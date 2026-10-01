// The Comtech console in the RustDesk client. Copied to
// flutter/lib/comtech/console_host.dart by comtech_patch.py --console.
//
// Technician builds carry the signed setting comtech-console = Y; their home
// tab (on phones, the whole app) is the console, with the usual RustDesk home
// page under Client. Every other build shows the normal home page.
import 'dart:io';

import 'package:comtech_console/comtech_console.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' as rd;
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
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

/// The phone app: the console for technician builds, else the usual app.
Widget comtechMobileHome() => comtechConsoleEnabled() ? const ComtechConsolePage() : HomePage();

/// The console's colours for the RustDesk home page under Client: its
/// widgets take them from the theme, so the layout stays as RustDesk has it.
ThemeData comtechClientTheme(ThemeData outer) {
  final dark = outer.brightness == Brightness.dark;
  final c = dark ? CtColors.darkColors : CtColors.light;
  final rdColors = outer.extension<rd.ColorThemeExtension>() ?? (dark ? rd.ColorThemeExtension.dark : rd.ColorThemeExtension.light);
  final radius = BorderRadius.circular(8);
  return outer.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    cardColor: c.surface,
    dividerColor: c.border,
    hoverColor: c.surfaceHover,
    highlightColor: c.surfaceHover,
    primaryColor: c.primary,
    colorScheme: outer.colorScheme.copyWith(
      primary: c.primary,
      secondary: c.primary,
      // ignore: deprecated_member_use
      background: c.surface,
      surface: c.surface,
      onSurface: c.text,
    ),
    textTheme: outer.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    iconTheme: outer.iconTheme.copyWith(color: c.text2),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text2,
        side: BorderSide(color: c.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.primary)),
    // input borders stay as RustDesk sets them: its ID and password are
    // plain text fields that would otherwise get outlines
    extensions: [
      for (final e in outer.extensions.values)
        if (e is! rd.ColorThemeExtension) e,
      rdColors.copyWith(border: c.border, border2: c.borderStrong, border3: c.borderStrong, highlight: c.surfaceHover, divider: c.border),
    ],
  );
}

/// The accent bars beside this device's ID and password.
Color comtechAccent(BuildContext context) => comtechConsoleEnabled() ? Theme.of(context).colorScheme.primary : rd.MyTheme.accent;

/// The install banner, blue in the technician app instead of RustDesk's pink.
List<Color> comtechBannerColors(BuildContext context, List<Color> normal) {
  if (!comtechConsoleEnabled()) return normal;
  final c = Theme.of(context).brightness == Brightness.dark ? CtColors.darkColors : CtColors.light;
  return [c.primary, c.primaryHover];
}

class RustDeskConsoleHost extends ConsoleHost {
  final String server;
  @override
  final String? deviceId;
  @override
  final String? deviceUuid;
  RustDeskConsoleHost(this.server, this.deviceId, this.deviceUuid);

  @override
  String get apiServer => server.endsWith('/') ? server.substring(0, server.length - 1) : server;

  @override
  Widget? buildClientPage(BuildContext context) => Builder(
        builder: (context) => Theme(
          data: comtechClientTheme(Theme.of(context)),
          child: rd.isMobile ? HomePage() : const DesktopHomePage(key: ValueKey('comtech-client')),
        ),
      );

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
  void onClientSignIn(String clientToken) {
    // signing in to the console signs the client in too, with its own
    // session that lasts like any RustDesk sign-in
    bind.mainSetLocalOption(key: 'access_token', value: clientToken).then((_) => rd.gFFI.userModel.refreshCurrentUser());
  }

  @override
  void onSignedOut() => rd.gFFI.userModel.reset(resetOther: true);

  @override
  bool get startDark => rd.MyTheme.currentThemeMode() == ThemeMode.dark;

  @override
  void onThemeChanged(bool dark) => rd.MyTheme.changeDarkMode(dark ? ThemeMode.dark : ThemeMode.light);

  @override
  void openClientSettings() {
    if (!rd.isMobile) return DesktopTabPage.onAddSetting();
    final ctx = rd.globalKey.currentContext;
    if (ctx == null) return;
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: Text(rd.translate('Settings'))), body: SettingsPage()),
    ));
  }

  @override
  String get platform => Platform.isAndroid
      ? 'android'
      : Platform.isIOS
          ? 'ios'
          : Platform.isMacOS
              ? 'mac'
              : (Platform.isLinux ? 'linux' : 'windows');
}

class ComtechConsolePage extends StatefulWidget {
  const ComtechConsolePage({super.key});

  @override
  State<ComtechConsolePage> createState() => _ComtechConsolePageState();
}

class _ComtechConsolePageState extends State<ComtechConsolePage> with AutomaticKeepAliveClientMixin {
  static bool _started = false;
  static bool _askedInstall = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (!_started) {
      Future.wait([bind.mainGetApiServer(), bind.mainGetMyId(), bind.mainGetUuid()]).then((r) {
        Console(RustDeskConsoleHost(r[0], r[1].isEmpty ? null : r[1], r[2].isEmpty ? null : r[2]));
        _started = true;
        if (mounted) setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptInstall());
  }

  // Run as the portable exe, the technician app offers to install itself so
  // it becomes a proper service (needed for unattended and UAC-side work).
  void _maybePromptInstall() {
    if (_askedInstall || !(Platform.isWindows || Platform.isMacOS)) return;
    if (bind.mainIsInstalled()) return;
    _askedInstall = true;
    final ctx = rd.globalKey.currentContext ?? context;
    showDialog(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Install Comtech Remote Admin?'),
        content: const Text(
            'Install it on this PC so it runs as a service. Unattended access '
            'and controlling UAC prompts on the remote side need it installed. '
            'Windows will ask for administrator permission.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Not now')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dctx).pop();
              bind.installInstallMe(options: 'startmenu desktopicon', path: bind.installInstallPath());
            },
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_started) return const Center(child: CircularProgressIndicator());
    return const ConsoleShell();
  }
}
