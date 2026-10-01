"""The Comtech changes to RustDesk for base clients.

Base clients are built once per RustDesk release; the Client Builder then
brands each customer's installer on the server in seconds. Run from the
RustDesk source folder:

    python comtech_patch.py --key <settings public key> [--updates] [--packer] [--android] [--ios] [--ios-share] [--console]
    python comtech_patch.py --check [--updates] [--packer] [--android] [--ios] [--ios-share] [--console]

--check only confirms every change still applies to this RustDesk version,
so a new release that moved the code fails early and clearly.
"""
import argparse
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RUSTDESK_KEY = 'const KEY: &str = "5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=";'


def fail(msg):
    print("::error::" + msg)
    sys.exit(1)


class Patcher:
    def __init__(self, check):
        self.check = check

    def replace(self, path, old, new, what, count=1):
        s = open(path, encoding="utf-8").read()
        if old not in s:
            fail(f"{what}: RustDesk changed {path}, so this change needs updating for this version")
        if not self.check:
            s = s.replace(old, new) if count == 0 else s.replace(old, new, count)
            open(path, "w", encoding="utf-8", newline="\n").write(s)
        print("ok: " + what)

    def sub(self, path, pattern, repl, what, least):
        """Replace every match of pattern, failing unless at least `least` of them are there."""
        s = open(path, encoding="utf-8").read()
        n = len(re.findall(pattern, s))
        if n < least:
            fail(f"{what}: RustDesk changed {path} ({n} places, expected {least} or more), "
                 "so this change needs updating for this version")
        if not self.check:
            open(path, "w", encoding="utf-8", newline="\n").write(re.sub(pattern, repl, s))
        print(f"ok: {what} ({n} places)")

    def append(self, path, extra_file, what):
        if not os.path.isfile(path):
            fail(f"{what}: {path} is missing")
        if not self.check:
            extra = open(os.path.join(HERE, extra_file), encoding="utf-8").read()
            with open(path, "a", encoding="utf-8", newline="\n") as f:
                f.write("\n" + extra)
        print("ok: " + what)

    def write(self, path, content, what):
        if not self.check:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w", encoding="utf-8", newline="\n").write(content)
        print("ok: " + what)


def quote_app_name(p):
    """Quote the app name where Windows installs put it in a cmd script.

    RustDesk writes the install as a .bat and drops the app name in unquoted,
    so a name with a space ("Comtech Remote Admin") makes `sc create` take
    only the first word as an option. The batch file carries on, the install
    looks fine, and the client ends up with no service: it is then reachable
    only while its window is open, because the window runs a server of its
    own. rdgen quotes the registry commands in a workflow step, which base
    clients can't use: the name is only known when the Client Builder brands
    the installer, long after the build.
    """
    win = "src/platform/windows.rs"
    p.sub(win, r"sc (create|start|stop|delete) \{app_name\}", r'sc \1 \\"{app_name}\\"',
          "the service is created under the app's full name", 13)
    p.replace(win, 'format!("sc start {}", &app_name)', 'format!("sc start \\"{}\\"", &app_name)',
              "an update restarts the service by its full name")
    p.sub(win, r"taskkill /F /IM \{app_name\}\.exe", r'taskkill /F /IM \\"{app_name}.exe\\"',
          "installs and updates can stop the running app", 4)
    p.sub(win, r"reg (add|delete) \{subkey\}", r'reg \1 \\"{subkey}\\"',
          "the app is listed in Add or remove programs", 22)
    p.sub(win, r"reg (add|delete) (HKEY_CLASSES_ROOT\\\\[^ ]*)", r'reg \1 \\"\2\\"',
          "the app's file type and links are registered", 19)
    # the same key, passed positionally: share_rdp and an update's DisplayIcon
    p.sub(win, r"reg add \{\} /f /v", r'reg add \\"{}\\" /f /v',
          "share RDP and the update's icon reach the registry", 2)


