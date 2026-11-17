// Comtech: the single file installer reads its packed files from data
// attached to the end of its own exe, instead of compiling them in, so the
// Client Builder can brand an installer (settings, icons, logo) in seconds.
// Layout: payload (the usual data.bin), its length as u64 little endian,
// then the 8 bytes CTRDPKG1.
// The server may sign the installer (Authenticode). A signature is a
// certificate table added after all of that, so we look for the trailer
// just before it. The marker below lets the server tell stubs that can
// cope with a signature from older ones that can't.
#[used]
static COMTECH_SIGNABLE: [u8; 20] = *b"CTRDPKG-SIGNABLE-V1\0";

static PAYLOAD: std::sync::OnceLock<&'static [u8]> = std::sync::OnceLock::new();

// Where the package data ends: the start of the Authenticode certificate
// table when it is the last thing in the file, else the end of the file.
// Anything unexpected in the exe's headers just means the end of the file.
#[allow(dead_code)]
fn comtech_pack_end<F: std::io::Read + std::io::Seek>(f: &mut F, size: u64) -> u64 {
    use std::io::SeekFrom;
    let find = |f: &mut F| -> Option<u64> {
        let u32_at = |f: &mut F, pos: u64| -> Option<u32> {
            let mut b = [0u8; 4];
            f.seek(SeekFrom::Start(pos)).ok()?;
            f.read_exact(&mut b).ok()?;
            Some(u32::from_le_bytes(b))
        };
        let pe = u32_at(f, 0x3C)? as u64;
        if u32_at(f, pe)? != 0x0000_4550 {
            return None;
        }
        // optional header starts 24 bytes into the PE header
        let opt = pe + 24;
        let mut m = [0u8; 2];
        f.seek(SeekFrom::Start(opt)).ok()?;
        f.read_exact(&mut m).ok()?;
        let dirs = match u16::from_le_bytes(m) {
            0x10b => 96,
            0x20b => 112,
            _ => return None,
        };
        // the security directory is data directory number 4
        let at = opt + dirs + 4 * 8;
        let off = u32_at(f, at)? as u64;
        let len = u32_at(f, at + 4)? as u64;
        if off > 0 && len > 0 && off + len == size {
            Some(off)
        } else {
            None
        }
    };
    find(f).unwrap_or(size)
}

fn bin_data() -> &'static [u8] {
    PAYLOAD.get_or_init(|| {
        use std::io::{Read, Seek, SeekFrom};
        const MAGIC: &[u8] = b"CTRDPKG1";
        std::hint::black_box(&COMTECH_SIGNABLE);
        let read = || -> Option<Vec<u8>> {
            let mut f = std::fs::File::open(std::env::current_exe().ok()?).ok()?;
            let size = f.seek(SeekFrom::End(0)).ok()?;
            let mut end = comtech_pack_end(&mut f, size);
            // signing pads up to 7 zero bytes before the certificate table
            if end != size {
                let mut pad = 0;
                while pad < 7 && end > 16 {
                    let mut b = [0u8; 1];
                    f.seek(SeekFrom::Start(end - 1)).ok()?;
                    f.read_exact(&mut b).ok()?;
                    if b[0] != 0 {
                        break;
                    }
                    end -= 1;
                    pad += 1;
                }
            }
            if end < 16 {
                return None;
            }
            let mut tail = [0u8; 16];
            f.seek(SeekFrom::Start(end - 16)).ok()?;
            f.read_exact(&mut tail).ok()?;
            if &tail[8..] != MAGIC {
                return None;
            }
            let len = u64::from_le_bytes(tail[..8].try_into().ok()?);
            if len > end - 16 {
                return None;
            }
            f.seek(SeekFrom::Start(end - 16 - len)).ok()?;
            let mut buf = vec![0u8; len as usize];
            f.read_exact(&mut buf).ok()?;
            Some(buf)
        };
        Box::leak(read().unwrap_or_default().into_boxed_slice())
    })
}
