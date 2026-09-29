import 'dart:convert';

import 'package:flutter/material.dart';

import '../console.dart';
import '../i18n.dart';
import '../save.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/basic.dart';
import '../widgets/dialog.dart';
import '../widgets/form.dart';
import '../widgets/listpage.dart';
import '../widgets/select.dart';
import '../widgets/table.dart';
import 'peers.dart' show Totals;

/// Confirm, then delete the given rows with a batch endpoint.
Future<bool> batchDelete(BuildContext context, List<Row_> rows, String path, {String key = 'ids', String field = 'id', bool single = false}) async {
  if (rows.isEmpty) {
    Toasts.warning(T('PleaseSelectData'));
    return false;
  }
  if (!await confirm(context, T('Confirm?', {'param': T(single ? 'Delete' : 'BatchDelete')}))) return false;
  try {
    await api.post(path, body: {key: rows.map((r) => r[field]).toList()});
    Toasts.success(T('OperationSuccess'));
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> deleteOne(BuildContext context, Row_ r, String path) async {
  if (!await confirm(context, T('Confirm?', {'param': T('Delete')}))) return false;
  try {
    await api.post(path, body: {'id': r['id']});
    Toasts.success(T('OperationSuccess'));
    return true;
  } catch (_) {
    return false;
  }
}

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  final ctl = ListCtl((q) => api.get('/audit_alarm/list', params: q), query: {'peer_id': '', 'ip': ''}, pageSize: 20)..load();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _del(List<Row_> rows) async {
    if (await batchDelete(context, rows, '/audit_alarm/delete', single: true)) ctl.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ListPage(
      ctl: ctl,
      selectable: true,
      queryBelow: Muted(T('SecurityAlertsHelp')),
      filters: () => [
        QueryField(T('Peer'), qText(ctl, 'peer_id')),
        QueryField('IP', qText(ctl, 'ip')),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('BatchDelete'), tone: Tone.danger, onPressed: () => _del(ctl.selectedRows)),
        ]),
      ],
      columns: () {
        final types = Map<String, dynamic>.from((ctl.data is Map ? ctl.data['types'] : null) as Map? ?? {});
        return [
          Col(T('Time'), prop: 'created_at', width: 170),
          Col(T('Peer'), prop: 'peer_id', width: 130),
          Col(T('Alert'),
              minWidth: 240,
              center: false,
              cell: (r, _) {
                final t = asInt(r['typ']);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: CtTag('${types['$t'] ?? T('AlertType', {'n': t})}', tone: t == 0 || t == 10 ? Tone.warning : Tone.danger),
                );
              }),
          Col(T('FromIp'), prop: 'ip', width: 150),
          Col(T('FromPeer'),
              width: 170,
              cell: (r, _) => Text.rich(TextSpan(children: [
                    TextSpan(text: '${r['from_id'] ?? ''}'.isEmpty ? '-' : '${r['from_id']}'),
                    if ('${r['from_name'] ?? ''}'.isNotEmpty) TextSpan(text: ' (${r['from_name']})', style: TextStyle(color: c.muted)),
                  ]))),
          Col(T('Actions'), width: 120, cell: (r, _) => CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del([r]))),
        ];
      },
    );
  }
}

class AdminLogPage extends StatefulWidget {
  const AdminLogPage({super.key});

  @override
  State<AdminLogPage> createState() => _AdminLogPageState();
}

class _AdminLogPageState extends State<AdminLogPage> {
  final ctl = ListCtl((q) => api.get('/admin_log/list', params: q), query: {'username': '', 'action': ''}, pageSize: 20)..load();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  dynamic _parse(dynamic s) {
    try {
      return jsonDecode('$s');
    } catch (_) {
      return null;
    }
  }

  String _pretty(dynamic s) {
    final v = _parse(s);
    return v == null ? '$s' : const JsonEncoder.withIndent('  ').convert(v);
  }

