# Windows client patch — BitLocker recovery key reporting

This is the remaining, unimplemented half of the BitLocker escrow feature.
The **server and console are already built and committed** (rustdesk-api
`client-builder`, rdgen `master`). This spec is self-contained: a developer
or a fresh Claude session can implement it from this file alone.

## What it is

BitLocker recovery key escrow, the same thing Ninja/Breeze and Microsoft's
own MBAM/Intune do: our own installed Windows clients send their BitLocker
recovery keys to our API so a technician can unlock a machine that shows the
blue recovery screen. Keys are stored encrypted (server side, already done)
and every reveal is audit-logged. This is a standard, documented IT admin
workflow over our own fleet, on clients we build and sign ourselves.

## How it fits the existing fork

The client is patched at build time by `comtech_patch.py`, run from the
RustDesk source root by `base-windows.yml`. Model this change on the existing
`--updates` feature, which already:
- hooks the heartbeat response in `src/hbbs_http/sync.rs`, and
- adds a module to `src/lib.rs` and ships a `.rs` file via `p.write`
  (see `comtech_update_check.rs` and the `linux_updates`/`--updates` blocks
  in `comtech_patch.py`).

Read those first; this change is the same shape.

## Wire contract (fixed — the server is already built to it)

**1. Heartbeat request** must gain a field so the server learns the build:
```
"comtech_build": "<value of signed hard setting comtech-build, or empty>"
```
Read it the way `comtech_update_check.rs` reads it:
```rust
config::HARD_SETTINGS.read().unwrap().get("comtech-build").cloned().unwrap_or_default()
```
Without this the server never links a device to its build and never asks for
keys. The server reads it as `info.ComtechBuild` in `Heartbeat`.

**2. Heartbeat reply** may contain `"comtech_bitlocker": true`. When present
(and only on Windows), the client collects its keys and POSTs them once.

**3. Report endpoint**: `POST <api>/api/comtech/bitlocker`, body JSON:
```json
{
  "id":    "<Config::get_id()>",
  "uuid":  "<crate::encode64(hbb_common::get_uuid())>",
  "build": "<comtech-build hard setting>",
  "volumes": [
    { "volume": "<Win32_EncryptableVolume.DeviceID>",
      "mount": "C:",
      "protection": 0|1|2,          // GetProtectionStatus: 0 off, 1 on, 2 unknown
      "volume_type": 0|1|2,         // 0 OS, 1 fixed data, 2 removable
      "keys": [ { "id": "{GUID}", "password": "<48-digit recovery password>" } ] }
  ],
  "error": ""                       // short string if collection failed; omit volumes then
}
```
The server replies `200 {}` in every case. `id`/`uuid` are matched against the
peer record exactly as the heartbeat does, so send them identically.

## Target files

- **New**: `.github/patches/comtech_bitlocker.rs` (the Rust module, shipped by `p.write`)
- **Modify**: `.github/patches/comtech_patch.py` (add `bitlocker(p)` + `--bitlocker`)
- **Modify**: `.github/workflows/base-windows.yml` (add `--bitlocker` to both the
  `--check` line and the apply line; update the docstring usage line)

## The Rust module (`comtech_bitlocker.rs`)

`#[cfg(windows)]` module with:

```rust
pub fn report(url: String)      // non-blocking; no-op if a run is already in flight
fn collect() -> serde_json::Value   // { "volumes": [...], "error": "" }
```

### `report`
- Guard with a `static AtomicBool` so only one run is ever in flight; bail
  immediately if already set, clear it when done.
- Skip entirely unless `crate::platform::is_installed() && crate::platform::is_root()`
  — portable or non-SYSTEM processes don't report. (The installed Windows
  service runs as SYSTEM, which is the access BitLocker key reads require.)
- `tokio::spawn` + `spawn_blocking(collect)`; then add `id`, `uuid`, `build`
  to the JSON and send with `crate::post_request(url, body, "")`.
- Never log the body, the raw output, or any password. On any failure just
  stop; the server marks the device "not available" and stops asking for 24h.

### `collect`
Run a short PowerShell script and parse its JSON. Use PowerShell (not
`manage-bde` text) because its output doesn't change with the Windows display
language, and it works on Home editions.

- Launch `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`, with
  the path built from the `SystemRoot` env var — **never** rely on PATH.
- Args: `-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand <b64>`
  where `<b64>` is the script encoded as base64 of UTF-16LE (standard
  `-EncodedCommand` form).
