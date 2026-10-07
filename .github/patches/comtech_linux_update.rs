// Comtech: installed Linux clients update themselves from our server.
//
// Only Client Builder instant builds (the ones with a comtech-build setting)
// take part. The root service asks the API every ten minutes whether this client's build
// has been remade from a newer base client. When it has, and nobody is
// connected, the package is downloaded, checked against the SHA-256 the API
// gave, and installed by a transient systemd unit: the package scripts stop
// and start the rustdesk service, which would kill an installer started from
// inside it.
use hbb_common::{bail, config::{self, Config}, log, ResultType};
use sha2::{Digest, Sha256};
use std::{
    io::Read,
    os::unix::fs::{DirBuilderExt, OpenOptionsExt},
    path::{Path, PathBuf},
    process::Command,
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const WORK_DIR: &str = "/var/lib/rustdesk-update";
const FIRST_CHECK: Duration = Duration::from_secs(60);
const CHECK_EVERY: Duration = Duration::from_secs(60 * 10);
// a version that was tried is left alone this long, so a package that won't
// install isn't downloaded again every ten minutes
const RETRY_AFTER: u64 = 60 * 60 * 6;

pub fn start() {
    if !crate::platform::is_installed() {
        return;
    }
    if std::env::var_os("APPIMAGE").is_some() || std::env::var_os("FLATPAK_ID").is_some() {
        return;
    }
    if !Path::new("/run/systemd/system").exists() {
        log::info!("comtech-update: this system doesn't run systemd, so updates are off");
        return;
    }
    let spawned = std::thread::Builder::new()
        .name("comtech-update".to_owned())
        .spawn(|| {
            std::thread::sleep(FIRST_CHECK);
            loop {
                if let Err(e) = check_guarded() {
                    log::error!("comtech-update: {}", e);
                }
                std::thread::sleep(CHECK_EVERY);
            }
        });
    if let Err(e) = spawned {
        log::error!("comtech-update: not started: {}", e);
    }
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default()
}

fn run_ok(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

// which package manager owns this install: deb, rpm, suse or arch
fn package_type() -> Option<&'static str> {
    if let Ok(out) = Command::new("dpkg-query")
        .args(["-W", "-f=${Status}", "rustdesk"])
        .output()
    {
        if String::from_utf8_lossy(&out.stdout).contains("install ok installed") {
            return Some("deb");
        }
    }
    if run_ok("rpm", &["-q", "rustdesk"]) {
        let os_release = std::fs::read_to_string("/etc/os-release").unwrap_or_default();
        let suse = os_release.lines().any(|l| {
            (l.starts_with("ID=") || l.starts_with("ID_LIKE=")) && l.to_lowercase().contains("suse")
        });
        return Some(if suse { "suse" } else { "rpm" });
    }
    if run_ok("pacman", &["-Q", "rustdesk"]) {
        return Some("arch");
    }
    None
}

struct Update {
    version: String,
    url: String,
    sha256: String,
    file: String,
}

// the Client Builder puts this in its instant builds' settings; they keep
// the RustDesk name, so it's what tells them from a stock install
fn build_uuid() -> String {
    config::HARD_SETTINGS
        .read()
        .unwrap()
        .get("comtech-build")
        .cloned()
        .unwrap_or_default()
}

fn ask_server(api: &str, pkg: &str) -> ResultType<Option<Update>> {
    let build = build_uuid();
    let url = format!(
        "{}/api/clientgen/linux-update-check?id={}&uuid={}&build={}&version={}&arch={}&pkg={}",
        api,
        Config::get_id(),
        crate::encode64(hbb_common::get_uuid()).replace('+', "%2B").replace('/', "%2F").replace('=', "%3D"),
        build,
        crate::VERSION,
        std::env::consts::ARCH,
        pkg
    );
    let client = crate::hbbs_http::create_http_client_with_url_strict(&url)?;
    let response = client.get(&url).send()?;
    if !response.status().is_success() {
        bail!("the update check failed: {}", response.status());
    }
    let body: serde_json::Value = serde_json::from_str(&response.text()?)?;
    let up = &body["update"];
    if up.is_null() {
        return Ok(None);
    }
    let field = |k: &str| up[k].as_str().unwrap_or_default().to_owned();
    let update = Update {
        version: field("version"),
        url: field("url"),
        sha256: field("sha256").to_lowercase(),
        file: field("file"),
    };
    if update.version.is_empty() || update.url.is_empty() || update.sha256.len() != 64 || update.file.is_empty() {
        bail!("the update check gave an incomplete answer");
    }
    Ok(Some(update))
}

fn work_dir() -> ResultType<PathBuf> {
    let dir = PathBuf::from(WORK_DIR);
    if !dir.is_dir() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir)?;
    }
    Ok(dir)
}

fn tried_recently(dir: &Path, version: &str) -> bool {
    let Ok(text) = std::fs::read_to_string(dir.join("state.json")) else {
        return false;
    };
    let Ok(state) = serde_json::from_str::<serde_json::Value>(&text) else {
        return false;
    };
    state["version"].as_str() == Some(version)
        && state["at"]
            .as_u64()
            .map(|at| now_secs().saturating_sub(at) < RETRY_AFTER)
            .unwrap_or(false)
}

fn write_state(dir: &Path, version: &str) -> ResultType<()> {
    let state = serde_json::json!({ "version": version, "at": now_secs() });
    std::fs::write(dir.join("state.json"), state.to_string())?;
    Ok(())
}