  String _target(dynamic s) {
    final v = _parse(s);
    if (v is! Map) return '-';
    for (final k in ['name', 'username', 'peer_id', 'id', 'row_id', 'ids', 'row_ids']) {
      final x = v[k];
      if (x != null && x != '') return '$k: ${x is List ? x.join(', ') : x}';
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return ListPage(
      ctl: ctl,
      sizes: const [20, 50, 100, 200],
      queryBelow: Muted(T('AdminActivityHelp')),
      filters: () => [
        QueryField(T('Username'), qText(ctl, 'username')),
        QueryField(T('Action'), qText(ctl, 'action')),
        CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
      ],
      expand: (r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: '${r['method']} ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: '${r['path']}'),
        ])),
        const SizedBox(height: 8),
        '${r['detail'] ?? ''}'.isNotEmpty ? CodeBox(_pretty(r['detail']), block: true) : Muted(T('NoDetails')),
      ]),
      columns: () => [
        Col(T('Time'), prop: 'created_at', width: 170),
        Col(T('Username'),
            width: 170,
            cell: (r, _) => Wrap(spacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${r['username'] ?? ''}'.isEmpty ? '-' : '${r['username']}'),
                  if (r['api_key'] == true)
                    Tooltip(
                      message: '${r['via'] ?? ''}'.isEmpty ? T('ApiKey') : '${r['via']}',
                      child: CtTag('${r['via'] ?? ''}'.isEmpty ? T('ApiKey') : '${r['via']}'.replaceFirst(RegExp(r'^API key '), ''), small: true, tone: Tone.info),
                    ),
                ])),
        Col(T('Action'), prop: 'action', minWidth: 220, center: false),
        Col(T('Target'), minWidth: 160, center: false, cell: (r, _) => Tooltip(message: _target(r['detail']), child: Text(_target(r['detail']), maxLines: 1, overflow: TextOverflow.ellipsis))),
        const Col('IP', prop: 'ip', width: 140),
        Col(T('Result'),
            width: 150,
            cell: (r, _) => r['success'] == true
                ? CtTag(T('Done'), tone: Tone.success)
                : Tooltip(message: '${r['message'] ?? ''}'.isEmpty ? T('Failed') : '${r['message']}', child: CtTag(T('Failed'), tone: Tone.danger))),
      ],
    );
  }
}

class ConnLogPage extends StatefulWidget {
  const ConnLogPage({super.key});

  @override
  State<ConnLogPage> createState() => _ConnLogPageState();
}

class _ConnLogPageState extends State<ConnLogPage> {
  final ctl = ListCtl((q) => api.get('/audit_conn/list', params: q), query: {'peer_id': '', 'from_peer': ''})..load();
  final canDisconnect = can(['peers.manage']);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _kick(Row_ r) async {
    if (!await confirm(context, T('DisconnectConfirm', {'id': r['peer_id']}), confirmText: T('Disconnect'))) return;
    try {
      await api.post('/audit_conn/disconnect', body: {'id': r['id']});
      Toasts.success(T('DisconnectSent'));
    } catch (_) {}
  }

