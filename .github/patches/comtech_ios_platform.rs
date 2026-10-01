// Comtech: what RustDesk's server asks of the platform, for iOS screen
// sharing (comtech_patch.py --ios-share)
#[cfg(target_os = "ios")]
pub fn get_active_username() -> String {
    "ios".into()
}

#[cfg(target_os = "ios")]
#[derive(Default)]
pub struct WakeLock;

// the broadcast keeps the screen on by itself
#[cfg(target_os = "ios")]
pub fn get_wakelock(_display: bool) -> WakeLock {
    WakeLock
}

#[cfg(target_os = "ios")]
pub fn resolutions(_name: &str) -> Vec<hbb_common::message_proto::Resolution> {
    Vec::new()
}
