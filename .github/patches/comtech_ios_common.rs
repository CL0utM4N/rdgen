// Comtech: the device name the server reports for iOS screen sharing
// (comtech_patch.py --ios-share); the desktop version needs a crate iOS
// builds don't have
#[cfg(target_os = "ios")]
pub fn whoami_hostname() -> String {
    hbb_common::whoami::devicename()
}