  Future<void> _export() async {
    try {
      final d = await api.get('/audit_conn/list', params: {...ctl.query, 'page': 1, 'page_size': 1000000});
      await exportCsv('connectLog.csv', rowsOf(d));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ListPage(
      ctl: ctl,
      selectable: true,
      filters: () => [
        QueryField(T('Peer'), qText(ctl, 'peer_id')),
        QueryField(T('FromPeer'), qText(ctl, 'from_peer')),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('BatchDelete'), tone: Tone.danger, onPressed: () async {
            if (ctl.selectedRows.isNotEmpty && await batchDelete(context, ctl.selectedRows, '/audit_conn/batchDelete')) ctl.load();
          }),
          CtButton(T('Export'), tone: Tone.success, onPressed: _export),
        ]),
      ],
      columns: () => [
        const Col('ID', prop: 'id', width: 100),
        Col(T('Peer'), prop: 'peer_id', width: 120),
        Col(T('FromPeer'), prop: 'from_peer', width: 120),
        Col(T('FromName'), prop: 'from_name', width: 120),
        Col(T('Ip'), prop: 'ip', width: 120),
        Col(T('Type'), width: 120, cell: (r, _) => r['type'] == 1 ? CtTag(T('File'), tone: Tone.warning) : CtTag(T('Common'))),
        const Col('uuid', prop: 'uuid', width: 120, ellipsis: true),
        Col(T('CreatedAt'), prop: 'created_at'),
        Col(T('CloseTime'),
            cell: (r, _) => asInt(r['close_time']) == 0 ? CtTag(T('Active'), tone: Tone.success) : Text(formatTime(asInt(r['close_time'])))),
        Col(T('Note'),
            minWidth: 160,
            cell: (r, _) => '${r['note'] ?? ''}'.isEmpty
                ? const Text('-')
                : Tooltip(
                    message: '${r['note']}',
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${r['note']}'),
                        if ('${r['note_by'] ?? ''}'.isNotEmpty) TextSpan(text: ' (${r['note_by']})', style: TextStyle(color: c.muted)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
        Col(T('Actions'),
            width: 220,
            cell: (r, _) => Actions_([
                  if (canDisconnect && asInt(r['close_time']) == 0) CtButton(T('Disconnect'), tone: Tone.warning, size: BtnSize.table, onPressed: () => _kick(r)),
                  CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () async {
                    if (await deleteOne(context, r, '/audit_conn/delete')) ctl.load();
                  }),
                ])),
      ],
    );
  }
}

class FileLogPage extends StatefulWidget {
  const FileLogPage({super.key});

  @override
  State<FileLogPage> createState() => _FileLogPageState();
}

class _FileLogPageState extends State<FileLogPage> {
  final ctl = ListCtl((q) => api.get('/audit_file/list', params: q), query: {'peer_id': '', 'from_peer': ''}, decorate: (rows) async {
    for (final r in rows) {
      try {
        r['info'] = '${r['info'] ?? ''}'.isEmpty ? null : jsonDecode('${r['info']}');
      } catch (_) {
        r['info'] = null;
      }
    }
  })
    ..load();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  List<List> _files(Row_ r) => [for (final f in ((r['info'] as Map?)?['files'] as List? ?? const [])) f as List];

  void _allFiles(List<List> files) => showCtDialog(
        context,
        title: T('File'),
        width: 700,
        builder: (ctx, set) => CtTable(small: true, rows: [for (var i = 0; i < files.length; i++) {'n': i + 1, 'name': files[i][0], 'size': files[i][1]}], columns: [
          Col(T('IndexNum'), prop: 'n', width: 120),
          Col(T('FileName'), prop: 'name'),
          Col(T('Size'), cell: (r, _) => Text(sizeFormat(r['size'] as num?))),
        ]),
        footer: (ctx, set) => [CtButton(T('Close'), tone: Tone.primary, onPressed: () => Navigator.of(ctx).pop())],
      );

