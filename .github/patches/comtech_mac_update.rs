// Comtech: installed Macs update themselves from our server, when asked.
//
// This replaces RustDesk's own Mac updater, which refuses app names with
// spaces and puts the name into shell commands without quotes.
//
// Only Client Builder instant builds (the ones with a comtech-build setting)
// take part, and only when someone pressed Update now in the console: the
// builds are signed ad hoc, so macOS asks for Screen Recording and
// Accessibility permission again after every update and someone has to be
// at the Mac. The root service asks the API every ten minutes. The API only
// has an answer while Update now is waiting, and the request stays queued
// until this Mac has started updating. When nobody is connected the zip is
// downloaded, checked against the SHA-256 the API gave and against the app
// itself, and a detached script swaps the app in and restarts the services.
use hbb_common::{bail, config::{self, Config}, log, ResultType};
use sha2::{Digest, Sha256};
use std::{
    io::Read,
    os::unix::{
        fs::{OpenOptionsExt, PermissionsExt},
        process::CommandExt,
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Duration,
};

const FIRST_CHECK: Duration = Duration::from_secs(60);
const CHECK_EVERY: Duration = Duration::from_secs(60 * 10);
const LOG_FILE: &str = "/Library/Logs/comtech-update.log";

pub fn start() {
    let spawned = std::thread::Builder::new()
        .name("comtech-update".to_owned())
        .spawn(|| {
            std::thread::sleep(FIRST_CHECK);
            loop {
                if let Err(e) = check_once() {
                    log::error!("comtech-update: {}", e);
                }
                std::thread::sleep(CHECK_EVERY);
            }
        });
    if let Err(e) = spawned {
        log::error!("comtech-update: not started: {}", e);
    }
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

fn encoded_uuid() -> String {
    crate::encode64(hbb_common::get_uuid())
        .replace('+', "%2B")
        .replace('/', "%2F")
        .replace('=', "%3D")
}

fn ask_server(api: &str) -> ResultType<Option<Update>> {
    let url = format!(
        "{}/api/clientgen/mac-update-check?id={}&uuid={}&build={}&version={}&arch={}",
        api,
        Config::get_id(),
        encoded_uuid(),
        build_uuid(),
        crate::VERSION,
        std::env::consts::ARCH
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
    if update.version.is_empty() || update.url.is_empty() || update.file.is_empty() {
        bail!("the update check gave an incomplete answer");
    }
    if update.sha256.len() != 64 || !update.sha256.chars().all(|c| c.is_ascii_hexdigit()) {
        bail!("the update check gave a bad checksum");
    }
    if !update.file.ends_with(".zip")
        || update.file.contains('/')
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
    Ok(Some(update))
}

// shell single quotes: nothing inside is special except the quote itself
fn sh_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

// Every value comes in once, quoted, at the top; the steps below only use
// "$VAR". It runs detached, because the swap stops the service that starts it.
const SCRIPT_BODY: &str = r#"
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
exec >>"$LOG" 2>&1
echo "=== updating $APP: $(date) ==="
sleep 2

bootstrap_agent() {
    uid="$1"
    if [ "$uid" != "0" ]; then
        launchctl bootstrap gui/"$uid" "$AGENT_PLIST" || \
            launchctl bootstrap user/"$uid" "$AGENT_PLIST" || \
            launchctl load -w "$AGENT_PLIST"
    else
        # the login window has no gui/0 domain
        launchctl load -w -S LoginWindow "$AGENT_PLIST" || \
            launchctl load -w "$AGENT_PLIST"
    fi
}

bootstrap_agents() {
    for uid in $UIDS; do
        bootstrap_agent "$uid" || return 1
    done
}

rollback() {
    echo "the update failed, putting the old app back"
    if [ -d "$BUNDLE.bak" ]; then
        rm -rf "$BUNDLE"
        mv "$BUNDLE.bak" "$BUNDLE"
    fi
    launchctl bootstrap system "$DAEMON_PLIST"
    bootstrap_agents
    rm -rf "$TMP"
    exit 1
}

for uid in $UIDS; do
    if [ "$uid" != "0" ]; then
        launchctl bootout gui/"$uid"/"$AGENT_LABEL" || \
            launchctl bootout user/"$uid"/"$AGENT_LABEL" || true
    else
        launchctl unload -w -S LoginWindow "$AGENT_PLIST" || true
        launchctl bootout user/0/"$AGENT_LABEL" || true
        launchctl bootout system/"$AGENT_LABEL" || true
    fi
done
launchctl bootout system/"$DAEMON_LABEL" || true
sleep 2
ps -axo pid=,args= | grep -F "$BUNDLE/Contents/MacOS/" | grep -v grep | awk '{print $1}' | while read -r pid; do
    kill "$pid" 2>/dev/null || true
done
sleep 1

rm -rf "$BUNDLE.bak"
mv "$BUNDLE" "$BUNDLE.bak" || rollback
ditto "$NEW" "$BUNDLE" || rollback
chown -R root:wheel "$BUNDLE" || rollback
chmod -R go-w "$BUNDLE" || rollback
xattr -r -d com.apple.quarantine "$BUNDLE" || true

launchctl bootstrap system "$DAEMON_PLIST" || rollback
bootstrap_agents || rollback

echo "updated"
rm -rf "$BUNDLE.bak" "$TMP"
exit 0
"#;

fn render_script(vars: &[(&str, &str)]) -> String {
    let mut script = String::from("#!/bin/sh\n");
    for (name, value) in vars {
        script.push_str(&format!("{}={}\n", name, sh_quote(value)));
    }
    script.push_str(SCRIPT_BODY);
    script
}

fn run_output(cmd: &str, args: &[&str]) -> ResultType<String> {
    let out = Command::new(cmd).args(args).output()?;
    if !out.status.success() {
        bail!(
            "{} failed: {}",
            cmd,
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

fn make_temp_dir() -> ResultType<PathBuf> {
    let dir = run_output("/usr/bin/mktemp", &["-d", "/tmp/.comtech-update-XXXXXX"])?;
    if dir.is_empty() {
        bail!("couldn't make a temporary folder");
    }
    let dir = PathBuf::from(dir);
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))?;
    Ok(dir)
}

fn download(update: &Update, dir: &Path) -> ResultType<PathBuf> {
    let path = dir.join(&update.file);
    let client = crate::hbbs_http::create_http_client_with_url_strict(&update.url)?;
    let mut response = client.get(&update.url).send()?;
    if !response.status().is_success() {
        bail!("the download failed: {}", response.status());
    }
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
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
        bail!("the downloaded {} doesn't match its checksum", update.file);
    }
    Ok(path)
}

// downloads and checks the new app, then hands over to the swap script;
// false means somebody is connected and nothing was started
fn stage_and_launch(update: &Update, api: &str, tmp: &Path, app_name: &str) -> ResultType<bool> {
    let zip = download(update, tmp)?;
    let new_dir = tmp.join("new");
    run_output(
        "/usr/bin/ditto",
        &["-x", "-k", &zip.to_string_lossy(), &new_dir.to_string_lossy()],
    )?;
    let new_app = new_dir.join(format!("{}.app", app_name));
    if !new_app.is_dir() {
        bail!("the update has no {}.app in it", app_name);
    }
    let new_app = new_app.to_string_lossy().to_string();
    let version = run_output(
        "/usr/libexec/PlistBuddy",
        &[
            "-c",
            "Print :CFBundleShortVersionString",
            &format!("{}/Contents/Info.plist", new_app),
        ],
    )?;
    if version != update.version {
        bail!("the update is version {}, not {}", version, update.version);
    }
    run_output("/usr/bin/codesign", &["--verify", "--deep", "--strict", &new_app])?;
    // somebody may have connected during the download
    if !crate::updater::has_no_active_conns_ipc() {
        log::info!("comtech-update: {} is downloaded, waiting for the connections to end", update.version);
        return Ok(false);
    }

    let daemon_label = format!("com.carriez.{}_service", app_name);
    let agent_label = format!("com.carriez.{}_server", app_name);
    let daemon_plist = format!("/Library/LaunchDaemons/{}.plist", daemon_label);
    let agent_plist = format!("/Library/LaunchAgents/{}.plist", agent_label);
    if !Path::new(&daemon_plist).is_file() || !Path::new(&agent_plist).is_file() {
        bail!("this app isn't installed as a service");
    }
    let uids = crate::platform::get_logged_in_uids()
        .iter()
        .map(|u| u.to_string())
        .collect::<Vec<_>>()
        .join(" ");
    let bundle = format!("/Applications/{}.app", app_name);
    let tmp_str = tmp.to_string_lossy().to_string();
    let script = render_script(&[
        ("APP", app_name),
        ("BUNDLE", &bundle),
        ("NEW", &new_app),
        ("TMP", &tmp_str),
        ("DAEMON_LABEL", &daemon_label),
        ("AGENT_LABEL", &agent_label),
        ("DAEMON_PLIST", &daemon_plist),
        ("AGENT_PLIST", &agent_plist),
        ("UIDS", &uids),
        ("LOG", LOG_FILE),
    ]);
    let script_path = tmp.join("update.sh");
    {
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o700)
            .open(&script_path)?;
        std::io::Write::write_all(&mut f, script.as_bytes())?;
    }

    // the server stops asking this Mac once it knows the update has started
    let done = format!(
        "{}/api/clientgen/mac-update-done?id={}&uuid={}",
        api,
        Config::get_id(),
        encoded_uuid()
    );
    let told = crate::hbbs_http::create_http_client_with_url_strict(&done)
        .and_then(|client| Ok(client.post(&done).send()?))
        .map(|r| r.status().is_success())
        .unwrap_or(false);
    if !told {
        log::error!("comtech-update: couldn't tell the server the update has started");
    }

    log::info!("comtech-update: updating to {}", update.version);
    // its own session, so it outlives the service it stops
    let mut cmd = Command::new("/bin/sh");
    cmd.arg(&script_path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    unsafe {
        cmd.pre_exec(|| {
            hbb_common::libc::setsid();
            Ok(())
        });
    }
    cmd.spawn()?;
    Ok(true)
}

fn check_once() -> ResultType<()> {
    if build_uuid().is_empty() {
        return Ok(());
    }
    // only an installed app can be swapped
    if !std::env::current_exe()?.starts_with("/Applications/") {
        return Ok(());
    }
    let api = crate::common::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    if api.is_empty() {
        return Ok(());
    }
    let Some(update) = ask_server(&api)? else {
        return Ok(());
    };
    // the request stays queued on the server, so the next round tries again
    if !crate::updater::has_no_active_conns_ipc() {
        log::info!("comtech-update: {} is waiting for the connections to end", update.version);
        return Ok(());
    }
    let app_name = crate::get_app_name();
    let tmp = make_temp_dir()?;
    match stage_and_launch(&update, &api, &tmp, &app_name) {
        Ok(true) => Ok(()),
        other => {
            std::fs::remove_dir_all(&tmp).ok();
            other.map(|_| ())
        }
    }
}
