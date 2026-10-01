// Comtech: RustDesk's server hands taps and keys to Android's service; iOS
// lets no app control the device, so they go nowhere
// (comtech_patch.py --ios-share)
#[cfg(target_os = "ios")]
pub mod android {
    pub fn call_main_service_pointer_input(_kind: &str, _mask: i32, _x: i32, _y: i32) -> hbb_common::ResultType<()> {
        Ok(())
    }

    pub fn call_main_service_key_event(_data: &[u8]) -> hbb_common::ResultType<()> {
        Ok(())
    }
}
