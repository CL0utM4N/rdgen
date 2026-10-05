import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../console.dart';
import '../i18n.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/basic.dart';
import '../widgets/dialog.dart';
import '../widgets/form.dart';
import '../widgets/listpage.dart';
import '../widgets/select.dart';
import '../widgets/table.dart';
import 'address_books.dart';

List<Opt<int>> timeFilters() => [
      Opt(-60, T('MinutesLess', {'param': 1}, 1)),
      Opt(-3600, T('HoursLess', {'param': 1}, 1)),
      Opt(-86400, T('DaysLess', {'param': 1}, 1)),
      const Opt(0, '---------', disabled: true),
      Opt(60, T('MinutesAgo', {'param': 1}, 1)),
      Opt(3600, T('HoursAgo', {'param': 1}, 1)),
      Opt(86400, T('DaysAgo', {'param': 1}, 1)),
      Opt(2592000, T('MonthsAgo', {'param': 1}, 1)),
    ];

Widget lastOnline(Row_ r) {
  final t = asInt(r['last_online_time']);
  return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    Flexible(child: Text(t > 0 ? timeAgo(t) : '-')),
    const SizedBox(width: 10),
    Dot(isOnline(t) ? Colors.green : Colors.red, size: 6),
  ]);
}

Widget idCell(Row_ r) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Flexible(child: Text('${r['id']}')),
      CopyIcon('${r['id']}'),
    ]);

/// Pick owners, an address book and tags, then add the ticked devices.
Future<void> batchAddToAb(BuildContext context, {required bool mine, required List<Row_> peers, List<Row_> users = const []}) async {
  if (peers.isEmpty) {
    Toasts.warning(T('PleaseSelectData'));
    return;
  }
  final f = <String, dynamic>{'collection_id': 0, 'tags': <String>[], 'peer_ids': peers.map((p) => p['row_id']).toList(), 'user_id': null};
  var cols = mine ? await Lookups.collections(mine: true) : <Row_>[];
  var tags = mine ? await Lookups.tags(mine: true, collectionId: 0) : <Row_>[];
  if (!context.mounted) return;
  await showCtDialog(
    context,
    title: T('Create'),
    width: 800,
    builder: (ctx, set) => Column(children: [
      if (!mine)
        FormItem(
          label: T('Owner'),
          required: true,
          child: CtSelect<int>(
            value: f['user_id'] as int?,
            filterable: true,
            options: userOpts(users),
            onChanged: (v) async {
              set(() {
                f['user_id'] = v;
                f['collection_id'] = 0;
              });
              if (v != null) {
                final r = await Lookups.collections(mine: false, userId: v);
                set(() => cols = r);
              }
            },
          ),
        ),
      FormItem(
        label: T('AddressBookName'),
        required: true,
        child: CtSelect<int>(
          value: f['collection_id'] as int?,
          clearable: true,
          options: collectionOpts(cols),
          onChanged: (v) async {
            set(() {
              f['collection_id'] = v;
              f['tags'] = <String>[];
            });
            if (mine) {
              final r = await Lookups.tags(mine: true, collectionId: v);
              set(() => tags = r);
            }
          },
        ),
      ),
      if (mine)
        FormItem(
          label: T('Tags'),
          child: CtMultiSelect<String>(
            values: List<String>.from(f['tags'] as List),
            options: [for (final t in tags) Opt('${t['name']}', '${t['name']}')],
            onChanged: (v) => set(() => f['tags'] = v),
          ),
        ),
    ]),
    footer: (ctx, set) => [
      CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
      CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
        try {
          await api.post(mine ? '/my/address_book/batchCreateFromPeers' : '/address_book/batchCreateFromPeers', body: f);
          Toasts.success(T('OperationSuccess'));
          if (ctx.mounted) Navigator.of(ctx).pop();
        } catch (_) {}
      }),
    ],
  );
}

