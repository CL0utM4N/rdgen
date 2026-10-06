// Comtech: Android phones update themselves from our server.
//
// A phone can't install an update by itself: it downloads the APK, checks it
// against the SHA-256 the server gave, then asks its user to install it. The
// first time, Android also asks to allow installing apps from this one.
//
// Only Client Builder builds (the ones with a comtech-build setting) take
// part. The check runs while the app is running, a first time after 30
// seconds and then every 10 minutes. The server only has an update for a
// phone when updates are pushed or Update now was pressed.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'common.dart';
import 'models/platform_model.dart';

const _kFirstCheck = Duration(seconds: 30);
const _kCheckEvery = Duration(minutes: 10);
const _kAskEvery = Duration(hours: 6);
const _kPromptedOption = 'comtech-update-prompted';
const _kMaxApkBytes = 400 * 1024 * 1024;

bool _comtechUpdateBusy = false;

void comtechStartUpdates() {
  Timer(_kFirstCheck, () {
    _comtechUpdateRound();
    Timer.periodic(_kCheckEvery, (_) => _comtechUpdateRound());
  });
}

Future<void> _comtechUpdateRound() async {
  if (_comtechUpdateBusy) return;
  _comtechUpdateBusy = true;
  try {
    await _comtechCheckOnce();
  } catch (e) {
    debugPrint('comtech-update: $e');
  } finally {
    _comtechUpdateBusy = false;
  }
}

String? _comtechArch() {
  final abi = Abi.current();
  if (abi == Abi.androidArm64) return 'aarch64';
  if (abi == Abi.androidArm) return 'armv7';
  if (abi == Abi.androidX64) return 'x86_64';
  return null;
}

Future<void> _comtechCheckOnce() async {
  final build = bind.mainGetHardOption(key: 'comtech-build');
  if (build.isEmpty) return;
  final api = (await bind.mainGetApiServer()).replaceAll(RegExp(r'/+$'), '');
  if (api.isEmpty) return;
  final arch = _comtechArch();
  if (arch == null) return;
  final current = await bind.mainGetVersion();

  final uri = Uri.parse('$api/api/clientgen/android-update-check').replace(
    queryParameters: {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid(),
      'build': build,
      'version': current,
      'arch': arch,
    },
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) {
    debugPrint('comtech-update: check answered ${res.statusCode}');
    return;
  }
  final body = jsonDecode(res.body);
  final update = body is Map ? body['update'] : null;
  if (update is! Map) return;
  final newVersion = '${update['version']}';
  final sha256 = '${update['sha256']}'.toLowerCase();
  final file = '${update['file']}';
  final url = '${update['url']}';
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
      !RegExp(r'^[A-Za-z0-9._-]+\.apk$').hasMatch(file) ||
      !url.startsWith('$api/api/clientgen/update/') ||
      newVersion.isEmpty ||
      newVersion == current) {
    debugPrint('comtech-update: ignoring an update the server described badly');
    return;
  }

  // the user is asked about a version once in a while, not every round
  final prompted =
      bind.mainGetLocalOption(key: _kPromptedOption).split(' ');
  if (prompted.length == 2 && prompted[0] == newVersion) {
    final at = int.tryParse(prompted[1]) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - at;
    if (age >= 0 && age < _kAskEvery.inSeconds) return;
  }

  final path = await _comtechDownload(url, file, sha256);
  if (path == null) return;

  await bind.mainSetLocalOption(
      key: _kPromptedOption,
      value: '$newVersion ${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
  await gFFI.invokeMethod(
      'comtech_update_notify', {'version': newVersion, 'path': path});
  if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
    _comtechAskToInstall(newVersion, path);
  }
}

// the APK goes in the cache folder the app's FileProvider shares
Future<String?> _comtechDownload(String url, String file, String sha256) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/comtech-update');
  if (await dir.exists()) {
    await for (final f in dir.list()) {
      try {
        await f.delete(recursive: true);
      } catch (_) {}
    }
  } else {
    await dir.create(recursive: true);
  }
  final out = File('${dir.path}/$file');
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    final res = await client.send(req).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      debugPrint('comtech-update: download answered ${res.statusCode}');
      return null;
    }
    final sink = out.openWrite();
    var size = 0;
    try {
      await for (final chunk in res.stream) {
        size += chunk.length;
        if (size > _kMaxApkBytes) throw 'the download is too big';
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    final sum = (await crypto.sha256.bind(out.openRead()).first).toString();
    if (sum != sha256) {
      debugPrint('comtech-update: the download does not match its checksum');
      await out.delete();
      return null;
    }
    return out.path;
  } catch (e) {
    debugPrint('comtech-update: download failed: $e');
    try {
      if (await out.exists()) await out.delete();
    } catch (_) {}
    return null;
  } finally {
    client.close();
  }
}

void _comtechAskToInstall(String version, String path) {
  final dialogManager = gFFI.dialogManager;
  msgBoxCommon(
    dialogManager,
    'Update available',
    Text('Version $version is ready to install.'),
    [
      dialogButton('Later', isOutline: true, onPressed: dialogManager.dismissAll),
      dialogButton('Install', onPressed: () {
        dialogManager.dismissAll();
        gFFI.invokeMethod('comtech_install_apk', {'path': path});
      }),
    ],
  );
}
