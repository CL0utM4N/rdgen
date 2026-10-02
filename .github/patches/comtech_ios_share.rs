// Comtech: what the iPhone broadcast extension calls. Copied to
// src/comtech_ios.rs by comtech_patch.py --ios-share.
//
// The extension runs while the user broadcasts their screen. It starts
// RustDesk's sharing side here (register with the ID server, report to the
// API, take connections) and passes each screen frame in. iOS caps the
// extension's memory at about 50 MB, so frames are made smaller first.
use hbb_common::{config, log};
use std::ffi::{c_char, CStr};
use std::sync::{Mutex, Once};

static START: Once = Once::new();

fn cstr(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
}

/// The ID screen sharing uses, from the phone's identifierForVendor, which the
/// app and its extension share. The app shows the same number (FNV-1a of the
/// uppercase UUID text, into RustDesk's mobile ID range), so the user can read
/// it out even though the extension has no screen of its own.
pub fn share_id(vendor_id: &str) -> Option<String> {
    let v = vendor_id.trim().to_uppercase();
    if v.is_empty() {
        return None;
    }
    let mut h: u32 = 0x811c9dc5;
    for b in v.bytes() {
        h ^= b as u32;
        h = h.wrapping_mul(0x01000193);
    }
    Some((1_000_000_000u64 + (h as u64 % 1_000_000_000)).to_string())
}

/// Starts sharing. app_dir is a folder the extension can write to; custom is
/// the signed settings from the app's assets/custom.txt; vendor_id is the
/// phone's identifierForVendor; code is a one-time code to use, or empty to
/// make one. The code goes to the API under the vendor ID, where the app
/// (which shares that ID but can't read the extension's files) fetches it.
#[no_mangle]
pub extern "C" fn comtech_share_start(
    app_dir: *const c_char,
    custom: *const c_char,
    vendor_id: *const c_char,
    code: *const c_char,
    device_name: *const c_char,
) {
    let device_name = cstr(device_name);
    let app_dir = cstr(app_dir);
    let custom = cstr(custom);
    let vendor_id = cstr(vendor_id);
    let code = cstr(code);
    START.call_once(move || {
        remote_log::start();
        // the name the device list shows; the app normally sets it, and the
        // extension doesn't run the app
        *crate::common::DEVICE_NAME.lock().unwrap() = device_name;
        *config::APP_DIR.write().unwrap() = app_dir.clone();
        if !custom.trim().is_empty() {
            crate::read_custom_client(custom.trim());
        } else {
            log::warn!("comtech: no settings found in the app; sharing uses the built-in server");
        }
        // this session's one-time password, beside the build's permanent
        // password if it has one; the app shows it
        let code = if code.len() >= 6 { code } else { new_code() };
        *VENDOR.lock().unwrap() = vendor_id.clone();
        use_code(&code);
        if let Some(id) = share_id(&vendor_id) {
            if config::Config::get_id() != id {
                config::Config::set_id(&id);
            }
        }
        log::info!(
            "comtech: iOS sharing starting as {} (server {:?}, api {:?}, dir {})",
            config::Config::get_id(),
            config::Config::get_option("custom-rendezvous-server"),
            config::Config::get_option("api-server"),
            app_dir
        );
        // how connections will be let in (never the password itself)
        log::info!(
            "comtech: settings {} bytes; one-time code on; preset password {}, using it {}, local password {}; verification {:?}, approve {:?}",
            custom.trim().len(),
            !config::Config::get_preset_password_storage_and_salt().0.is_empty(),
            config::Config::is_using_preset_password(),
            config::Config::has_local_permanent_password(),
            config::Config::get_option("verification-method"),
            config::Config::get_option("approve-mode"),
        );
        std::thread::spawn(|| crate::start_server(true));
    });
}

lazy_static::lazy_static! {
    static ref VENDOR: Mutex<String> = Mutex::new(String::new());
}

fn new_code() -> String {
    use hbb_common::rand::Rng;
    format!("{:06}", hbb_common::rand::thread_rng().gen_range(0..1_000_000))
}

/// Lets the code in as a one-time password and tells the API, so the app
/// can show it
fn use_code(code: &str) {
    *hbb_common::password_security::TEMPORARY_PASSWORD.write().unwrap() = code.to_owned();
    config::OVERWRITE_SETTINGS
        .write()
        .unwrap()
        .insert("verification-method".to_owned(), "use-both-passwords".to_owned());
    publish_code(code);
}

fn publish_code(code: &str) {
    let vendor = VENDOR.lock().unwrap().clone();
    if vendor.is_empty() {
        return;
    }
    let body = serde_json::json!({ "vendor": vendor, "code": code }).to_string();
    let clearing = code.is_empty();
    let send = move || {
        if !remote_log::post("/api/comtech/ios-code", body) {
            log::warn!("comtech: the one-time code couldn't be sent to the API");
        }
    };
    if clearing {
        send(); // the extension is about to end
    } else {
        std::thread::spawn(send);
    }
}

/// A new one-time code during the broadcast
#[no_mangle]
pub extern "C" fn comtech_share_set_code(code: *const c_char) {
    let code = cstr(code);
    if code.len() >= 6 {
        use_code(&code);
        log::info!("comtech: new one-time code");
    }
}

/// The broadcast stopped: the code stops working, and what's left of the
/// log is sent
#[no_mangle]
pub extern "C" fn comtech_share_stop() {
    log::info!("comtech: iOS sharing stopped");
    publish_code("");
    remote_log::flush();
}