/// Adds one device to the address books of one or more users.
Future<void> addPeerToAb(BuildContext context, Row_ peer, List<Row_> users) async {
  final f = <String, dynamic>{
    'user_ids': <int>[],
    'collection_id': 0,
    'id': peer['id'],
    'username': peer['username'] ?? '',
    'alias': '',
    'hostname': peer['hostname'] ?? '',
    'platform': abPlatformFor('${peer['os'] ?? ''}'),
    'tags': <String>[],
    'uuid': peer['uuid'],
    'hash': '',
  };
  var cols = <Row_>[], tags = <Row_>[];
  await showCtDialog(
    context,
    title: T('Create'),
    width: 800,
    builder: (ctx, set) {
      final ids = f['user_ids'] as List<int>;
      Widget text(String key, String label, {bool required = false}) =>
          FormItem(label: label, required: required, child: CtInput(value: '${f[key] ?? ''}', onChanged: (v) => f[key] = v));
      return Column(children: [
        FormItem(
          label: T('Owner'),
          required: true,
          child: CtMultiSelect<int>(
            values: ids,
            options: userOpts(users),
            onChanged: (v) async {
              set(() {
                f['user_ids'] = v;
                f['collection_id'] = 0;
                f['tags'] = <String>[];
                cols = [];
                tags = [];
              });
              if (v.length == 1) {
                final r = await Lookups.collections(mine: false, userId: v.first);
                set(() => cols = r);
              }
            },
          ),
        ),
        if (ids.length <= 1)
          FormItem(
            label: T('AddressBookName'),
            required: true,
            child: CtSelect<int>(
              value: f['collection_id'] as int?,
              clearable: true,
              options: collectionOpts(cols),
              onChanged: (v) async {
                set(() {
                  f['collection_id'] = v;
                  f['tags'] = <String>[];
                });
                final r = await Lookups.tags(mine: false, userId: ids.isEmpty ? null : ids.first, collectionId: v);
                set(() => tags = r);
              },
            ),
          ),
        text('id', 'ID', required: true),
        text('username', T('Username')),
        text('alias', T('Alias')),
        text('hostname', T('Hostname')),
        FormItem(label: T('Platform'), child: CtSelect<String>(value: '${f['platform']}', options: abPlatforms, onChanged: (v) => set(() => f['platform'] = v ?? ''))),
        if (ids.length <= 1)
          FormItem(
            label: T('Tags'),
            child: CtMultiSelect<String>(
              values: List<String>.from(f['tags'] as List),
              options: [for (final t in tags) Opt('${t['name']}', '${t['name']}')],
              onChanged: (v) => set(() => f['tags'] = v),
            ),
          ),
      ]);
    },
    footer: (ctx, set) => [
      CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
      CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
        final ids = f['user_ids'] as List<int>;
        if (ids.isEmpty) return Toasts.error(T('ParamRequired', {'param': T('Owner')}));
        if ('${f['id']}'.isEmpty) return Toasts.error(T('ParamRequired', {'param': 'ID'}));
        if (ids.length > 1) {
          f['collection_id'] = 0;
          f['tags'] = <String>[];
        }
        try {
          await api.post('/address_book/batchCreate', body: f);
          Toasts.success(T('OperationSuccess'));
          if (ctx.mounted) Navigator.of(ctx).pop();
        } catch (_) {}
      }),
    ],
  );
}

class _Column {
  final String name;
  final String label;
  bool visible;
  _Column(this.name, this.label, this.visible);
}

class PeerPage extends StatefulWidget {
  const PeerPage({super.key});

  @override
  State<PeerPage> createState() => _PeerPageState();
}

class _PeerPageState extends State<PeerPage> {
  final ctl = ListCtl((q) => api.get('/peer/list', params: q), query: {'time_ago': null, 'id': '', 'hostname': '', 'username': '', 'ip': ''});
  List<Row_> groups = [], strategies = [], users = [];
  late List<_Column> columns;
  final canManage = can(['peers.manage']);
  final canAb = can(['address_books']);

  static const all = [
    ('id', 'Id'),
    ('cpu', 'Cpu'),
    ('hostname', 'Hostname'),
    ('memory', 'Memory'),
    ('os', 'Os'),
    ('last_online_time', 'LastOnlineTime'),
    ('last_online_ip', 'LastOnlineIp'),
    ('username', 'Username'),
    ('group_id', 'Group'),
    ('uuid', 'Uuid'),
    ('version', 'Version'),
    ('alias', 'Alias'),
    ('note', 'Note'),
    ('created_at', 'CreatedAt'),
    ('updated_at', 'UpdatedAt'),
  ];

