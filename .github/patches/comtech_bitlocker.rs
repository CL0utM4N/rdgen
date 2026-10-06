
// Comtech: installed Windows clients escrow their BitLocker recovery keys to
// our API, so a technician can unlock a machine stuck on the blue recovery
// screen. The server stores them encrypted and audit-logs every reveal; the
// client only ever reports the keys that already exist on a drive -- it never
// adds a protector to a drive that lacks one. The server asks for a report by
// returning "comtech_bitlocker": true in a heartbeat reply (see sync.rs).
#[cfg(windows)]
mod imp {
    use hbb_common::config::{Config, HARD_SETTINGS};
    use serde_json::{json, Value};
    use std::io::Read;
    use std::os::windows::process::CommandExt;
    use std::process::{Command, Stdio};
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::{Duration, Instant};

    // Only one report is ever collected at a time: the heartbeat can ask again
    // before the first PowerShell run has finished.
    static IN_FLIGHT: AtomicBool = AtomicBool::new(false);

    struct Guard;
    impl Drop for Guard {
        fn drop(&mut self) {
            IN_FLIGHT.store(false, Ordering::SeqCst);
        }
    }

    // Enumerate every fixed drive, not just C:. PowerShell (not manage-bde text)
    // because its output doesn't shift with the Windows display language and it
    // works on Home editions. Key protector type 3 == numerical password.
    const SCRIPT: &str = r#"$ErrorActionPreference='Stop'
$out=@()
foreach ($v in Get-WmiObject -Namespace 'root/cimv2/security/microsoftvolumeencryption' -Class Win32_EncryptableVolume) {
  $prot = $v.GetProtectionStatus().ProtectionStatus
  $keys=@()
  foreach ($id in $v.GetKeyProtectors(3).VolumeKeyProtectorID) {
    $pw = $v.GetKeyProtectorNumericalPassword($id).NumericalPassword
    if ($pw) { $keys += @{ id=$id; password=$pw } }
  }
  $out += @{ volume=$v.DeviceID; mount=$v.DriveLetter; protection=[int]$prot; volume_type=[int]$v.VolumeType; keys=$keys }
}
@{ volumes=$out } | ConvertTo-Json -Depth 4 -Compress"#;

    pub fn report(url: String) {
        // Portable or non-SYSTEM processes don't report: reading BitLocker keys
        // needs the SYSTEM access the installed Windows service runs with.
        if !(crate::platform::is_installed() && crate::platform::is_root()) {
            return;
        }
        if IN_FLIGHT
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            return;
        }
        hbb_common::tokio::spawn(async move {
            let _guard = Guard;
            let mut v = match hbb_common::tokio::task::spawn_blocking(collect).await {
                Ok(v) => v,
                Err(_) => return,
            };
            // Match id/uuid to the peer record exactly as the heartbeat does.
            if let Some(obj) = v.as_object_mut() {
                obj.insert("id".to_owned(), json!(Config::get_id()));
                obj.insert(
                    "uuid".to_owned(),
                    json!(crate::encode64(hbb_common::get_uuid())),
                );
                obj.insert(
                    "build".to_owned(),
                    json!(HARD_SETTINGS
                        .read()
                        .map(|h| h.get("comtech-build").cloned().unwrap_or_default())
                        .unwrap_or_default()),
                );
            }
            // On any failure just stop; the server marks the device "not
            // available" and stops asking for 24h. Never log the body.
            let _ = crate::post_request(url, v.to_string(), "").await;
        });
    }

    fn collect() -> Value {
        let err = |msg: &str| json!({ "volumes": [], "error": msg });
        // Build the path from SystemRoot; never rely on PATH.
        let sysroot = match std::env::var("SystemRoot") {
            Ok(s) => s,
            Err(_) => return err("no SystemRoot"),
        };
        let ps = format!(
            r"{}\System32\WindowsPowerShell\v1.0\powershell.exe",
            sysroot
        );
        // -EncodedCommand expects base64 of the script as UTF-16LE.
        let utf16: Vec<u8> = SCRIPT.encode_utf16().flat_map(|u| u.to_le_bytes()).collect();
        let b64 = crate::encode64(&utf16);
        let mut child = match Command::new(&ps)
            .args([
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-EncodedCommand",
                &b64,
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .creation_flags(winapi::um::winbase::CREATE_NO_WINDOW)
            .spawn()
        {
            Ok(c) => c,
            Err(_) => return err("powershell did not start"),
        };
        // Drain stdout on a thread so a full pipe can't deadlock the wait, and
        // so a kill unblocks the read.
        let mut stdout = match child.stdout.take() {
            Some(s) => s,
            None => {
                let _ = child.kill();
                let _ = child.wait();
                return err("no stdout");
            }
        };
        let reader = std::thread::spawn(move || {
            let mut s = String::new();
            let _ = stdout.read_to_string(&mut s);
            s
        });
        let start = Instant::now();
        let status = loop {
            match child.try_wait() {
                Ok(Some(st)) => break st,
                Ok(None) => {
                    if start.elapsed() > Duration::from_secs(60) {
                        let _ = child.kill();
                        let _ = child.wait();
                        let _ = reader.join();
                        return err("timed out");
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
                Err(_) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    let _ = reader.join();
                    return err("wait failed");
                }
            }
        };
        let out = reader.join().unwrap_or_default();
        if !status.success() {
            return err("powershell failed");
        }
        let parsed: Value = match serde_json::from_str(out.trim()) {
            Ok(v) => v,
            Err(_) => return err("bad output"),
        };
        // ConvertTo-Json renders a single volume as an object, not a one-element
        // array; normalise to an array either way.
        let volumes = match parsed.get("volumes") {
            Some(Value::Array(a)) => Value::Array(a.clone()),
            Some(obj @ Value::Object(_)) => json!([obj.clone()]),
            _ => json!([]),
        };
        json!({ "volumes": volumes, "error": "" })
    }
}

#[cfg(windows)]
pub use imp::report;