/// The extension has no screen and its files can't be read from outside, so
/// it sends its log to the API server, which keeps it with the device's ID.
mod remote_log {
    use hbb_common::{config, log};
    use std::sync::Mutex;

    lazy_static::lazy_static! {
        static ref LINES: Mutex<Vec<String>> = Mutex::new(Vec::new());
    }

    struct Logger;

    impl log::Log for Logger {
        fn enabled(&self, m: &log::Metadata) -> bool {
            m.level() <= log::Level::Info
        }

        fn log(&self, r: &log::Record) {
            if !self.enabled(r.metadata()) {
                return;
            }
            let mut l = LINES.lock().unwrap();
            if l.len() < 400 {
                l.push(format!("{} {}: {}", r.level(), r.target(), r.args()));
            }
        }

        fn flush(&self) {}
    }

    pub fn start() {
        if log::set_boxed_logger(Box::new(Logger)).is_ok() {
            log::set_max_level(log::LevelFilter::Info);
        }
        std::thread::spawn(|| loop {
            std::thread::sleep(std::time::Duration::from_secs(5));
            flush();
        });
    }

    pub fn flush() {
        let lines: Vec<String> = std::mem::take(&mut *LINES.lock().unwrap());
        if lines.is_empty() {
            return;
        }
        let body = serde_json::json!({
            "id": config::Config::get_id(),
            "uuid": crate::encode64(hbb_common::get_uuid()),
            "lines": lines,
        })
        .to_string();
        post("/api/comtech/ios-log", body);
    }

    /// Posts JSON to the API server; false when it couldn't
    pub fn post(path: &str, body: String) -> bool {
        let api = crate::common::get_api_server(
            config::Config::get_option("api-server"),
            config::Config::get_option("custom-rendezvous-server"),
        );
        if api.is_empty() {
            return false;
        }
        let url = format!("{}{}", api.trim_end_matches('/'), path);
        match hbb_common::tokio::runtime::Builder::new_current_thread().enable_all().build() {
            Ok(rt) => rt.block_on(crate::post_request(url, body, "Content-Type: application/json")).is_ok(),
            Err(_) => false,
        }
    }
}

/// This device's RustDesk ID, written into buf (with a trailing NUL)
#[no_mangle]
pub extern "C" fn comtech_share_id(buf: *mut c_char, len: usize) -> usize {
    let id = config::Config::get_id();
    if buf.is_null() || len == 0 {
        return id.len();
    }
    let n = id.len().min(len - 1);
    unsafe {
        std::ptr::copy_nonoverlapping(id.as_ptr() as *const c_char, buf, n);
        *buf.add(n) = 0;
    }
    n
}

struct Buffers {
    i420: Vec<u8>,
    small: Vec<u8>,
    bgra: Vec<u8>,
}

lazy_static::lazy_static! {
    static ref BUFFERS: Mutex<Buffers> = Mutex::new(Buffers { i420: Vec::new(), small: Vec::new(), bgra: Vec::new() });
}

/// A screen frame as iOS gives it: NV12 (a Y plane and an interleaved UV
/// plane). Phone screens are halved, keeping the shared picture readable
/// while staying inside the extension's memory.
#[no_mangle]
pub extern "C" fn comtech_share_frame_nv12(
    y: *const u8,
    y_stride: i32,
    uv: *const u8,
    uv_stride: i32,
    width: i32,
    height: i32,
) {
    if y.is_null() || uv.is_null() || width < 2 || height < 2 {
        return;
    }
    let (w, h) = (width as usize & !1, height as usize & !1);
    let (dw, dh) = if w.max(h) > 1600 { ((w / 2) & !1, (h / 2) & !1) } else { (w, h) };
    let mut b = BUFFERS.lock().unwrap();
    let Buffers { i420, small, bgra } = &mut *b;
    let (cw, ch) = (w / 2, h / 2);
    i420.resize(w * h + cw * ch * 2, 0);
    let (iy, rest) = i420.split_at_mut(w * h);
    let (iu, iv) = rest.split_at_mut(cw * ch);
    unsafe {
        scrap::NV12ToI420(
            y, y_stride, uv, uv_stride,
            iy.as_mut_ptr(), w as _, iu.as_mut_ptr(), cw as _, iv.as_mut_ptr(), cw as _,
            w as _, h as _,
        );
    }
    let (sw, sh) = (dw / 2, dh / 2);
    let (py, pu, pv);
    if (dw, dh) != (w, h) {
        small.resize(dw * dh + sw * sh * 2, 0);
        let (sy, rest) = small.split_at_mut(dw * dh);
        let (su, sv) = rest.split_at_mut(sw * sh);
        unsafe {
            scrap::I420Scale(
                iy.as_ptr(), w as _, iu.as_ptr(), cw as _, iv.as_ptr(), cw as _, w as _, h as _,
                sy.as_mut_ptr(), dw as _, su.as_mut_ptr(), sw as _, sv.as_mut_ptr(), sw as _, dw as _, dh as _,
                scrap::FilterMode::kFilterBilinear,
            );
        }
        py = sy.as_ptr();
        pu = su.as_ptr();
        pv = sv.as_ptr();
    } else {
        py = iy.as_ptr();
        pu = iu.as_ptr();
        pv = iv.as_ptr();
    }
    bgra.resize(dw * dh * 4, 0);
    unsafe {
        // libyuv's ARGB is B, G, R, A in memory
        scrap::I420ToARGB(py, dw as _, pu, sw as _, pv, sw as _, bgra.as_mut_ptr(), (dw * 4) as _, dw as _, dh as _);
    }
    scrap::ios_set_frame(bgra, dw, dh);
}