// true only when every reachable --server says it has no connections
fn is_idle() -> bool {
    let mut uids: Vec<u32> = Vec::new();
    if let Ok(uid) = crate::platform::linux::get_active_userid_fresh().trim().parse::<u32>() {
        uids.push(uid);
    }
    if !uids.contains(&0) {
        uids.push(0);
    }
    let Ok(rt) = hbb_common::tokio::runtime::Runtime::new() else {
        return false;
    };
    // None: no server could be reached
    let answer = rt.block_on(async {
        let mut answered = false;
        for uid in uids {
            let Ok(mut conn) = crate::ipc::connect_for_uid(1000, uid, "").await else {
                continue;
            };
            if conn
                .send(&crate::ipc::Data::HasNoActiveConns(None))
                .await
                .is_err()
            {
                return Some(false);
            }
            match conn.next_timeout(1000).await {
                Ok(Some(crate::ipc::Data::HasNoActiveConns(Some(true)))) => answered = true,
                _ => return Some(false),
            }
        }
        if answered {
            Some(true)
        } else {
            None
        }
    });
    match answer {
        Some(idle) => idle,
        // no server to ask: idle unless one is running anyway
        None => Command::new("pgrep")
            .args(["-f", "rustdesk --server"])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.code() == Some(1))
            .unwrap_or(false),
    }
}

fn download(update: &Update, api: &str, dir: &Path) -> ResultType<PathBuf> {
    if update.file.contains('/')
        || update.file.contains("..")
        || !update
            .file
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-')
    {
        bail!("the update's file name isn't plain: {}", update.file);
    }
    if !update.url.starts_with(&format!("{}/api/clientgen/update/", api)) {
        bail!("the update isn't offered by this client's server");
    }
    // only the package being installed is kept
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            if entry.file_name() != "state.json" {
                std::fs::remove_file(entry.path()).ok();
            }
        }
    }
    let path = dir.join(&update.file);
    let client = crate::hbbs_http::create_http_client_with_url_strict(&update.url)?;
    let mut response = client.get(&update.url).send()?;
    if !response.status().is_success() {
        bail!("the download failed: {}", response.status());
    }
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&path)?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 64 * 1024];
    loop {
        let n = response.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
        std::io::Write::write_all(&mut file, &buf[..n])?;
    }
    drop(file);
    let sum = format!("{:x}", hasher.finalize());
    if sum != update.sha256 {
        std::fs::remove_file(&path).ok();
        bail!("the downloaded {} doesn't match its checksum", update.file);
    }
    Ok(path)
}

fn install(pkg: &str, path: &Path) -> ResultType<()> {
    let path = path.to_string_lossy().to_string();
    let cmd: Vec<String> = match pkg {
        "deb" => {
            if Path::new("/usr/bin/apt-get").exists() {
                vec!["apt-get".into(), "install".into(), "-y".into(), "--allow-downgrades".into(), path]
            } else {
                vec!["dpkg".into(), "-i".into(), path]
            }
        }
        "rpm" => {
            if Path::new("/usr/bin/dnf").exists() {
                vec!["dnf".into(), "install".into(), "-y".into(), path]
            } else {
                vec!["yum".into(), "install".into(), "-y".into(), path]
            }
        }
        "suse" => vec![
            "zypper".into(),
            "--non-interactive".into(),
            "install".into(),
            "--allow-unsigned-rpm".into(),
            path,
        ],
        "arch" => vec!["pacman".into(), "-U".into(), "--noconfirm".into(), path],
        _ => bail!("unknown package type {}", pkg),
    };
    let unit = format!("comtech-rustdesk-update-{}", now_secs());
    let status = Command::new("systemd-run")
        .arg(format!("--unit={}", unit))
        .args(["--collect", "--quiet", "--no-block", "--setenv=DEBIAN_FRONTEND=noninteractive"])
        .args(&cmd)
        .status()?;
    if !status.success() {
        bail!("systemd-run couldn't start the install: {}", status);
    }
    log::info!("comtech-update: installing through {}", unit);
    Ok(())
}

// a scheduled check and one asked for by the Check for updates button must
// not run at once: the second finds the first still going and leaves it be
static CHECKING: AtomicBool = AtomicBool::new(false);

struct CheckGuard;

impl Drop for CheckGuard {
    fn drop(&mut self) {
        CHECKING.store(false, Ordering::SeqCst);
    }
}

fn check_guarded() -> ResultType<()> {
    if CHECKING.swap(true, Ordering::SeqCst) {
        return Ok(());
    }
    let _guard = CheckGuard;
    check_once()
}

// The Check for updates button: one check now, off the IPC thread. Only the
// root service installs updates, so a user's --server ignores the request.
pub fn check_now() {
    if unsafe { hbb_common::libc::geteuid() } != 0 {
        return;
    }
    let spawned = std::thread::Builder::new()
        .name("comtech-update-now".to_owned())
        .spawn(|| {
            if let Err(e) = check_guarded() {
                log::error!("comtech-update: {}", e);
            }
        });
    if let Err(e) = spawned {
        log::error!("comtech-update: check not started: {}", e);
    }
}

fn check_once() -> ResultType<()> {
    if build_uuid().is_empty() {
        return Ok(());
    }
    let Some(pkg) = package_type() else {
        return Ok(());
    };
    let api = crate::common::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    if api.is_empty() {
        return Ok(());
    }
    let Some(update) = ask_server(&api, pkg)? else {
        return Ok(());
    };
    let dir = work_dir()?;
    if tried_recently(&dir, &update.version) {
        return Ok(());
    }
    if !is_idle() {
        log::info!("comtech-update: {} is waiting for the connections to end", update.version);
        return Ok(());
    }
    let path = download(&update, &api, &dir)?;
    // somebody may have connected during the download
    if !is_idle() {
        log::info!("comtech-update: {} is downloaded, waiting for the connections to end", update.version);
        return Ok(());
    }
    write_state(&dir, &update.version)?;
    log::info!("comtech-update: updating to {}", update.version);
    install(pkg, &path)
}
