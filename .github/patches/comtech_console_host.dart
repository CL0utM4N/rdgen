// The Comtech console in the RustDesk client. Copied to
// flutter/lib/comtech/console_host.dart by comtech_patch.py --console.
//
// Technician builds carry the signed setting comtech-console = Y; their home
// tab is the console, with the usual RustDesk home page under Client. Every
// other build shows the normal home page.
import 'dart:io';

import 'package:comtech_console/comtech_console.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' as rd;
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';

bool comtechConsoleEnabled() {
  try {
    return bind.mainGetHardOption(key: 'comtech-console') == 'Y';
  } catch (_) {
    return false;
  }
}

/// The home tab: the console for technician builds, else the usual page.
Widget comtechHomePage(Key key) => comtechConsoleEnabled() ? ComtechConsolePage(key: key) : DesktopHomePage(key: key);

class RustDeskConsoleHost extends ConsoleHost {
  final String server;
  RustDeskConsoleHost(this.server);

  @override
  String get apiServer => server.endsWith('/') ? server.substring(0, server.length - 1) : server;

  @override
  Widget? buildClientPage(BuildContext context) => const DesktopHomePage(key: ValueKey('comtech-client'));

  @override
  void connect(String id, {bool fileTransfer = false}) {
    final ctx = rd.globalKey.currentContext;
    if (ctx != null) rd.connect(ctx, id, isFileTransfer: fileTransfer);
  }

  @override
  String? loadSetting(String key) {
    // the console follows the client's theme rather than keeping its own
    if (key == 'console-dark') return null;
    final v = bind.mainGetLocalOption(key: 'comtech-$key');
    return v.isEmpty ? null : v;
  }

  @override
  void saveSetting(String key, String value) {
    if (key == 'console-dark') return;
    bind.mainSetLocalOption(key: 'comtech-$key', value: value);
  }

  @override
  String? get clientToken {
    final t = bind.mainGetLocalOption(key: 'access_token');
    return t.isEmpty ? null : t;
  }

  @override
  void onSignedIn(String token) {
    // one sign-in for both: the client's address book and account follow
    if (bind.mainGetLocalOption(key: 'access_token') == token) return;
    bind.mainSetLocalOption(key: 'access_token', value: token).then((_) => rd.gFFI.userModel.refreshCurrentUser());
  }

  @override
  void onSignedOut() => rd.gFFI.userModel.reset(resetOther: true);

  @override
  bool get startDark => rd.MyTheme.currentThemeMode() == ThemeMode.dark;

  @override
  void onThemeChanged(bool dark) => rd.MyTheme.changeDarkMode(dark ? ThemeMode.dark : ThemeMode.light);

  @override
  void openClientSettings() => DesktopTabPage.onAddSetting();

  @override
  String get platform => Platform.isMacOS ? 'mac' : (Platform.isLinux ? 'linux' : 'windows');
}

class ComtechConsolePage extends StatefulWidget {
  const ComtechConsolePage({super.key});

  @override
  State<ComtechConsolePage> createState() => _ComtechConsolePageState();
}

class _ComtechConsolePageState extends State<ComtechConsolePage> with AutomaticKeepAliveClientMixin {
  static bool _started = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (!_started) {
      bind.mainGetApiServer().then((server) {
        Console(RustDeskConsoleHost(server));
        _started = true;
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_started) return const Center(child: CircularProgressIndicator());
    return const ConsoleShell();
  }
}
