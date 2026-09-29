// A browser preview of the console, for checking pages without building the
// RustDesk client. Run with --dart-define=API=http://localhost:21114
import 'package:comtech_console/comtech_console.dart';
import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

class PreviewHost extends ConsoleHost {
  @override
  String get apiServer => const String.fromEnvironment('API', defaultValue: 'http://localhost:21114');

  @override
  Widget? buildClientPage(BuildContext context) =>
      const Center(child: Text('The RustDesk home page goes here in the app.'));

  @override
  void connect(String id, {bool fileTransfer = false}) =>
      html.window.alert('${fileTransfer ? 'File transfer' : 'Connect'} to $id');

  @override
  String? loadSetting(String key) => html.window.localStorage['console-$key'];

  @override
  void saveSetting(String key, String value) => html.window.localStorage['console-$key'] = value;
}

void main() {
  Console(PreviewHost());
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, title: 'Comtech console', home: ConsoleShell()));
}
