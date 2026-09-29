"""The Comtech changes to RustDesk for base clients.

Base clients are built once per RustDesk release; the Client Builder then
brands each customer's installer on the server in seconds. Run from the
RustDesk source folder:

    python comtech_patch.py --key <settings public key> [--updates] [--packer] [--android] [--console]
    python comtech_patch.py --check [--updates] [--packer] [--android] [--console]

--check only confirms every change still applies to this RustDesk version,
so a new release that moved the code fails early and clearly.
"""
import argparse
import os
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", default="")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--updates", action="store_true", help="updates come from our server (Windows)")
    ap.add_argument("--packer", action="store_true", help="Windows installer reads its files from the end of the exe")
    ap.add_argument("--android", action="store_true", help="Android reads its settings from assets/custom.txt")
    ap.add_argument("--appimage", action="store_true", help="Linux reads settings attached to its AppImage")
    ap.add_argument("--console", action="store_true", help="technician builds open the Comtech console (desktop)")
    a = ap.parse_args()
    if not a.check and not a.key:
        fail("no settings public key")
    p = Patcher(a.check)

    # custom.txt is only read when signed: trust only our Client Builder's
    # key. (rdgen deletes the check, so anyone could change a client.)
    p.replace("src/common.rs", RUSTDESK_KEY, f'const KEY: &str = "{a.key}";', "settings are signed by our Client Builder")

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
        # the service and the app both read the settings the Client Builder
        # puts in the APK, instead of compiled in text
        p.replace("flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt",
                  'FFI.startServer(configPath, "")',
                  'FFI.startServer(configPath, try { applicationContext.assets.open("flutter_assets/assets/custom.txt")'
                  '.bufferedReader().use { it.readText().trim() } } catch (e: Exception) { "" })',
                  "the Android service reads assets/custom.txt")
        p.replace("flutter/lib/models/native_model.dart",
                  "        customClientConfig: '',",
                  "        customClientConfig: await _comtechCustomConfig(),",
                  "the Android app reads assets/custom.txt")
        p.append("flutter/lib/models/native_model.dart", "comtech_custom_config.dart", "the settings reader")
        p.write("flutter/assets/custom.txt", "", "an empty assets/custom.txt for the Client Builder to fill")

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