  @override
  void initState() {
    super.initState();
    ctl.load();
    Lookups.deviceGroups().then((g) => setState(() => groups = g));
    Lookups.strategies().then((s) => setState(() => strategies = s));
    if (canAb) Lookups.users().then((u) => setState(() => users = u));
    // keep the saved order and visibility, adding any column introduced since
    var saved = <_Column>[];
    try {
      final raw = jsonDecode(Console.I.host.loadSetting('peer_visible_columns') ?? '[]') as List;
      saved = [
        for (final s in raw)
          if (all.any((a) => a.$1 == s['name'])) _Column('${s['name']}', all.firstWhere((a) => a.$1 == s['name']).$2, s['visible'] != false),
      ];
    } catch (_) {}
    columns = [...saved, for (final a in all) if (!saved.any((s) => s.name == a.$1)) _Column(a.$1, a.$2, true)];
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  /// The device's group; clicking it moves the device to another group
  Widget _groupCell(Row_ r) {
    final current = asInt(r['group_id']);
    final label = current > 0 ? CtTag(nameOf(groups, r['group_id']), icon: canManage ? Icons.expand_more : null) : const Text('-');
    if (!canManage || groups.isEmpty) return label;
    return PopupMenuButton<int>(
      tooltip: T('ChangeGroup'),
      initialValue: current > 0 ? current : null,
      onSelected: (g) => _moveToGroup(r, g),
      itemBuilder: (_) => [
        for (final g in groups) PopupMenuItem(value: asInt(g['id']), child: Text('${g['name']}')),
      ],
      child: current > 0 ? label : CtTag(T('ChooseGroup'), plain: true, icon: Icons.expand_more),
    );
  }

  Future<void> _moveToGroup(Row_ r, int groupId) async {
    if (groupId == asInt(r['group_id'])) return;
    try {
      // fields left out keep their values
      await api.post('/peer/update', body: {'row_id': r['row_id'], 'group_id': groupId});
      Toasts.success(T('MovedToGroup', {'name': nameOf(groups, groupId)}));
      ctl.load();
    } catch (_) {}
  }

  Col _col(String name) {
    switch (name) {
      case 'id':
        return Col('ID', width: 150, cell: (r, _) => idCell(r));
      case 'cpu':
        return const Col('CPU', prop: 'cpu', width: 100, ellipsis: true);
      case 'hostname':
        return Col(T('Hostname'), prop: 'hostname', width: 120);
      case 'memory':
        return Col(T('Memory'), prop: 'memory', width: 120);
      case 'os':
        return Col(T('Os'), prop: 'os', width: 120, ellipsis: true);
      case 'last_online_time':
        return Col(T('LastOnlineTime'), minWidth: 150, cell: (r, _) => lastOnline(r));
      case 'last_online_ip':
        return Col(T('LastOnlineIp'), prop: 'last_online_ip', minWidth: 120);
      case 'username':
        return Col(T('Username'), prop: 'username', width: 120);
      case 'group_id':
        return Col(T('Group'), width: 190, cell: (r, _) => _groupCell(r));
      case 'uuid':
        return Col(T('Uuid'), prop: 'uuid', width: 120, ellipsis: true);
      case 'version':
        return Col(T('Version'), prop: 'version', width: 80);
      case 'alias':
        return Col(T('Alias'), prop: 'alias', width: 120, ellipsis: true);
      case 'note':
        return Col(T('Note'), prop: 'note', minWidth: 160, ellipsis: true);
      case 'created_at':
        return Col(T('CreatedAt'), prop: 'created_at', width: 150);
      default:
        return Col(T('UpdatedAt'), prop: 'updated_at', width: 150);
    }
  }

  Future<void> _edit([Row_? row]) async {
    const keys = ['row_id', 'group_id', 'cpu', 'hostname', 'id', 'memory', 'os', 'username', 'uuid', 'version', 'alias', 'note', 'strategy_id', 'offline_alert_minutes'];
    final f = <String, dynamic>{for (final k in keys) k: row?[k]};
    f['row_id'] ??= 0;
    f['strategy_id'] ??= 0;
    f['offline_alert_minutes'] ??= 0;
    for (final k in ['cpu', 'hostname', 'id', 'memory', 'os', 'username', 'uuid', 'version', 'alias', 'note']) {
      f[k] ??= '';
    }
    await showCtDialog(
      context,
      title: asInt(f['row_id']) == 0 ? T('Create') : T('Update'),
      width: 800,
      builder: (ctx, set) {
        Widget text(String key, String label, {bool required = false, int rows = 1}) =>
            FormItem(label: label, required: required, child: CtInput(value: '${f[key]}', rows: rows, onChanged: (v) => f[key] = v));
        return Column(children: [
          text('id', 'ID', required: true),
          FormItem(
            label: T('Group'),
            child: CtSelect<int>(
              value: f['group_id'] as int?,
              filterable: true,
              options: [for (final g in groups) Opt(asInt(g['id']), '${g['name']}')],
              onChanged: (v) => set(() => f['group_id'] = v),
            ),
          ),
          text('username', T('Username')),
          text('hostname', T('Hostname')),
          text('cpu', 'CPU'),
          text('memory', T('Memory')),
          text('os', T('Os')),
          text('uuid', T('Uuid')),
          text('version', T('Version')),
          text('alias', T('Alias')),
          text('note', T('Note'), rows: 2),
          FormItem(
            label: T('ClientPolicy'),
            child: CtSelect<int>(
              value: asInt(f['strategy_id']),
              options: [Opt(0, T('PolicyInherit')), for (final s in strategies) Opt(asInt(s['id']), '${s['name']}')],
              onChanged: (v) => set(() => f['strategy_id'] = v ?? 0),
            ),
          ),
          FormItem(
            label: T('OfflineAlert'),
            help: T('OfflineAlertHelp'),
            child: Row(children: [
              CtNumberInput(value: asInt(f['offline_alert_minutes']), max: 10080, onChanged: (v) => set(() => f['offline_alert_minutes'] = v)),
              const SizedBox(width: 10),
              Muted(T('UnitMinutes')),
            ]),
          ),
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          try {
            await api.post(asInt(f['row_id']) > 0 ? '/peer/update' : '/peer/create', body: f);
            Toasts.success(T('OperationSuccess'));
            if (ctx.mounted) Navigator.of(ctx).pop();
            ctl.load();
          } catch (_) {}
        }),
      ],
    );
  }

  Future<void> _del(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('Delete')}))) return;
    try {
      await api.post('/peer/delete', body: {'row_id': r['row_id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  Future<void> _batchDelete() async {
    final rows = ctl.selectedRows;
    if (rows.isEmpty) return Toasts.warning(T('PleaseSelectData'));
    if (!await confirm(context, T('Confirm?', {'param': T('BatchDelete')}))) return;
    try {
      await api.post('/peer/batchDelete', body: {'row_ids': rows.map((r) => r['row_id']).toList()});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  // "Update now": the selected devices, or every Windows device
  Future<void> _requestUpdate() async {
    final rows = ctl.selectedRows;
    final msg = rows.isNotEmpty ? T('UpdateNowSelected', {'n': rows.length}) : T('UpdateNowAll');
    if (!await confirm(context, msg, confirmText: T('UpdateNow'), title: T('UpdateNow'), warning: false)) return;
    try {
      final d = await api.post('/peer/requestUpdate',
          body: rows.isNotEmpty ? {'row_ids': rows.map((r) => r['row_id']).toList()} : {'all': true});
      Toasts.success(T('UpdateNowSent', {'n': (d is Map ? d['queued'] : null) ?? 0}));
    } catch (_) {}
  }

  Future<void> _export() async {
    try {
      final d = await api.get('/peer/list', params: {...ctl.query, 'page': 1, 'page_size': 10000});
      final rows = rowsOf(d).map((r) {
        final t = asInt(r['last_online_time']);
        r['last_online_time'] = t > 0 ? formatTime(t) : '-';
        r.remove('user_id');
        r.remove('user');
        return r;
      }).toList();
      await exportCsv('peers.csv', rows);
    } catch (_) {}
  }

  Future<void> _import() async {
    await showCtDialog(
      context,
      title: T('Import'),
      width: 600,
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(T('Please upload csv file')),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          TextSpan(text: '${T('Columns')}: '),
          const TextSpan(text: 'id,cpu,hostname,memory,os,username,uuid,version,group_id', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ])),
        const SizedBox(height: 4),
        Text(T('You can reference export file')),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Import'), tone: Tone.danger, icon: Icons.upload_file, onPressed: () async {
          final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: true);
          final bytes = picked?.files.single.bytes;
          if (bytes == null) return;
          if (ctx.mounted) Navigator.of(ctx).pop();
          await _importCsv(utf8.decode(bytes));
        }),
      ],
    );
  }

  Future<void> _importCsv(String data) async {
    const allowed = ['id', 'cpu', 'hostname', 'memory', 'os', 'username', 'uuid', 'version', 'group_id'];
    final lines = data.replaceAll('\r', '').split('\n');
    final keys = lines.first.split(',');
    final split = RegExp(r',(?=(?:(?:[^"]*"){2})*[^"]*$)');
    final items = <Map<String, dynamic>>[];
    for (final line in lines.skip(1)) {
      final vals = line.split(split);
      final m = <String, dynamic>{};
      for (var i = 0; i < vals.length && i < keys.length; i++) {
        final k = keys[i].trim();
        if (allowed.contains(k)) m[k] = vals[i].trim().replaceAll(RegExp(r'^"|"$'), '');
      }
      if ('${m['id'] ?? ''}'.isEmpty) continue;
      m['group_id'] = int.tryParse('${m['group_id'] ?? ''}');
      items.add(m);
    }
    try {
      await Future.wait(items.map((m) => api.post('/peer/create', body: m)));
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  Future<void> _columnSettings() async {
    final work = [for (final c in columns) _Column(c.name, c.label, c.visible)];
    await showCtDialog(
      context,
      title: 'Column Setting',
      width: 520,
      builder: (ctx, set) => Column(children: [
        for (var i = 0; i < work.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(width: 220, child: CtCheckbox(value: work[i].visible, label: Text(T(work[i].label)), onChanged: (v) => set(() => work[i].visible = v))),
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                splashRadius: 16,
                onPressed: i == 0 ? null : () => set(() => work.insert(i - 1, work.removeAt(i))),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                splashRadius: 16,
                onPressed: i == work.length - 1 ? null : () => set(() => work.insert(i + 1, work.removeAt(i))),
              ),
            ]),
          ),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Save'), tone: Tone.primary, onPressed: () {
          setState(() => columns = work);
          Console.I.host.saveSetting('peer_visible_columns', jsonEncode([for (final c in work) {'name': c.name, 'visible': c.visible, 'label': c.label}]));
          Toasts.success(T('OperationSuccess'));
          Navigator.of(ctx).pop();
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = Console.I.host;
    return ListPage(
      ctl: ctl,
      selectable: true,
      tableTop: Align(alignment: Alignment.centerRight, child: CtButton('', icon: Icons.settings_outlined, onPressed: _columnSettings)),
      filters: () => [
        QueryField('ID', qText(ctl, 'id')),
        QueryField(T('Hostname'), qText(ctl, 'hostname')),
        QueryField(T('LastOnlineTime'), qSelect<int>(ctl, 'time_ago', timeFilters(), width: 180)),
        QueryField(T('Username'), qText(ctl, 'username')),
        QueryField('IP', qText(ctl, 'ip')),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          if (canManage) CtButton(T('Add'), tone: Tone.danger, onPressed: () => _edit()),
          CtButton(T('Export'), tone: Tone.success, onPressed: _export),
          if (canManage) CtButton(T('Import'), tone: Tone.danger, icon: Icons.keyboard_arrow_down, onPressed: _import),
          if (canManage) CtButton(T('BatchDelete'), tone: Tone.danger, onPressed: _batchDelete),
          if (canManage) CtButton(T('UpdateNow'), tone: Tone.primary, onPressed: _requestUpdate),
          if (canAb) CtButton(T('BatchAddToAB'), tone: Tone.primary, onPressed: () => batchAddToAb(context, mine: false, peers: ctl.selectedRows, users: users)),
        ]),
      ],
      columns: () => [
        for (final c in columns)
          if (c.visible) _col(c.name),
        Col(T('Actions'),
            width: 250,
            cell: (r, _) => Actions_([
                  CtButton(T('Connect'), tone: Tone.success, size: BtnSize.table, onPressed: () => host.connect('${r['id']}')),
                  CtMenuButton(
                    button: CtButton(T('More'), size: BtnSize.table, trailingIcon: Icons.keyboard_arrow_down, onPressed: () {}),
                    actions: [
                      MenuAction(T('TransferFiles'), () => host.connect('${r['id']}', fileTransfer: true)),
                      if (canManage) MenuAction(T('Edit'), () => _edit(r)),
                      if (canAb) MenuAction(T('AddToAddressBook'), () => addPeerToAb(context, r, users)),
                      if (canManage) MenuAction(T('Delete'), () => _del(r), divided: true, danger: true),
                    ],
                  ),
                ])),
      ],
    );
  }
}

