
// Comtech: the updater asks our API instead of rustdesk.com. The API answers
// with a .../tag/<version> URL when this client's build has been remade from
// a newer base client, and the updater downloads that installer from
// .../download/<version>/rustdesk-<version>-<arch>.exe as usual.
fn comtech_update_check_url() -> String {
    let api = get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    let build = config::HARD_SETTINGS
        .read()
        .unwrap()
        .get("comtech-build")
        .cloned()
        .unwrap_or_default();
    format!(
        "{}/api/clientgen/update-check?id={}&uuid={}&build={}&version={}&arch={}",
        api,
        Config::get_id(),
        crate::encode64(hbb_common::get_uuid()).replace('+', "%2B").replace('/', "%2F").replace('=', "%3D"),
        build,
        crate::VERSION,
        std::env::consts::ARCH
    )
}
