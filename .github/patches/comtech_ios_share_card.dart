// Comtech: on iPhones and iPads, the ID a technician uses to see this screen,
// and how to start sharing it. Copied to flutter/lib/comtech/ios_share.dart
// by comtech_patch.py --ios-share.
//
// The broadcast extension does the sharing and has no screen of its own; it
// takes its ID from identifierForVendor (see comtech_ios.rs share_id), which
// it shares with this app, so the same number is worked out here. While it
// shares, it makes a one-time code and gives it to the API under the same
// identifierForVendor; this card fetches it from there to show.
import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

String? comtechShareId(String? vendorId) {
  final v = (vendorId ?? '').trim().toUpperCase();
  if (v.isEmpty) return null;
  var h = 0x811c9dc5;
  for (final b in v.codeUnits) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return (1000000000 + h % 1000000000).toString();
}

String _spaced(String id) {
  final b = StringBuffer();
  for (var i = 0; i < id.length; i++) {
    if (i > 0 && (id.length - i) % 3 == 0) b.write(' ');
    b.write(id[i]);
  }
  return b.toString();
}

class ComtechShareCard extends StatefulWidget {
  const ComtechShareCard({super.key});

  @override
  State<ComtechShareCard> createState() => _ComtechShareCardState();
}

const _broadcast = MethodChannel('comtech/broadcast');

class _ComtechShareCardState extends State<ComtechShareCard> {
  String? id;
  String? vendor;
  String? code;
  String? problem;
  Timer? timer;

  // the extension's one-time code, which exists only while sharing is on
  Future<void> _fetchCode() async {
    final v = vendor;
    if (v == null) return;
    try {
      final api = (await bind.mainGetApiServer()).replaceAll(RegExp(r'/+$'), '');
      if (api.isEmpty) return;
      final r = await http
          .get(Uri.parse('$api/api/comtech/ios-code?vendor=${Uri.encodeQueryComponent(v)}'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final c = (jsonDecode(r.body)['code'] ?? '').toString();
      if (mounted && c != (code ?? '')) setState(() => code = c.isEmpty ? null : c);
    } catch (_) {}
  }

  Future<void> _start() async {
    try {
      final r = await _broadcast.invokeMethod<String>('start');
      if (r == 'missing') {
        setState(() => problem = "Screen sharing isn't in this copy of the app. The tool used to install it may have "
            'removed it; ask your technician for a new copy.');
      }
    } catch (_) {
      setState(() => problem = "Screen sharing couldn't be started on this device.");
    }
  }

  @override
  void initState() {
    super.initState();
    // the phone stays awake while the app is open; iOS doesn't let it keep
    // others awake, so the card asks the user to change Auto-Lock
    WakelockPlus.enable().catchError((_) {});
    DeviceInfoPlugin().iosInfo.then((info) {
      if (!mounted) return;
      setState(() {
        vendor = info.identifierForVendor;
        id = comtechShareId(vendor);
      });
      _fetchCode();
      timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchCode());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    timer?.cancel();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (id == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Share this screen', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: SelectableText(_spaced(id!),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1)),
            ),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () => Clipboard.setData(ClipboardData(text: id!)),
            ),
          ]),
          if (code != null)
            Row(children: [
              Text('One-time code  ', style: theme.textTheme.bodyMedium),
              SelectableText(_spaced(code!),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 1)),
            ])
          else
            Text('A one-time code appears here once you start sharing.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            'Tap Start sharing, then Start Broadcast, and give your technician the ID and one-time code. '
            'Each time you start sharing there is a new code. '
            'You can also start it from Control Center: press and hold Screen Recording and choose this app.\n\n'
            "So your iPhone doesn't lock while you're being helped, set Auto-Lock to Never "
            '(Settings → Display & Brightness → Auto-Lock), and change it back afterwards.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.screen_share_outlined, size: 18),
            label: const Text('Start sharing'),
          ),
          if (problem != null) ...[
            const SizedBox(height: 8),
            Text(problem!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
        ]),
      ),
    );
  }
}