  Future<void> _export() async {
    try {
      final d = await api.get('/audit_file/list', params: {...ctl.query, 'page': 1, 'page_size': 1000000});
      await exportCsv('fileTransformLog.csv', rowsOf(d));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ListPage(
      ctl: ctl,
      selectable: true,
      filters: () => [
        QueryField(T('Peer'), qText(ctl, 'peer_id')),
        QueryField(T('FromPeer'), qText(ctl, 'from_peer')),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('BatchDelete'), tone: Tone.danger, onPressed: () async {
            if (ctl.selectedRows.isNotEmpty && await batchDelete(context, ctl.selectedRows, '/audit_file/batchDelete')) ctl.load();
          }),
          CtButton(T('Export'), tone: Tone.success, onPressed: _export),
        ]),
      ],
      columns: () => [
        const Col('ID', prop: 'id', width: 100),
        Col(T('Peer'), prop: 'peer_id', width: 120),
        Col(T('FromPeer'), prop: 'from_peer', width: 120),
        Col(T('FromName'), prop: 'from_name', width: 120),
        Col(T('Ip'), prop: 'ip', width: 120),
        Col(T('Type'),
            width: 200,
            cell: (r, _) => r['type'] == 1
                ? CtTag('${T('ToRemote')}: → ${r['peer_id']}', tone: Tone.warning)
                : CtTag('${T('ToLocal')}: → ${r['from_peer']}')),
        Col(T('Num'), prop: 'num', width: 100),
        Col(T('FileInfo'),
            width: 300,
            cell: (r, _) {
              final files = _files(r);
              if (files.isEmpty) return const Text('-');
              if (r['is_file'] == true) return Text(sizeFormat(files.first[1] as num?));
              return Column(mainAxisSize: MainAxisSize.min, children: [
                for (final f in files.take(3))
                  Row(children: [
                    Expanded(child: Tooltip(message: '${f[0]}', child: Text('${f[0]}', maxLines: 1, overflow: TextOverflow.ellipsis))),
                    const SizedBox(width: 8),
                    Text(sizeFormat(f[1] as num?), style: TextStyle(color: c.muted)),
                  ]),
                if (files.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: CtButton('${T('More')}(${files.length - 3})', tone: Tone.primary, size: BtnSize.small, expand: true, onPressed: () => _allFiles(files)),
                  ),
              ]);
            }),
        Col(T('Path'), prop: 'path', width: 150, ellipsis: true),
        const Col('uuid', prop: 'uuid', width: 120, ellipsis: true),
        Col(T('CreatedAt'), prop: 'created_at', minWidth: 120),
        Col(T('Actions'),
            width: 150,
            cell: (r, _) => CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () async {
                  if (await deleteOne(context, r, '/audit_file/delete')) ctl.load();
                })),
      ],
    );
  }
}

class LoginLogPage extends StatefulWidget {
  final bool mine;
  const LoginLogPage({super.key, required this.mine});

  @override
  State<LoginLogPage> createState() => _LoginLogPageState();
}

class _LoginLogPageState extends State<LoginLogPage> {
  late final ListCtl ctl;
  List<Row_> users = [];

  String get base => widget.mine ? '/my/login_log' : '/login_log';

  @override
  void initState() {
    super.initState();
    ctl = ListCtl((q) => api.get('$base/list', params: q), query: {'is_my': 0, 'user_id': null}, decorate: (rows) async {
      // client sign-ins carry the device's uuid; show which device it was
      final uuids = rows.where((r) => '${r['uuid'] ?? ''}'.isNotEmpty && r['client'] == 'client' && '${r['device_id'] ?? ''}'.isEmpty).map((r) => '${r['uuid']}').toSet();
      final peers = <String, Row_>{};
      await Future.wait(uuids.map((u) async {
        try {
          final d = await api.get(widget.mine ? '/my/peer/list' : '/peer/list', params: {'uuids': u, 'page': 1, 'page_size': 10}, quiet: true);
          for (final p in rowsOf(d)) {
            peers['${p['uuid']}'] = p;
          }
        } catch (_) {}
      }));
      for (final r in rows) {
        if (peers['${r['uuid']}'] != null) r['peer'] = peers['${r['uuid']}'];
      }
    })
      ..load();
    if (!widget.mine) Lookups.users().then((u) => setState(() => users = u));
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    try {
      final d = await api.get('/login_log/list', params: {...ctl.query, 'page': 1, 'page_size': 1000000});
      await exportCsv('loginLog.csv', rowsOf(d));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListPage(
      ctl: ctl,
      selectable: true,
      filters: () => [
        if (!widget.mine) QueryField(T('User'), qSelect<int>(ctl, 'user_id', [for (final u in users) Opt(asInt(u['id']), '${u['username']}')], filterable: true)),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('BatchDelete'), tone: Tone.danger, onPressed: () async {
            if (ctl.selectedRows.isNotEmpty && await batchDelete(context, ctl.selectedRows, '$base/batchDelete')) ctl.load();
          }),
          if (!widget.mine) CtButton(T('Export'), tone: Tone.success, onPressed: _export),
        ]),
      ],
      columns: () => [
        if (!widget.mine) const Col('ID', prop: 'id', width: 100),
        if (!widget.mine)
          Col(T('Owner'), width: 120, cell: (r, _) => asInt(r['user_id']) > 0 ? CtTag(nameOf(users, r['user_id'], field: 'username')) : const SizedBox()),
        const Col('client', prop: 'client', width: 120),
        Col(T('Peer'), cell: (r, _) => Text('${r['device_id'] ?? ''}'.isNotEmpty ? '${r['device_id']}' : '${(r['peer'] as Map?)?['id'] ?? ''}')),
        const Col('uuid', prop: 'uuid'),
        const Col('ip', prop: 'ip', width: 150),
        const Col('type', prop: 'type', width: 100),
        const Col('Platform/UA', prop: 'platform', width: 120, ellipsis: true),
        Col(T('CreatedAt'), prop: 'created_at'),
        Col(T('Actions'),
            width: 200,
            cell: (r, _) => CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () async {
                  if (await deleteOne(context, r, '$base/delete')) ctl.load();
                })),
      ],
    );
  }
}

