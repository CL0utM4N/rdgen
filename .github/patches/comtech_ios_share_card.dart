// Comtech: on iPhones and iPads, the ID a technician uses to see this screen,
// and how to start sharing it. Copied to flutter/lib/comtech/ios_share.dart
// by comtech_patch.py --ios-share.
//
// The broadcast extension does the sharing and has no screen of its own; it
// takes its ID from identifierForVendor (see comtech_ios.rs share_id), which
// it shares with this app, so the same number is worked out here.
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  String? problem;

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
    DeviceInfoPlugin().iosInfo.then((info) {
      if (mounted) setState(() => id = comtechShareId(info.identifierForVendor));
    }).catchError((_) {});
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
          const SizedBox(height: 4),
          Text(
            'Give your technician the number above, then tap Start sharing and Start Broadcast. '
            'You can also start it from Control Center: press and hold Screen Recording and choose this app.',
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
