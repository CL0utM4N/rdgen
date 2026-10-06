import 'package:flutter/material.dart';

import '../console.dart';
import '../i18n.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/basic.dart';
import '../widgets/dialog.dart';
import '../widgets/form.dart';
import '../widgets/listpage.dart';
import '../widgets/table.dart';

/// BitLocker recovery keys reported by Windows devices. Opened from a device
/// with Console.I.go('Bitlocker', {'peer_id': id}) to show only its keys.
class BitlockerPage extends StatefulWidget {
  const BitlockerPage({super.key});

  @override
  State<BitlockerPage> createState() => _BitlockerPageState();
}

class _BitlockerPageState extends State<BitlockerPage> {
  late final ListCtl ctl;

  @override
  void initState() {
    super.initState();
    ctl = ListCtl((q) => api.get('/bitlocker/list', params: q),
        query: {'key_id': '', 'hostname': '', 'peer_id': '${Console.I.args['peer_id'] ?? ''}', 'include_removed': 0})
      ..load();
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  /// Shows one recovery password. It lives only as long as the dialog.
  Future<void> _reveal(Row_ r) async {
    final String password;
    try {
      final d = await api.post('/bitlocker/reveal', body: {'id': r['id']});
      password = '${(d is Map ? d['recovery_password'] : null) ?? ''}';
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await showCtDialog(
      context,
      title: T('BitlockerRecoveryKey'),
      width: 640,
      builder: (ctx, set) {
        final c = ctx.ct;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${r['hostname'] ?? ''} · ${r['peer_id'] ?? ''} · ${r['mount_point'] ?? ''}', style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(height: 6),
          Text('${T('BitlockerKeyId')}: ${r['key_protector_id'] ?? ''}', style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: c.muted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(color: c.surface2, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(6)),
            child: SelectableText(password,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1, height: 1.5, color: c.text)),
          ),
          const SizedBox(height: 14),
          CtAlert(T('BitlockerRevealLogged')),
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Copy'), icon: Icons.copy_outlined, onPressed: () => copyText(password)),
        CtButton(T('Close'), tone: Tone.primary, onPressed: () => Navigator.of(ctx).pop()),
      ],
    );
  }

  Widget _keyCell(Row_ r) {
    final id = '${r['key_protector_id'] ?? ''}';
    if (id.isEmpty) return const Text('-');
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Flexible(child: Tooltip(message: id, child: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)))),
      CopyIcon(id),
    ]);
  }

  Widget _protection(Row_ r) => switch (asInt(r['protection_status'])) {
        1 => CtTag(T('On'), tone: Tone.success, small: true),
        0 => CtTag(T('Off'), tone: Tone.warning, small: true),
        _ => CtTag(T('Unknown'), tone: Tone.info, small: true),
      };

  Widget _status(Row_ r) {
    final removed = asInt(r['removed_at']);
    return Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
      removed > 0
          ? CtTag(T('BitlockerRemovedOn', {'date': formatTime(removed, seconds: false)}), tone: Tone.warning, small: true)
          : CtTag(T('Active'), tone: Tone.success, small: true),
      if (asInt(r['peer_row_id']) == 0) CtTag(T('BitlockerDeviceDeleted'), tone: Tone.danger, small: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListPage(
      ctl: ctl,
      queryAbove: Padding(padding: const EdgeInsets.only(bottom: 12), child: Muted(T('BitlockerKeysHelp'))),
      filters: () => [
        QueryField(T('BitlockerKeyId'), qText(ctl, 'key_id', width: 200), width: 200),
        QueryField(T('Hostname'), qText(ctl, 'hostname')),
        QueryField(T('DeviceId'), qText(ctl, 'peer_id')),
        CtCheckbox(
          value: ctl.query['include_removed'] == 1,
          label: Text(T('BitlockerShowRemoved')),
          onChanged: (v) {
            ctl.set('include_removed', v ? 1 : 0);
            ctl.filter();
          },
        ),
        Buttons([CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter)]),
      ],
      columns: () => [
        Col(T('Hostname'), prop: 'hostname', minWidth: 140, ellipsis: true),
        Col(T('DeviceId'), width: 140, cell: (r, _) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text('${r['peer_id'] ?? ''}')),
              CopyIcon('${r['peer_id'] ?? ''}'),
            ])),
        Col(T('BitlockerDrive'), width: 80, cell: (r, _) => Text('${r['mount_point'] ?? ''}'.isEmpty ? '-' : '${r['mount_point']}')),
        Col(T('BitlockerKeyId'), minWidth: 220, cell: (r, _) => _keyCell(r)),
        Col(T('BitlockerProtection'), width: 110, cell: (r, _) => _protection(r)),
        Col(T('LastSeen'), width: 150, cell: (r, _) {
          final t = asInt(r['last_seen']);
          return Tooltip(message: formatTime(t), child: Text(t > 0 ? timeAgo(t) : '-'));
        }),
        Col(T('Status'), width: 200, cell: (r, _) => _status(r)),
        Col(T('Actions'),
            width: 110,
            cell: (r, _) => Actions_([
                  CtButton(T('BitlockerReveal'), tone: Tone.primary, size: BtnSize.table, icon: Icons.key_outlined, onPressed: () => _reveal(r)),
                ])),
      ],
    );
  }
}