class MyPeerPage extends StatefulWidget {
  const MyPeerPage({super.key});

  @override
  State<MyPeerPage> createState() => _MyPeerPageState();
}

class _MyPeerPageState extends State<MyPeerPage> {
  final ctl = ListCtl((q) => api.get('/my/peer/list', params: q), query: {'time_ago': null, 'id': '', 'hostname': ''})..load();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    try {
      final d = await api.get('/my/peer/list', params: {...ctl.query, 'page': 1, 'page_size': 10000});
      final rows = rowsOf(d).map((r) {
        final t = asInt(r['last_online_time']);
        r['last_online_time'] = t > 0 ? formatTime(t) : '-';
        r.remove('user_id');
        r.remove('user');
        return r;
      }).toList();
      await exportCsv('peers.csv', rows);
    } catch (_) {}
  }

  void _view(Row_ r) {
    showCtDialog(
      context,
      title: T('Information'),
      width: 800,
      builder: (ctx, set) => Column(children: [
        for (final f in [
          ('id', 'ID'),
          ('username', T('Username')),
          ('hostname', T('Hostname')),
          ('cpu', 'CPU'),
          ('memory', T('Memory')),
          ('os', T('Os')),
          ('uuid', T('Uuid')),
          ('version', T('Version')),
        ])
          FormItem(label: f.$2, child: CtInput(value: '${r[f.$1] ?? ''}', enabled: false)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = Console.I.host;
    return ListPage(
      ctl: ctl,
      selectable: true,
      filters: () => [
        QueryField('ID', qText(ctl, 'id')),
        QueryField(T('Hostname'), qText(ctl, 'hostname')),
        QueryField(T('LastOnlineTime'), qSelect<int>(ctl, 'time_ago', timeFilters(), width: 180)),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('Export'), tone: Tone.success, onPressed: _export),
          CtButton(T('BatchAddToAB'), tone: Tone.primary, onPressed: () => batchAddToAb(context, mine: true, peers: ctl.selectedRows)),
        ]),
      ],
      columns: () => [
        Col('ID', width: 150, cell: (r, _) => idCell(r)),
        const Col('CPU', prop: 'cpu', width: 100, ellipsis: true),
        Col(T('Hostname'), prop: 'hostname', width: 120),
        Col(T('Memory'), prop: 'memory', width: 120),
        Col(T('Os'), prop: 'os', width: 120, ellipsis: true),
        Col(T('LastOnlineTime'), minWidth: 150, cell: (r, _) => lastOnline(r)),
        Col(T('LastOnlineIp'), prop: 'last_online_ip', minWidth: 120),
        Col(T('Username'), prop: 'username', width: 120),
        Col(T('Uuid'), prop: 'uuid', width: 120, ellipsis: true),
        Col(T('Version'), prop: 'version', width: 80),
        Col(T('Alias'), prop: 'alias', width: 80),
        Col(T('CreatedAt'), prop: 'created_at', width: 150),
        Col(T('UpdatedAt'), prop: 'updated_at', width: 150),
        Col(T('Actions'),
            width: 330,
            cell: (r, _) => Actions_([
                  CtButton(T('Connect'), tone: Tone.success, size: BtnSize.table, onPressed: () => host.connect('${r['id']}')),
                  CtButton(T('AddToAddressBook'), tone: Tone.primary, size: BtnSize.table, onPressed: () async {
                    if (await showAbForm(context, mine: true, peer: r)) Toasts.success(T('OperationSuccess'));
                  }),
                  CtButton(T('View'), size: BtnSize.table, onPressed: () => _view(r)),
                ])),
      ],
    );
  }
}

