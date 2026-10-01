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

/// Starts sharing. app_dir is a folder the extension can write to; custom is
/// the signed settings from the app's assets/custom.txt.
#[no_mangle]
pub extern "C" fn comtech_share_start(app_dir: *const c_char, custom: *const c_char) {
    let app_dir = cstr(app_dir);
    let custom = cstr(custom);
    START.call_once(move || {
        *config::APP_DIR.write().unwrap() = app_dir;
        if !custom.trim().is_empty() {
            crate::read_custom_client(custom.trim());
        }
        log::info!("comtech: iOS sharing starting as {}", config::Config::get_id());
        std::thread::spawn(|| crate::start_server(true));
    });
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