class ShareRecordPage extends StatefulWidget {
  final bool mine;
  const ShareRecordPage({super.key, required this.mine});

  @override
  State<ShareRecordPage> createState() => _ShareRecordPageState();
}

class _ShareRecordPageState extends State<ShareRecordPage> {
  late final ListCtl ctl;
  List<Row_> users = [];

  String get base => widget.mine ? '/my/share_record' : '/share_record';

  @override
  void initState() {
    super.initState();
    ctl = ListCtl((q) => api.get('$base/list', params: q), query: {'user_id': null})..load();
    if (!widget.mine) Lookups.users().then((u) => setState(() => users = u));
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  bool _expired(Row_ r) {
    final e = asInt(r['expire']);
    if (e == 0) return false;
    final created = DateTime.tryParse('${r['created_at']}')?.millisecondsSinceEpoch ?? 0;
    return e * 1000 + created < DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    return ListPage(
      ctl: ctl,
      selectable: true,
      filters: () => [
        if (!widget.mine) QueryField(T('User'), qSelect<int>(ctl, 'user_id', [for (final u in users) Opt(asInt(u['id']), '${u['username']}')], filterable: true)),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('BatchDelete'), tone: Tone.danger, onPressed: () async {
            if (ctl.selectedRows.isNotEmpty && await batchDelete(context, ctl.selectedRows, '$base/batchDelete')) ctl.load();
          }),
        ]),
      ],
      columns: () => [
        const Col('ID', prop: 'id', width: 100),
        if (!widget.mine)
          Col(T('User'), width: 120, cell: (r, _) => asInt(r['user_id']) > 0 ? CtTag(nameOf(users, r['user_id'], field: 'username')) : const SizedBox()),
        Col(T('Peer'), prop: 'peer_id'),
        Col(T('CreatedAt'), prop: 'created_at'),
        Col('${T('ExpireTime')} (${T('Second')})',
            cell: (r, _) => CtTag(asInt(r['expire']) > 0 ? '${r['expire']}' : T('Forever'), tone: _expired(r) ? Tone.info : Tone.success)),
        Col(T('Actions'),
            width: 200,
            cell: (r, _) => CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () async {
                  if (await deleteOne(context, r, '$base/delete')) ctl.load();
                })),
      ],
    );
  }
}

class UsageReportPage extends StatefulWidget {
  const UsageReportPage({super.key});

  @override
  State<UsageReportPage> createState() => _UsageReportPageState();
}

