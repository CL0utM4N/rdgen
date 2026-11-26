// Comtech: installed Windows clients update themselves from our server.
//
// RustDesk 1.5.3's own updater only accepts github.com release pages and
// installs the official RustDesk, so its check_update hands over to this when
// the client was made by our Client Builder. The API says whether this
// client's build has been remade from a newer base client (a newer RustDesk
// version, or a rebuilt base of the same version). If so the installer is
// downloaded, checked against the size and SHA-256 the API gave, and run the
// same way RustDesk runs its own update.
#[cfg(target_os = "windows")]
fn comtech_check_update() -> ResultType<()> {
    let build = config::HARD_SETTINGS
        .read()
        .unwrap()
        .get("comtech-build")
        .cloned()
        .unwrap_or_default();
    // an empty build is fine: the server then uses the customer's newest build
    let base = config::HARD_SETTINGS
        .read()
        .unwrap()
        .get("comtech-base")
        .cloned()
        .unwrap_or_default();
    let api = crate::common::get_api_server(
        config::Config::get_option("api-server"),
        config::Config::get_option("custom-rendezvous-server"),
    );
    if api.is_empty() {
        log::debug!("comtech: no API server, so no update check");
        return Ok(());
    }
    let url = format!(
        "{}/api/clientgen/win-update-check?id={}&uuid={}&build={}&base={}&version={}",
        api,
        config::Config::get_id(),
        crate::encode64(hbb_common::get_uuid())
            .replace('+', "%2B")
            .replace('/', "%2F")
            .replace('=', "%3D"),
        build,
        base,
        crate::VERSION
    );
    log::debug!("comtech: checking for an update");
    let client = crate::hbbs_http::create_http_client_with_url_strict(&url)?;
    let response = client.get(&url).send()?;
    if !response.status().is_success() {
        bail!("comtech: the update check failed: {}", response.status());
    }
    let body: serde_json::Value = serde_json::from_str(&response.text()?)?;
    let field = |k: &str| body[k].as_str().unwrap_or_default().to_owned();
    let download_url = field("url");
    if download_url.is_empty() {
        log::debug!("comtech: no update available");
        return Ok(());
    }
    let version = field("version");
    let sha256 = field("sha256").to_lowercase();
    let size = body["size"].as_u64().unwrap_or_default();
    if version.is_empty() || sha256.len() != 64 || size == 0 {
        bail!("comtech: the update check gave an incomplete answer");
    }
    if !download_url.starts_with(&format!("{}/api/clientgen/update/", api)) {
        bail!("comtech: the update isn't offered by this client's server");
    }
    // a plain file name, kept in a folder of our own under the temp folder
    let mut name: String = field("file")
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | ' ' | '-'))
        .collect();
    if name.is_empty() || name.contains("..") {
        name = "update.exe".to_owned();
    }
    if !name.to_lowercase().ends_with(".exe") {
        name.push_str(".exe");
    }
    let dir = std::env::temp_dir().join("comtech-update");
    std::fs::create_dir_all(&dir)?;
    let file_path = dir.join(&name);
    log::info!("comtech: downloading {} for the update", version);
    ensure_verified_update_artifact(&download_url, &file_path, size, &sha256)?;
    // somebody may have connected during the download
    if has_no_active_conns() {
        log::info!("comtech: updating to {}", version);
        update_new_version(false, &version, &file_path, &sha256);
    } else {
        log::info!("comtech: {} is downloaded, waiting for the connections to end", version);
    }
    Ok(())
}
