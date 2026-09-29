import 'package:flutter/widgets.dart';

/// What the app hosting the console provides. The RustDesk client implements
/// this; the console never reaches into RustDesk itself.
abstract class ConsoleHost {
  /// The API server, such as https://rd.comtechit.au, without a trailing slash.
  String get apiServer;

  /// The RustDesk home page (this device's ID and the connect box), shown
  /// under Client in the sidebar. Null when there isn't one, as in a preview.
  Widget? buildClientPage(BuildContext context) => null;

  /// Starts a remote session with a device.
  void connect(String id, {bool fileTransfer = false});

  /// Small settings the console keeps, such as the theme and table columns.
  String? loadSetting(String key);
  void saveSetting(String key, String value);

  /// The token the client itself is signed in with, if any. The console and
  /// the client share sign-ins, so this skips the console's own login.
  String? get clientToken => null;

  /// The console signed in or out; the client can follow suit.
  void onSignedIn(String token) {}
  void onSignedOut() {}

  /// Dark mode changed in the console, so the client can match it.
  void onThemeChanged(bool dark) {}
  bool get startDark => false;

  /// The client's own settings page, opened from the header.
  void openClientSettings() {}

  /// Short name for the sign-in log, such as "windows".
  String get platform => 'windows';
}