class _UsageReportPageState extends State<UsageReportPage> {
  late DateTimeRange range;
  int? groupId;
  List<Row_> groups = [];
  bool loading = false;
  String tab = 'customers';
  Map<String, dynamic> report = {'sessions': 0, 'seconds': 0, 'no_end': 0, 'groups': [], 'list': []};
  String? fCustomer, fTechnician, fStatus;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    range = DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month, now.day));
    _load();
    Lookups.deviceGroups().then((g) => setState(() => groups = g));
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
  String hours(num s) {
    final h = s ~/ 3600;
    final m = ((s % 3600) / 60).round();
    return h > 0 ? '${h}h ${_pad(m)}m' : '${m}m';
  }

  String when(dynamic t) => formatTime(asInt(t), seconds: false);

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await api.get('/report/usage', params: {'from': formatDay(range.start), 'to': formatDay(range.end), 'group_id': groupId ?? 0});
      setState(() {
        report = Map<String, dynamic>.from(d as Map);
        fCustomer = fTechnician = fStatus = null;
      });
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  List<Row_> get list => rowsOf(report['list']);
  List<Row_> get filtered => list
      .where((r) =>
          (fCustomer == null || r['group_name'] == fCustomer) && (fTechnician == null || r['technician'] == fTechnician) && (fStatus == null || r['status'] == fStatus))
      .toList();

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: range,
      builder: (ctx, child) => Theme(data: consoleTheme(Console.I.dark), child: child!),
    );
    if (picked != null) setState(() => range = picked);
  }

  Future<void> _csv() async {
    String q(dynamic v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
    final rows = [
      ['Started', 'Ended', 'Minutes', 'Status', 'Customer', 'Device', 'RustDesk ID', 'Technician', 'Type', 'Note'],
      for (final r in filtered)
        [
          when(r['started_at']),
          asInt(r['ended_at']) > 0 ? when(r['ended_at']) : '',
          (asInt(r['seconds']) / 60).toStringAsFixed(1),
          r['status'],
          r['group_name'],
          r['device'],
          r['peer_id'],
          r['technician'],
          r['type'],
          r['note'],
        ],
    ];
    final csv = rows.map((r) => r.map(q).join(',')).join('\r\n');
    await saveBytes('support-sessions-${formatDay(range.start)}-to-${formatDay(range.end)}.csv', utf8.encode(csv));
  }

  @override
  Widget build(BuildContext context) {
    final sessions = asInt(report['sessions']), seconds = asInt(report['seconds']), noEnd = asInt(report['no_end']);
    final customers = rowsOf(report['groups']);
    final techs = list.map((r) => '${r['technician']}').toSet().toList()..sort();
    final f = filtered;
    return PageColumn([
      CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHead(T('UsageReport'), help: T('UsageReportHelp')),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            QueryField(
              T('DateRange'),
              CtButton('${formatDay(range.start)}  →  ${formatDay(range.end)}', icon: Icons.date_range, onPressed: _pickRange),
              width: 260,
            ),
            QueryField(
              T('Customer'),
              CtSelect<int>(
                value: groupId,
                clearable: true,
                filterable: true,
                placeholder: T('AllCustomers'),
                options: [for (final g in groups) Opt(asInt(g['id']), '${g['name']}')],
                onChanged: (v) => setState(() => groupId = v),
              ),
              width: 220,
            ),
            Buttons([
              CtButton(T('Filter'), tone: Tone.primary, onPressed: _load),
              CtButton(T('DownloadCsv'), onPressed: list.isEmpty ? null : _csv),
            ]),
          ]),
          const SizedBox(height: 18),
          Totals([
            ('$sessions', T('Sessions'), false),
            (hours(seconds), T('SupportTime'), false),
            (sessions > 0 ? hours((seconds / (sessions - noEnd).clamp(1, 1 << 30)).round()) : '-', T('AverageSession'), false),
            ('${customers.length}', T('Customers'), false),
            if (noEnd > 0) ('$noEnd', T('NoEndRecorded'), true),
          ]),
          if (noEnd > 0) CtAlert(T('NoEndRecordedHelp', {'n': noEnd}), margin: const EdgeInsets.only(top: 14)),
        ]),
      ),
      CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CtTabs<String>(
            value: tab,
            tabs: [('customers', T('ByCustomer')), ('sessions', T('SessionList', {'n': f.length}))],
            onChanged: (v) => setState(() => tab = v),
          ),
          if (tab == 'customers') ...[
            Muted(T('ByCustomerHelp'), padding: const EdgeInsets.only(bottom: 10)),
            CtTable(
              loading: loading,
              rows: customers,
              expand: (r) => CtTable(small: true, rows: rowsOf(r['technicians']), columns: [
                Col(T('Technician'), prop: 'name', minWidth: 200, center: false),
                Col(T('Sessions'), prop: 'sessions', width: 120),
                Col(T('SupportTime'), width: 160, cell: (t, _) => Text(hours(asInt(t['seconds'])))),
              ]),
              columns: [
                Col(T('Customer'), prop: 'group_name', minWidth: 200, center: false),
                Col(T('Sessions'), prop: 'sessions', width: 110),
                Col(T('SupportTime'), width: 140, cell: (r, _) => Text(hours(asInt(r['seconds'])))),
                Col(T('Devices'), prop: 'devices', width: 100),
                Col(T('NoEndRecorded'), width: 150, cell: (r, _) => Text(asInt(r['no_end']) > 0 ? '${r['no_end']}' : '-')),
                Col(T('Actions'),
                    width: 150,
                    cell: (r, _) => CtButton(T('ViewSessions'), size: BtnSize.small, onPressed: () => setState(() {
                          fCustomer = '${r['group_name']}';
                          fTechnician = null;
                          fStatus = null;
                          tab = 'sessions';
                        }))),
              ],
            ),
          ] else ...[
            Wrap(spacing: 24, runSpacing: 12, children: [
              QueryField(
                T('Customer'),
                CtSelect<String>(
                  value: fCustomer,
                  clearable: true,
                  placeholder: T('All'),
                  options: [for (final g in customers) Opt('${g['group_name']}', '${g['group_name']}')],
                  onChanged: (v) => setState(() => fCustomer = v),
                ),
                width: 200,
              ),
              QueryField(
                T('Technician'),
                CtSelect<String>(value: fTechnician, clearable: true, placeholder: T('All'), options: [for (final t in techs) Opt(t, t)], onChanged: (v) => setState(() => fTechnician = v)),
                width: 200,
              ),
              QueryField(
                T('Status'),
                CtSelect<String>(
                  value: fStatus,
                  clearable: true,
                  placeholder: T('All'),
                  options: [Opt('ended', T('Ended')), Opt('active', T('Active')), Opt('no_end', T('NoEndRecorded'))],
                  onChanged: (v) => setState(() => fStatus = v),
                ),
                width: 170,
              ),
            ]),
            const SizedBox(height: 14),
            CtTable(loading: loading, small: true, maxHeight: 620, rows: f, columns: [
              Col(T('Started'), width: 150, center: false, cell: (r, _) => Text(when(r['started_at']))),
              Col(T('Length'),
                  width: 120,
                  cell: (r, _) => r['status'] == 'no_end'
                      ? Tooltip(message: T('NoEndRowHelp'), child: CtTag(T('NoEnd'), small: true, tone: Tone.info))
                      : Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(hours(asInt(r['seconds']))),
                          if (r['status'] == 'active') CtTag(T('Active'), small: true, tone: Tone.success),
                        ])),
              Col(T('Customer'), prop: 'group_name', minWidth: 150, center: false, ellipsis: true),
              Col(T('Peer'), prop: 'device', minWidth: 190, center: false, ellipsis: true),
              Col(T('Technician'), prop: 'technician', minWidth: 150, center: false, ellipsis: true),
              Col(T('Type'), prop: 'type', width: 120, center: false),
              Col(T('Note'), prop: 'note', minWidth: 180, center: false, ellipsis: true),
            ]),
          ],
        ]),
      ),
    ]);
  }
}

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  final ctl = ListCtl((q) => api.get('/recording/list', params: q), query: {'peer_id': ''}, pageSize: 20)..load();
  Map<String, dynamic> settings = {'enabled': false, 'quota_gb': 20, 'retention_days': 30, 'used_bytes': 0};
  bool saving = false;
  final canSettings = can(['settings']);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final d = await api.get('/recording/settings', quiet: true);
      setState(() => settings = Map<String, dynamic>.from(d as Map));
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await api.post('/recording/settings', body: settings);
      Toasts.success(T('OperationSuccess'));
    } catch (_) {}
    if (mounted) setState(() => saving = false);
    _loadSettings();
  }

  Future<String> _link(Row_ r) async {
    try {
      final d = await api.post('/recording/link', body: {'id': r['id']});
      return '${d['url']}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _del(List<Row_> rows) async {
    if (await batchDelete(context, rows, '/recording/delete', single: true)) {
      ctl.load();
      _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final quota = asInt(settings['quota_gb']);
    final used = asInt(settings['used_bytes']);
    final pct = quota == 0 ? 0.0 : (used / (quota * 1073741824)).clamp(0.0, 1.0);
    return ListPage(
      ctl: ctl,
      selectable: true,
      before: [
        CtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHead(
              T('SessionRecordings'),
              help: T('SessionRecordingsHelp'),
              trailing: SizedBox(
                width: 260,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Muted(T('StorageUsed', {'used': sizeFormat(used), 'quota': '$quota GB'})),
                  const SizedBox(height: 6),
                  CtBar(fraction: pct, color: pct >= 0.9 ? c.danger : c.primary),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              QueryField(T('AcceptUploads'),
                  Align(alignment: Alignment.centerLeft, child: CtSwitch(value: settings['enabled'] == true, onChanged: canSettings ? (v) => setState(() => settings['enabled'] = v) : null)),
                  width: 50),
              QueryField(T('StorageLimitGB'),
                  CtNumberInput(value: quota, min: 1, max: 10000, onChanged: canSettings ? (v) => setState(() => settings['quota_gb'] = v) : null), width: 150),
              QueryField(T('KeepForDays'),
                  CtNumberInput(value: asInt(settings['retention_days']), max: 3650, onChanged: canSettings ? (v) => setState(() => settings['retention_days'] = v) : null),
                  width: 150),
              if (canSettings) CtButton(T('Save'), tone: Tone.primary, loading: saving, onPressed: _save),
            ]),
            Muted(T('SessionRecordingsSetup'), padding: const EdgeInsets.only(top: 14)),
          ]),
        ),
      ],
      filters: () => [
        QueryField(T('Peer'), qText(ctl, 'peer_id')),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('BatchDelete'), tone: Tone.danger, onPressed: () => _del(ctl.selectedRows)),
        ]),
      ],
      columns: () => [
        Col(T('Time'), prop: 'created_at', width: 170),
        Col(T('Peer'), prop: 'peer_id', width: 130),
        Col(T('File'), prop: 'file_name', minWidth: 260, ellipsis: true),
        Col(T('Size'), width: 110, cell: (r, _) => Text(sizeFormat(r['size'] as num?))),
        Col(T('Status'), width: 120, cell: (r, _) => r['complete'] == true ? CtTag(T('Complete'), tone: Tone.success) : CtTag(T('Uploading'), tone: Tone.warning)),
        Col(T('Actions'),
            width: 280,
            cell: (r, _) => Actions_([
                  // recordings open in the system's video player
                  CtButton(T('Play'), tone: Tone.primary, size: BtnSize.table, onPressed: asInt(r['size']) == 0 ? null : () async {
                    final u = await _link(r);
                    if (u.isNotEmpty) openUrl(u);
                  }),
                  CtButton(T('Download'), size: BtnSize.table, onPressed: asInt(r['size']) == 0 ? null : () async {
                    final u = await _link(r);
                    if (u.isNotEmpty) openUrl(u);
                  }),
                  CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del([r])),
                ])),
      ],
    );
  }
}
