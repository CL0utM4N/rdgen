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

  /// This device's RustDesk ID and uuid. Given, a console sign-in also
  /// signs the client in, with its own app session on this device.
  String? get deviceId => null;
  String? get deviceUuid => null;

  /// The console signed in and the server made the client its own session.
  void onClientSignIn(String clientToken) {}

  /// Someone chose Logout in the console; the client signs out too.
  void onSignedOut() {}

  /// Dark mode changed in the console, so the client can match it.
  void onThemeChanged(bool dark) {}
  bool get startDark => false;

  /// The client's own settings page, opened from the header.
  void openClientSettings() {}

  /// Short name for the sign-in log, such as "windows".
  String get platform => 'windows';
}
