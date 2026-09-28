// Comtech: the single file installer reads its packed files from data
// attached to the end of its own exe, instead of compiling them in, so the
// Client Builder can brand an installer (settings, icons, logo) in seconds.
// Layout: payload (the usual data.bin), its length as u64 little endian,
// then the 8 bytes CTRDPKG1.
static PAYLOAD: std::sync::OnceLock<&'static [u8]> = std::sync::OnceLock::new();

fn bin_data() -> &'static [u8] {
    PAYLOAD.get_or_init(|| {
        use std::io::{Read, Seek, SeekFrom};
        const MAGIC: &[u8] = b"CTRDPKG1";
        let read = || -> Option<Vec<u8>> {
            let mut f = std::fs::File::open(std::env::current_exe().ok()?).ok()?;
            let size = f.seek(SeekFrom::End(0)).ok()?;
            if size < 16 {
                return None;
            }
            let mut tail = [0u8; 16];
            f.seek(SeekFrom::End(-16)).ok()?;
            f.read_exact(&mut tail).ok()?;
            if &tail[8..] != MAGIC {
                return None;
            }
            let len = u64::from_le_bytes(tail[..8].try_into().ok()?);
            if len > size - 16 {
                return None;
            }
            f.seek(SeekFrom::Start(size - 16 - len)).ok()?;
            let mut buf = vec![0u8; len as usize];
            f.read_exact(&mut buf).ok()?;
            Some(buf)
        };
        Box::leak(read().unwrap_or_default().into_boxed_slice())
    })
}