- `CREATE_NO_WINDOW` creation flag (as the fork already does for subprocesses
  in `windows.rs`), and a 60-second timeout — kill the process if it overruns.
- Non-zero exit, timeout, or unparseable output → return
  `{ "volumes": [], "error": "<short reason>" }`.

Script logic (enumerate every fixed drive, not just C:):
```powershell
$ErrorActionPreference='Stop'
$out=@()
foreach ($v in Get-WmiObject -Namespace 'root/cimv2/security/microsoftvolumeencryption' -Class Win32_EncryptableVolume) {
  $prot = $v.GetProtectionStatus().ProtectionStatus
  $keys=@()
  foreach ($id in $v.GetKeyProtectors(3).VolumeKeyProtectorID) {   # type 3 = numerical password
    $pw = $v.GetKeyProtectorNumericalPassword($id).NumericalPassword
    if ($pw) { $keys += @{ id=$id; password=$pw } }
  }
  $out += @{ volume=$v.DeviceID; mount=$v.DriveLetter; protection=[int]$prot; volume_type=[int]$v.VolumeType; keys=$keys }
}
@{ volumes=$out } | ConvertTo-Json -Depth 4 -Compress
```
(Deserialize into the shape above; set `error` yourself on a failed launch.)

## `comtech_patch.py` changes

Add `def bitlocker(p):` and a `--bitlocker` flag, wired like `--updates`:

1. `p.write("src/comtech_bitlocker.rs", open(.../comtech_bitlocker.rs).read(), "the BitLocker key reporter")`
2. Register the module (same anchor `linux_updates` uses):
   ```python
   p.replace("src/lib.rs", "mod updater;\n",
             'mod updater;\n#[cfg(windows)]\npub mod comtech_bitlocker;\n',
             "the BitLocker reporter is part of the app")
   ```
3. **Send the build in the heartbeat request.** In `src/hbbs_http/sync.rs`,
   where the heartbeat body `v` is assembled (near `v["modified_at"] = ...`),
   insert `v["comtech_build"] = json!(<comtech-build hard setting>);`. Use a
   `p.replace` anchored on the `modified_at` line.
4. **Act on the reply.** Insert before the `disconnect` hook line in
   `sync.rs` (the same anchor `--updates` uses — make sure it still applies
   whether or not `--updates` also ran, since both insert before that line):
   ```rust
   #[cfg(windows)]
   if rsp.remove("comtech_bitlocker").and_then(|v| v.as_bool()).unwrap_or(false) {
       crate::comtech_bitlocker::report(url.replace("heartbeat", "comtech/bitlocker"));
   }
   ```

## `base-windows.yml` changes

Add `--bitlocker` to both the `--check` line and the apply line (the two
`comtech_patch.py` invocations), matching how `--console`/`--updates` appear.

## Verification

- `python comtech_patch.py --check --updates --packer --console --bitlocker`
  from both `$TEMP/rdclient` (1.5.0) and `$TEMP/rd149` (1.4.9) prints `ok:`
  for every step. (`--check` only confirms the anchors still exist.)
- Apply to a **copy** of `$TEMP/rdclient`, then `cargo check --target
  x86_64-pc-windows-msvc` if a toolchain is available; if not, say so — don't
  skip silently.
- Run the PowerShell script by itself, **not elevated**, and confirm the
  error path returns valid JSON. Do not run it elevated — that would print
  this PC's real recovery key to the console.

## Two checks that gate shipping (do these regardless)

1. **Every client must reach the API over HTTPS.** If any client talks to the
   API over plain HTTP, the keys cross the network in cleartext. Confirm this
   before enabling the feature anywhere.
2. Request-body logging on `/api/*` was already confirmed clean server-side
   (nothing logs the report body). Re-confirm if the client endpoint moves.

## End-to-end (after a new base Windows build carries this)

1. Turn on the master switch (Settings) and the per-build switch (Client
   Builder) for a test build; install it on a VM with BitLocker on C:.
2. Within a heartbeat or two the key appears in the console. Check its Key ID
   against `manage-bde -protectors -get C:` on the VM.
3. Delete that protector and add a new recovery password on the VM, press
   Refresh in the console: the old key shows Removed, the new one Active.
4. Reveal a key; confirm the admin log has the entry and the password itself
   is not in the log.

## Notes on scope

- The client never adds a recovery password to a drive that lacks one (e.g.
  TPM-only machines). It only reports what already exists.
- Only base (Instant) Windows builds get this; technician builds don't.
- The module is Windows-only (`#[cfg(windows)]`); other platforms are untouched.
