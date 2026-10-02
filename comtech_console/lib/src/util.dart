import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'console.dart';
import 'i18n.dart';
import 'save.dart';
import 'widgets/dialog.dart';
import 'widgets/table.dart' show Row_;

/// CSV with a header row from the first row's keys, like the web export.
String toCsv(List<Row_> rows) {
  if (rows.isEmpty) return '';
  final keys = rows.first.keys.toList();
  String q(dynamic v) => '"${(v is Map || v is List ? jsonEncode(v) : (v ?? '')).toString().replaceAll('"', '""')}"';
  final b = StringBuffer(keys.join(','))..write('\n');
  for (final r in rows) {
    b
      ..write(keys.map((k) => q(r[k])).join(','))
      ..write('\n');
  }
  return b.toString();
}

Future<void> exportCsv(String name, List<Row_> rows) async {
  if (rows.isEmpty) {
    Toasts.warning(T('NoData'));
    return;
  }
  if (await saveBytes(name, utf8.encode(toCsv(rows)))) Toasts.success(T('OperationSuccess'));
}

/// Opens a link in the system browser.
Future<void> openUrl(String url) async {
  final u = url.startsWith('/') ? '${Console.I.host.apiServer}$url' : url;
  await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
}

IconData platformIcon(String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.startsWith('ios') || n.contains('/ ios') || n.contains('ipados') || n.contains('iphone')) return Icons.phone_iphone;
  if (n.contains('win')) return Icons.window;
  if (n.contains('mac')) return Icons.apple;
  if (n.contains('android')) return Icons.android;
  if (n.contains('linux')) return Icons.computer;
  return Icons.devices_other;
}

/// "Windows", "macOS" ... from a device's OS string.
String osName(String? os) {
  final o = (os ?? '').toLowerCase();
  if (o.contains('windows')) return 'Windows';
  if (o.contains('mac')) return 'macOS';
  if (o.contains('android')) return 'Android';
  if (o.contains('ios')) return 'iOS';
  if (o.contains('linux') || o.contains('ubuntu') || o.contains('debian')) return 'Linux';
  return (os ?? '').isNotEmpty ? os!.split(RegExp(r'[ /]')).first : T('Unknown');
}

/// A device reporting within the last minute is online.
bool isOnline(dynamic lastOnline) {
  final t = (lastOnline as num?)?.toInt() ?? 0;
  return t > 0 && DateTime.now().millisecondsSinceEpoch ~/ 1000 - t < 60;
}

int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
