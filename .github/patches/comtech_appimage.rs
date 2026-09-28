
// Comtech: an AppImage is a compressed filesystem the Client Builder can't
// change, so it attaches the signed settings to the end of the AppImage:
// settings, their length (u64 little endian), then CTRDCFG1. The AppImage
// runtime sets APPIMAGE to the file's path.
#[cfg(target_os = "linux")]
fn comtech_appimage_settings() -> Option<String> {
    use std::io::{Read, Seek, SeekFrom};
    let path = std::env::var("APPIMAGE").ok()?;
    let mut f = std::fs::File::open(path).ok()?;
    let size = f.seek(SeekFrom::End(0)).ok()?;
    if size < 16 {
        return None;
    }
    let mut tail = [0u8; 16];
    f.seek(SeekFrom::End(-16)).ok()?;
    f.read_exact(&mut tail).ok()?;
    if &tail[8..] != b"CTRDCFG1" {
        return None;
    }
    let len = u64::from_le_bytes(tail[..8].try_into().ok()?);
    if len > (1 << 20) || len > size - 16 {
        return None;
    }
    f.seek(SeekFrom::Start(size - 16 - len)).ok()?;
    let mut buf = vec![0u8; len as usize];
    f.read_exact(&mut buf).ok()?;
    String::from_utf8(buf).ok().map(|s| s.trim().to_owned())
}