class VersionReportPage extends StatefulWidget {
  const VersionReportPage({super.key});

  @override
  State<VersionReportPage> createState() => _VersionReportPageState();
}

class _VersionReportPageState extends State<VersionReportPage> {
  bool loading = true;
  Map<String, dynamic> report = {'latest': '', 'versions': [], 'outdated': [], 'unknown': 0};

  @override
  void initState() {
    super.initState();
    api.get('/report/versions').then((d) {
      if (mounted) setState(() => report = Map<String, dynamic>.from(d as Map));
    }).catchError((_) {}).whenComplete(() {
      if (mounted) setState(() => loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final versions = rowsOf(report['versions']);
    final outdated = rowsOf(report['outdated']);
    final total = versions.fold<int>(0, (n, v) => n + asInt(v['devices']));
    final upToDate = versions.where((v) => v['current'] == true).fold<int>(0, (n, v) => n + asInt(v['devices']));
    return Loading(
      loading: loading,
      minHeight: 200,
      child: PageColumn([
        CtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardHead(T('VersionReport'), help: T('VersionReportHelp')),
            const SizedBox(height: 18),
            Totals([
              ('${report['latest'] == null || report['latest'] == '' ? '?' : report['latest']}', T('LatestRelease'), false),
              ('$upToDate', T('UpToDate'), false),
              ('${outdated.length}', T('Outdated'), outdated.isNotEmpty),
              if (asInt(report['unknown']) > 0) ('${report['unknown']}', T('VersionUnknown'), false),
            ]),
            if (!loading && '${report['latest'] ?? ''}'.isEmpty)
              CtAlert(T('LatestUnknown'), margin: const EdgeInsets.only(top: 14)),
          ]),
        ),
        CtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(T('Versions'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final v in versions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 90, child: Text('${v['version']}', style: TextStyle(fontSize: 13, color: c.text2))),
                  Expanded(child: CtBar(fraction: total == 0 ? 0 : asInt(v['devices']) / total, height: 12, color: v['current'] == true ? c.success : c.warning)),
                  SizedBox(width: 50, child: Text('${v['devices']}', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: c.muted))),
                ]),
              ),
          ]),
        ),
        if (outdated.isNotEmpty)
          CtCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(T('OutdatedDevices'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              CtTable(small: true, rows: outdated, columns: [
                Col(T('Peer'), prop: 'device', minWidth: 220, center: false),
                Col(T('Customer'), prop: 'group_name', minWidth: 160, center: false),
                Col(T('Version'), prop: 'version', width: 110),
                Col(T('LastOnlineTime'), width: 160, cell: (r, _) => Text(asInt(r['last_online_time']) > 0 ? timeAgo(asInt(r['last_online_time'])) : '-')),
              ]),
            ]),
          ),
      ]),
    );
  }
}

/// The row of big numbers at the top of report pages.
class Totals extends StatelessWidget {
  final List<(String value, String label, bool warn)> items;
  const Totals(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return Wrap(spacing: 40, runSpacing: 14, children: [
      for (final i in items)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(i.$1, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: i.$3 ? c.warning : c.text)),
          Text(i.$2, style: TextStyle(fontSize: 13, color: c.muted)),
        ]),
    ]);
  }
}
