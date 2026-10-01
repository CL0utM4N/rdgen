// Comtech: iPhone and iPad screens for RustDesk's sharing side. Copied to
// libs/scrap/src/common/ios.rs by comtech_patch.py --ios-share.
//
// iOS gives no app a way to capture the screen; while the user broadcasts
// (Control Center → Screen Recording → the app), iOS hands frames to the
// app's broadcast extension, which passes them here with ios_set_frame. The
// video service then reads them like any other capturer's.
use crate::{Frame, Pixfmt};
use lazy_static::lazy_static;
use std::sync::Mutex;
use std::{io, time::Duration};

struct Latest {
    bgra: Vec<u8>,
    width: usize,
    height: usize,
    seq: u64,
}

lazy_static! {
    static ref LATEST: Mutex<Latest> = Mutex::new(Latest { bgra: Vec::new(), width: 0, height: 0, seq: 0 });
}

/// The newest frame, BGRA with no row padding
pub fn ios_set_frame(bgra: &[u8], width: usize, height: usize) {
    if width == 0 || height == 0 || bgra.len() < width * height * 4 {
        return;
    }
    let mut l = LATEST.lock().unwrap();
    l.bgra.clear();
    l.bgra.extend_from_slice(&bgra[..width * height * 4]);
    l.width = width;
    l.height = height;
    l.seq = l.seq.wrapping_add(1);
}

/// The size of the frames being shared, or (0, 0) before the first one
pub fn ios_frame_size() -> (usize, usize) {
    let l = LATEST.lock().unwrap();
    (l.width, l.height)
}

pub struct Capturer {
    display: Display,
    bgra: Vec<u8>,
    width: usize,
    height: usize,
    seen: u64,
}

impl Capturer {
    pub fn new(display: Display) -> io::Result<Capturer> {
        Ok(Capturer { display, bgra: Vec::new(), width: 0, height: 0, seen: 0 })
    }

    pub fn width(&self) -> usize {
        self.display.width()
    }

    pub fn height(&self) -> usize {
        self.display.height()
    }
}

impl crate::TraitCapturer for Capturer {
    fn frame<'a>(&'a mut self, _timeout: Duration) -> io::Result<Frame<'a>> {
        {
            let l = LATEST.lock().unwrap();
            // the display's size is fixed for this capturer; a rotated
            // screen restarts the video service with a new one
            if l.seq == self.seen || l.width != self.display.width() || l.height != self.display.height() {
                return Err(io::ErrorKind::WouldBlock.into());
            }
            self.seen = l.seq;
            self.bgra.clear();
            self.bgra.extend_from_slice(&l.bgra);
            self.width = l.width;
            self.height = l.height;
        }
        Ok(Frame::PixelBuffer(PixelBuffer {
            data: &self.bgra,
            width: self.width,
            height: self.height,
            stride: vec![self.width * 4],
        }))
    }
}

pub struct PixelBuffer<'a> {
    data: &'a [u8],
    width: usize,
    height: usize,
    stride: Vec<usize>,
}

impl<'a> crate::TraitPixelBuffer for PixelBuffer<'a> {
    fn data(&self) -> &[u8] {
        self.data
    }

    fn width(&self) -> usize {
        self.width
    }

    fn height(&self) -> usize {
        self.height
    }

    fn stride(&self) -> Vec<usize> {
        self.stride.clone()
    }

    fn pixfmt(&self) -> Pixfmt {
        Pixfmt::BGRA
    }
}

pub struct Display {
    width: usize,
    height: usize,
}

impl Display {
    pub fn primary() -> io::Result<Display> {
        let (width, height) = ios_frame_size();
        Ok(Display { width, height })
    }

    pub fn all() -> io::Result<Vec<Display>> {
        Ok(vec![Display::primary()?])
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    pub fn origin(&self) -> (i32, i32) {
        (0, 0)
    }

    pub fn is_online(&self) -> bool {
        true
    }

    pub fn is_primary(&self) -> bool {
        true
    }

    pub fn name(&self) -> String {
        "iOS".into()
    }
}