def ios_share(p):
    """Turn RustDesk's sharing side on for iOS, for the broadcast extension.

    RustDesk leaves the server, ID registration and API reporting out of iOS
    builds, since an iPhone app can't see the screen. A broadcast extension
    can, so these come back, with frames from comtech_ios_capture.rs.
    """
    lib = "src/lib.rs"
    p.replace(lib,
              '#[cfg(not(any(target_os = "ios")))]\n/// cbindgen:ignore\nmod server;\n'
              '#[cfg(not(any(target_os = "ios")))]\npub use self::server::*;\n',
              '/// cbindgen:ignore\nmod server;\npub use self::server::*;\n',
              "iOS has the sharing server")
    p.replace(lib,
              '#[cfg(not(any(target_os = "ios")))]\nmod rendezvous_mediator;\n'
              '#[cfg(not(any(target_os = "ios")))]\npub use self::rendezvous_mediator::*;\n',
              'mod rendezvous_mediator;\npub use self::rendezvous_mediator::*;\n'
              '#[cfg(target_os = "ios")]\nmod comtech_ios;\n',
              "iOS registers its ID")
    p.replace(lib, '#[cfg(not(any(target_os = "ios")))]\npub mod ipc;\n', 'pub mod ipc;\n', "iOS has ipc for the server")
    p.write("src/comtech_ios.rs", open(os.path.join(HERE, "comtech_ios_share.rs"), encoding="utf-8").read(),
            "what the broadcast extension calls")

    server = "src/server.rs"
    p.replace(server,
              '    #[cfg(not(target_os = "ios"))]\n    {\n        server.add_service(Box::new(display_service::new()));\n',
              '    server.add_service(Box::new(display_service::new()));\n    #[cfg(not(target_os = "ios"))]\n    {\n',
              "iOS shares its screen")
    p.replace(server,
              '    pub const NAME_WINDOW_FOCUS: &\'static str = "";\n}\n',
              '    pub const NAME_WINDOW_FOCUS: &\'static str = "";\n'
              '    #[cfg(target_os = "ios")]\n    pub fn fix_key_down_timeout_at_exit() {}\n}\n',
              "iOS has no keys to release")
    p.replace("src/rendezvous_mediator.rs",
              '        if start_lan_listening {\n            std::thread::spawn(move || {\n'
              '                allow_err!(super::lan::start_listening());',
              '        #[cfg(not(target_os = "ios"))]\n'
              '        if start_lan_listening {\n            std::thread::spawn(move || {\n'
              '                allow_err!(super::lan::start_listening());',
              "iOS doesn't listen on the LAN")
    p.sub("src/hbbs_http/sync.rs", r'(?m)^#\[cfg\(not\(any\(target_os = "ios"\)\)\)\]\n|^#\[cfg\(not\(target_os = "ios"\)\)\]\n', '',
          "iOS reports to the API", 7)
    # the connection manager runs in the extension like Android's, with no
    # window: the build's permanent password lets technicians in
    p.sub("src/ui_cm_interface.rs", r'#\[cfg\(not\(any\(target_os = "ios"\)\)\)\]\s*|#\[cfg\(not\(target_os = "ios"\)\)\]\s*', '',
          "iOS has the connection manager", 20)
    p.replace("src/flutter.rs", '// Server Side\n#[cfg(not(any(target_os = "ios")))]\npub mod connection_manager {',
              '// Server Side\npub mod connection_manager {', "iOS has the connection manager's channel")
    p.append("src/common.rs", "comtech_ios_common.rs", "iOS knows its device name")
    p.replace("src/flutter.rs",
              '    #[cfg(target_os = "android")]\n    use hbb_common::tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender};\n\n'
              '    #[cfg(target_os = "android")]\n    pub fn start_channel(',
              '    #[cfg(any(target_os = "android", target_os = "ios"))]\n    use hbb_common::tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender};\n\n'
              '    #[cfg(any(target_os = "android", target_os = "ios"))]\n    pub fn start_channel(',
              "iOS starts the connection manager like Android")
    p.replace("src/ui_cm_interface.rs",
              '#[cfg(target_os = "android")]\n#[tokio::main(flavor = "current_thread")]\npub async fn start_listen<',
              '#[cfg(any(target_os = "android", target_os = "ios"))]\n#[tokio::main(flavor = "current_thread")]\npub async fn start_listen<',
              "iOS listens for connections like Android")
    p.append("src/platform/mod.rs", "comtech_ios_platform.rs", "iOS platform basics for the server")

    scrap = "libs/scrap/src/common/"
    p.replace(scrap + "mod.rs",
              '    } else if #[cfg(target_os = "android")] {\n        mod android;\n        pub use self::android::*;\n    }',
              '    } else if #[cfg(target_os = "android")] {\n        mod android;\n        pub use self::android::*;\n'
              '    } else if #[cfg(target_os = "ios")] {\n        mod ios;\n        pub use self::ios::*;\n    }',
              "iOS takes frames from the extension")
    p.sub(scrap + "mod.rs", r'(?m)^[ \t]*#\[cfg\(not\(any\(target_os = "ios"\)\)\)\]\n', '', "iOS can capture", 4)
    p.sub(scrap + "convert.rs", r'(?m)^#\[cfg\(not\(target_os = "ios"\)\)\]\n', '', "iOS converts frames", 3)
    p.sub(scrap + "codec.rs", r'(?m)^#\[cfg\(not\(target_os = "ios"\)\)\]\n(?=pub fn test_av1)', '', "iOS tests AV1 like others", 1)
    p.write(scrap + "ios.rs", open(os.path.join(HERE, "comtech_ios_capture.rs"), encoding="utf-8").read(),
            "the iOS capturer")
    # the server passes taps and keys on to Android; an iPhone can't take them
    p.append("libs/scrap/src/lib.rs", "comtech_ios_input.rs", "iOS ignores remote input")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", default="")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--updates", action="store_true", help="updates come from our server (Windows)")
    ap.add_argument("--packer", action="store_true", help="Windows installer reads its files from the end of the exe")
    ap.add_argument("--android", action="store_true", help="Android reads its settings from assets/custom.txt")
    ap.add_argument("--ios", action="store_true", help="iOS reads its settings from assets/custom.txt")
    ap.add_argument("--ios-share", action="store_true", help="iOS can share its screen from a broadcast extension")
    ap.add_argument("--appimage", action="store_true", help="Linux reads settings attached to its AppImage")
    ap.add_argument("--console", action="store_true", help="technician builds open the Comtech console")
    a = ap.parse_args()
    if not a.check and not a.key:
        fail("no settings public key")
    p = Patcher(a.check)

    # custom.txt is only read when signed: trust only our Client Builder's
    # key. (rdgen deletes the check, so anyone could change a client.)
    p.replace("src/common.rs", RUSTDESK_KEY, f'const KEY: &str = "{a.key}";', "settings are signed by our Client Builder")

    quote_app_name(p)

    if a.updates:
        p.replace("src/common.rs",
                  "    let (request, url) =\n        hbb_common::version_check_request(hbb_common::VER_TYPE_RUSTDESK_CLIENT.to_string());\n",
                  "    let (request, _) =\n        hbb_common::version_check_request(hbb_common::VER_TYPE_RUSTDESK_CLIENT.to_string());\n"
                  "    let url = comtech_update_check_url();\n",
                  "updates are checked with our server")
        p.append("src/common.rs", "comtech_update_check.rs", "the update check address")
        # updates install by themselves; don't offer RustDesk's download page
        p.replace("flutter/lib/desktop/pages/desktop_home_page.dart", "updateUrl.isNotEmpty", "false",
                  "no update banner", count=0)

    if a.packer:
        old = ('#[cfg(windows)]\nconst BIN_DATA: &[u8] = include_bytes!("../data.bin");\n'
               '#[cfg(not(windows))]\nconst BIN_DATA: &[u8] = &[];\n')
        path = "libs/portable/src/bin_reader.rs"
        s = open(path, encoding="utf-8").read()
        if old not in s:
            fail(f"installer packing: RustDesk changed {path}, so this change needs updating for this version")
        if not a.check:
            new = open(os.path.join(HERE, "comtech_bin_data.rs"), encoding="utf-8").read()
            s = s.replace(old, new, 1).replace("BIN_DATA", "bin_data()")
            open(path, "w", encoding="utf-8", newline="\n").write(s)
        print("ok: the installer reads its files from the end of the exe")

    if a.appimage:
        # settings attached to the end of an AppImage win over its custom.txt
        p.replace("src/common.rs",
                  "pub fn load_custom_client() {\n",
                  "pub fn load_custom_client() {\n"
                  "    #[cfg(target_os = \"linux\")]\n"
                  "    if let Some(data) = comtech_appimage_settings() {\n"
                  "        read_custom_client(&data);\n"
                  "        return;\n"
                  "    }\n",
                  "AppImages read settings attached to their end")
        p.append("src/common.rs", "comtech_appimage.rs", "the AppImage settings reader")

    if a.android:
        # the service reads the settings the Client Builder puts in the APK,
        # instead of compiled in text
        # (1.5.0 added a home folder argument before the settings)
        p.sub("flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt",
              r'FFI\.startServer\(configPath, (homePath, )?""\)',
              r'FFI.startServer(configPath, \1try { applicationContext.assets.open("flutter_assets/assets/custom.txt")'
              r'.bufferedReader().use { it.readText().trim() } } catch (e: Exception) { "" })',
              "the Android service reads assets/custom.txt", 1)

    if a.android or a.ios:
        # the app reads the settings the Client Builder puts in the APK or IPA
        p.replace("flutter/lib/models/native_model.dart",
                  "        customClientConfig: '',",
                  "        customClientConfig: await _comtechCustomConfig(),",
                  "the phone app reads assets/custom.txt")
        p.append("flutter/lib/models/native_model.dart", "comtech_custom_config.dart", "the settings reader")
        p.write("flutter/assets/custom.txt", "", "an empty assets/custom.txt for the Client Builder to fill")

    if a.ios_share:
        ios_share(p)

    if a.console:
        # the console package sits beside the app; the home tab shows it when
        # the build's signed settings turn it on
        src = os.path.join(HERE, "..", "..", "comtech_console")
        if not os.path.isfile(os.path.join(src, "pubspec.yaml")):
            fail("the comtech_console package is missing from rdgen")
        if not a.check:
            shutil.rmtree("flutter/comtech_console", ignore_errors=True)
            shutil.copytree(src, "flutter/comtech_console",
                            ignore=shutil.ignore_patterns("preview", "build", ".dart_tool", "pubspec.lock", "tool", ".idea", "*.iml"))
        print("ok: the console package")
        p.replace("flutter/pubspec.yaml",
                  "  flutter_localizations:\n    sdk: flutter\n",
                  "  flutter_localizations:\n    sdk: flutter\n  comtech_console:\n    path: ./comtech_console\n",
                  "the console is a dependency")
        p.write("flutter/lib/comtech/console_host.dart",
                open(os.path.join(HERE, "comtech_console_host.dart"), encoding="utf-8").read(),
                "the console's link to RustDesk")
        # on phones the console is the whole app
        p.replace("flutter/lib/main.dart", "import 'mobile/pages/home_page.dart';\n",
                  "import 'mobile/pages/home_page.dart';\nimport 'comtech/console_host.dart';\n",
                  "the phone app can show the console")
        p.replace("flutter/lib/main.dart", "                  ? WebHomePage()\n                  : HomePage(),",
                  "                  ? WebHomePage()\n                  : comtechMobileHome(),",
                  "technician phone apps open on the console")
        p.replace("flutter/lib/desktop/pages/desktop_tab_page.dart",
                  "import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';\n",
                  "import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';\n"
                  "import 'package:flutter_hbb/comtech/console_host.dart';\n",
                  "the home tab can show the console")
        p.replace("flutter/lib/desktop/pages/desktop_tab_page.dart",
                  "        page: DesktopHomePage(\n          key: const ValueKey(kTabLabelHomePage),\n        )));",
                  "        page: comtechHomePage(const ValueKey(kTabLabelHomePage))));",
                  "technician builds open on the console")
        # the home page under Client takes the console's colours; RustDesk
        # fixes these few, so they follow a function that keeps them as they
        # are in customers' builds
        home = "flutter/lib/desktop/pages/desktop_home_page.dart"
        p.replace(home, "import 'dart:convert';\n",
                  "import 'dart:convert';\nimport 'package:flutter_hbb/comtech/console_host.dart';\n",
                  "the home page can take the console's colours")
        p.replace(home, "decoration: const BoxDecoration(color: MyTheme.accent),",
                  "decoration: BoxDecoration(color: comtechAccent(context)),", "the ID accent bar")
        p.replace(home, "decoration: BoxDecoration(color: MyTheme.accent),",
                  "decoration: BoxDecoration(color: comtechAccent(context)),", "the password accent bar")
        p.replace(home,
                  "                colors: [\n                  Color.fromARGB(255, 226, 66, 188),\n"
                  "                  Color.fromARGB(255, 244, 114, 124),\n                ],",
                  "                colors: comtechBannerColors(context, const [\n"
                  "                  Color.fromARGB(255, 226, 66, 188),\n"
                  "                  Color.fromARGB(255, 244, 114, 124),\n                ]),",
                  "the install banner")

    print("all Comtech changes " + ("apply" if a.check else "applied"))


if __name__ == "__main__":
    main()
