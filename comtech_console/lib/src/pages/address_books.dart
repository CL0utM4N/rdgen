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

const abPlatforms = [Opt('Windows', 'Windows'), Opt('Linux', 'Linux'), Opt('Mac OS', 'Mac OS'), Opt('Android', 'Android')];

/// The address book platform for a device's OS string.
String abPlatformFor(String os) {
  final o = os.toLowerCase();
  if (o.contains('windows')) return 'Windows';
  if (o.contains('linux')) return 'Linux';
  if (o.contains('android')) return 'Android';
  if (o.contains('mac')) return 'Mac OS';
  return '';
}

List<Opt<int>> collectionOpts(List<Row_> cols) => [
      Opt(0, T('MyAddressBook')),
      for (final c in cols) Opt(asInt(c['id']), '${c['name']}'),
    ];

List<Opt<int>> userOpts(List<Row_> users) => [for (final u in users) Opt(asInt(u['id']), '${u['username']}')];

/// Adds or edits an address book entry. [peer] prefills it from a device.
Future<bool> showAbForm(BuildContext context, {required bool mine, Row_? row, Row_? peer, List<Row_> users = const []}) async {
  final f = <String, dynamic>{
    'row_id': 0,
    'alias': '',
    'forceAlwaysRelay': false,
    'hash': '',
    'hostname': '',
    'id': '',
    'loginName': '',
    'online': false,
    'password': '',
    'platform': '',
    'rdpPort': '',
    'rdpUsername': '',
    'sameServer': false,
    'tags': <String>[],
    'user_id': null,
    'user_ids': <int>[],
    'username': '',
    'collection_id': mine ? 0 : null,
  };
  if (row != null) {
    for (final k in f.keys.toList()) {
      if (row.containsKey(k)) f[k] = row[k];
    }
    f['tags'] = List<String>.from(row['tags'] ?? const []);
  }
  if (peer != null) {
    f['id'] = peer['id'];
    f['username'] = peer['username'];
    f['hostname'] = peer['hostname'];
    f['platform'] = abPlatformFor('${peer['os'] ?? ''}');
    f['uuid'] = peer['uuid'];
  }
  var cols = <Row_>[];
  var tags = <Row_>[];
  Future<void> loadCols(StateSetter set) async {
    final r = await Lookups.collections(mine: mine, userId: mine ? null : f['user_id'] as int?);
    set(() => cols = r);
  }

  Future<void> loadTags(StateSetter set) async {
    final r = await Lookups.tags(mine: mine, userId: mine ? null : f['user_id'] as int?, collectionId: f['collection_id'] as int?);
    set(() => tags = r);
  }

  var started = false;
  final saved = await showCtDialog<bool>(
    context,
    title: row == null ? T('Create') : T('Update'),
    width: 800,
    builder: (ctx, set) {
      if (!started) {
        started = true;
        if (mine || f['user_id'] != null) loadCols(set);
        if (row != null) loadTags(set);
      }
      Widget text(String key, String label, {bool required = false}) => FormItem(
            label: label,
            required: required,
            child: CtInput(value: '${f[key] ?? ''}', onChanged: (v) => f[key] = v),
          );
      return Column(children: [
        if (!mine)
          FormItem(
            label: T('Owner'),
            required: true,
            child: CtSelect<int>(
              value: f['user_id'] as int?,
              filterable: true,
              options: userOpts(users),
              onChanged: (v) {
                set(() {
                  f['user_id'] = v;
                  f['tags'] = <String>[];
                  f['collection_id'] = 0;
                  tags = [];
                  cols = [];
                });
                if (v != null) loadCols(set);
              },
            ),
          ),
        FormItem(
          label: T('AddressBookName'),
          required: mine,
          child: CtSelect<int>(
            value: f['collection_id'] as int?,
            clearable: true,
            options: collectionOpts(cols),
            onChanged: (v) {
              set(() {
                f['collection_id'] = v;
                f['tags'] = <String>[];
                tags = [];
              });
              loadTags(set);
            },
          ),
        ),
        text('id', 'ID', required: true),
        text('username', T('Username')),
        text('alias', T('Alias')),
        text('hash', T('Hash')),
        text('hostname', T('Hostname')),
        FormItem(
          label: T('Platform'),
          child: CtSelect<String>(value: '${f['platform'] ?? ''}', options: abPlatforms, onChanged: (v) => set(() => f['platform'] = v ?? '')),
        ),
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
        final base = mine ? '/my/address_book' : '/address_book';
        try {
          await api.post(asInt(f['row_id']) > 0 ? '$base/update' : '$base/create', body: f);
          Toasts.success(T('OperationSuccess'));
          if (ctx.mounted) Navigator.of(ctx).pop(true);
        } catch (_) {}
      }),
    ],
  );
  return saved == true;
}

class AddressBookPage extends StatefulWidget {
  final bool mine;
  const AddressBookPage({super.key, required this.mine});

  @override
  State<AddressBookPage> createState() => _AddressBookPageState();
}

class _AddressBookPageState extends State<AddressBookPage> {
  late final ListCtl ctl;
  List<Row_> users = [];
  List<Row_> cols = [];

  String get base => widget.mine ? '/my/address_book' : '/address_book';

  @override
  void initState() {
    super.initState();
    final uid = Console.I.args['user_id'];
    ctl = ListCtl(
      (q) => api.get('$base/list', params: q),
      query: {'user_id': uid},
      decorate: (rows) async {
        final ids = rows.map((r) => r['id']).toList();
        if (ids.isEmpty) return;
        try {
          final d = await api.post('/peer/simpleData', body: {'ids': ids}, quiet: true);
          final peers = rowsOf(d);
          for (final r in rows) {
            for (final p in peers) {
              if (p['id'] == r['id']) r['peer'] = p;
            }
          }
        } catch (_) {}
      },
    )..load();
    if (!widget.mine) Lookups.users().then((u) => setState(() => users = u));
    if (widget.mine || uid != null) _loadCols(uid as int?);
  }

  Future<void> _loadCols(int? uid) async {
    final r = await Lookups.collections(mine: widget.mine, userId: uid);
    if (mounted) setState(() => cols = r);
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _del(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('Delete')}))) return;
    try {
      await api.post('$base/delete', body: {'row_id': r['row_id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  Future<void> _batchTags() async {
    final ids = ctl.selectedRows.map((r) => r['row_id']).toList();
    if (ids.isEmpty) {
      Toasts.warning(T('PleaseSelectData'));
      return;
    }
    final tags = await Lookups.tags(mine: true);
    if (!mounted) return;
    var chosen = <String>[];
    await showCtDialog(
      context,
      title: T('BatchEditTags'),
      width: 800,
      builder: (ctx, set) => FormItem(
        label: T('Tags'),
        child: CtMultiSelect<String>(
          values: chosen,
          options: [for (final t in tags) Opt('${t['name']}', '${t['name']}')],
          onChanged: (v) => set(() => chosen = v),
        ),
      ),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          if (chosen.isEmpty) {
            Toasts.warning(T('PleaseSelectData'));
            return;
          }
          try {
            await api.post('/my/address_book/batchUpdateTags', body: {'tags': chosen, 'row_ids': ids});
            Toasts.success(T('Success'));
            if (ctx.mounted) Navigator.of(ctx).pop();
            ctl.load();
          } catch (_) {}
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ListPage(
      ctl: ctl,
      selectable: widget.mine,
      filters: () => [
        if (!widget.mine)
          QueryField(
            T('Owner'),
            qSelect<int>(ctl, 'user_id', userOpts(users), filterable: true, onChanged: (v) {
              ctl.query['collection_id'] = null;
              setState(() => cols = []);
              if (v != null) _loadCols(v);
            }),
          ),
        QueryField(T('AddressBookName'), qSelect<int>(ctl, 'collection_id', collectionOpts(cols))),
        QueryField(T('Id'), qText(ctl, 'id')),
        QueryField(T('Username'), qText(ctl, 'username')),
        QueryField(T('Hostname'), qText(ctl, 'hostname')),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('Add'), tone: Tone.danger, onPressed: () async {
            if (await showAbForm(context, mine: widget.mine, users: users)) ctl.load();
          }),
          if (widget.mine) CtButton(T('BatchEditTags'), tone: Tone.primary, onPressed: _batchTags),
        ]),
      ],
      columns: () => [
        Col('ID',
            width: 200,
            cell: (r, _) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(platformIcon('${r['platform'] ?? ''}'), size: 16, color: c.text2),
                  const SizedBox(width: 4),
                  Flexible(child: Text('${r['id']}')),
                  CopyIcon('${r['id']}'),
                ])),
        if (!widget.mine)
          Col(T('Owner'),
              width: 200, cell: (r, _) => asInt(r['user_id']) > 0 ? CtTag(nameOf(users, r['user_id'], field: 'username')) : const SizedBox()),
        Col(T('AddressBookName'),
            width: 150,
            cell: (r, _) => Text(asInt(r['collection_id']) == 0
                ? T('MyAddressBook')
                : (widget.mine ? nameOf(cols, r['collection_id']) : '${(r['collection'] as Map?)?['name'] ?? ''}'))),
        Col(T('Username'), prop: 'username', width: 150),
        Col(T('Hostname'), prop: 'hostname', width: 150),
        Col(T('Tags'), prop: 'tags'),
        Col(T('Alias'), prop: 'alias', width: 150),
        Col(T('Version'), prop: 'peer.version', width: 100),
        Col(T('Hash'), prop: 'hash', width: 150, ellipsis: true),
        Col(T('Actions'),
            width: 260,
            cell: (r, _) => Actions_([
                  CtButton(T('Connect'), tone: Tone.success, size: BtnSize.table, onPressed: () => Console.I.host.connect('${r['id']}')),
                  CtButton(T('Edit'), size: BtnSize.table, onPressed: () async {
                    if (await showAbForm(context, mine: widget.mine, row: r, users: users)) ctl.load();
                  }),
                  CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                ])),
      ],
    );
  }
}

class CollectionPage extends StatefulWidget {
  final bool mine;
  const CollectionPage({super.key, required this.mine});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late final ListCtl ctl;
  List<Row_> users = [];

  String get base => widget.mine ? '/my/address_book_collection' : '/address_book_collection';

  @override
  void initState() {
    super.initState();
    ctl = ListCtl((q) => api.get('$base/list', params: q), query: {if (!widget.mine) 'is_my': 0})..load();
    if (!widget.mine) Lookups.users().then((u) => setState(() => users = u));
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _edit([Row_? row]) async {
    final f = <String, dynamic>{'id': row?['id'] ?? 0, 'name': row?['name'] ?? '', if (!widget.mine) 'user_id': row?['user_id']};
    await showCtDialog(
      context,
      title: row == null ? T('Create') : T('Update'),
      width: 800,
      builder: (ctx, set) => Column(children: [
        if (!widget.mine)
          FormItem(
            label: T('Owner'),
            required: true,
            child: CtSelect<int>(value: f['user_id'] as int?, filterable: true, options: userOpts(users), onChanged: (v) => set(() => f['user_id'] = v)),
          ),
        FormItem(label: T('Name'), required: true, child: CtInput(value: '${f['name']}', onChanged: (v) => f['name'] = v)),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          try {
            await api.post(asInt(f['id']) > 0 ? '$base/update' : '$base/create', body: f);
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
      await api.post('$base/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        // your own address book is always first
        final rows = widget.mine && ctl.page == 1 ? [<String, dynamic>{'id': 0, 'name': T('MyAddressBook')}, ...ctl.list] : ctl.list;
        return PageColumn([
          QueryBar(children: [
            if (!widget.mine) QueryField(T('Owner'), qSelect<int>(ctl, 'user_id', userOpts(users), filterable: true)),
            Buttons([
              CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
              CtButton(T('Add'), tone: Tone.danger, onPressed: () => _edit()),
            ]),
          ]),
          CtCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.mine) Padding(padding: const EdgeInsets.only(bottom: 10), child: CtTag(T('MyAddressBookTips'), tone: Tone.danger)),
              CtTable(loading: ctl.loading, rows: rows, columns: [
                if (!widget.mine) const Col('ID', prop: 'id'),
                if (!widget.mine)
                  Col(T('Owner'), cell: (r, _) => asInt(r['user_id']) > 0 ? CtTag(nameOf(users, r['user_id'], field: 'username')) : const SizedBox()),
                Col(widget.mine ? T('Name') : T('AddressBook'), prop: 'name'),
                Col(T('CreatedAt'), prop: 'created_at'),
                Col(T('Actions'),
                    width: 330,
                    cell: (r, _) => asInt(r['id']) == 0
                        ? const SizedBox()
                        : Actions_([
                            CtButton(T('ShareRules'), tone: Tone.primary, size: BtnSize.table, onPressed: () => showRules(context, r, mine: widget.mine)),
                            CtButton(T('Edit'), size: BtnSize.table, onPressed: () => _edit(r)),
                            CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                          ])),
              ]),
            ]),
          ),
          CtPagination(total: ctl.total, page: ctl.page, pageSize: ctl.pageSize, onChange: ctl.setPage),
        ]);
      },
    );
  }
}

/// Who an address book is shared with.
Future<void> showRules(BuildContext context, Row_ collection, {required bool mine}) async {
  final base = mine ? '/my/address_book_collection_rule' : '/address_book_collection_rule';
  const typeUser = 1, typeGroup = 2;
  final rules = [Opt(1, T('Read')), Opt(2, T('ReadWrite')), Opt(3, T('FullControl'))];
  final types = [Opt(typeGroup, T('Group')), Opt(typeUser, T('User'))];
  final ctl = ListCtl((q) => api.get('$base/list', params: q), query: {'collection_id': collection['id']})..load();
  var groups = <Row_>[], users = <Row_>[];
  try {
    final d = await api.post('/user/groupUsers', quiet: true);
    groups = rowsOf(d['groups']);
    users = rowsOf(d['users']);
  } catch (_) {}
  if (!context.mounted) return;

  Future<void> edit([Row_? row]) async {
    final f = <String, dynamic>{
      'id': row?['id'] ?? 0,
      'collection_id': collection['id'],
      'user_id': collection['user_id'],
      'type': row?['type'] ?? typeUser,
      'rule': row?['rule'] ?? 1,
      'g_id': null,
      'u_id': null,
    };
    if (row != null) {
      if (row['type'] == typeUser) {
        f['u_id'] = row['to_id'];
        f['g_id'] = users.where((u) => u['id'] == row['to_id']).map((u) => u['group_id']).firstOrNull;
      } else {
        f['g_id'] = row['to_id'];
      }
    }
    await showCtDialog(
      context,
      title: row == null ? T('Create') : T('Update'),
      width: 800,
      dismissible: false,
      builder: (ctx, set) => Column(children: [
        FormItem(label: T('AddressBookName'), child: Padding(padding: const EdgeInsets.only(top: 7), child: Text('${collection['name']}'))),
        FormItem(label: T('Rule'), required: true, child: CtRadios<int>(value: f['rule'] as int, options: [for (final o in rules) (o.value, o.label)], onChanged: (v) => set(() => f['rule'] = v))),
        FormItem(label: T('Type'), required: true, child: CtRadios<int>(value: f['type'] as int, options: [for (final o in types) (o.value, o.label)], onChanged: (v) => set(() => f['type'] = v))),
        FormItem(
          label: T('ShareTo'),
          required: true,
          child: Wrap(spacing: 20, runSpacing: 8, children: [
            SizedBox(
              width: 220,
              child: CtSelect<int>(
                value: f['g_id'] as int?,
                options: [for (final g in groups) Opt(asInt(g['id']), '${g['name']}')],
                onChanged: (v) => set(() {
                  f['g_id'] = v;
                  f['u_id'] = null;
                }),
              ),
            ),
            if (f['type'] == typeUser)
              SizedBox(
                width: 220,
                child: CtSelect<int>(
                  value: f['u_id'] as int?,
                  filterable: true,
                  options: [for (final u in users.where((u) => u['group_id'] == f['g_id'])) Opt(asInt(u['id']), '${u['username']}')],
                  onChanged: (v) => set(() => f['u_id'] = v),
                ),
              ),
          ]),
        ),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          final body = {...f, 'to_id': f['type'] == typeGroup ? f['g_id'] : f['u_id']};
          try {
            await api.post(asInt(f['id']) > 0 ? '$base/update' : '$base/create', body: body);
            Toasts.success(T('OperationSuccess'));
            if (ctx.mounted) Navigator.of(ctx).pop();
            ctl.load();
          } catch (_) {}
        }),
      ],
    );
  }

  Future<void> del(BuildContext ctx, Row_ r) async {
    if (!await confirm(ctx, T('Confirm?', {'param': T('Delete')}))) return;
    try {
      await api.post('$base/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  await showCtDialog(
    context,
    title: T('ShareRules'),
    width: 1000,
    builder: (ctx, set) => ListenableBuilder(
      listenable: ctl,
      builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('Add'), tone: Tone.danger, onPressed: () => edit()),
        ]),
        const SizedBox(height: 14),
        CtTable(loading: ctl.loading, rows: ctl.list, columns: [
          Col(T('Rule'), cell: (r, _) => Text(rules.where((o) => o.value == r['rule']).map((o) => o.label).firstOrNull ?? '')),
          Col(T('Type'), cell: (r, _) => Text(types.where((o) => o.value == r['type']).map((o) => o.label).firstOrNull ?? '')),
          Col(T('ShareTo'),
              cell: (r, _) => Text(r['type'] == typeUser ? nameOf(users, r['to_id'], field: 'username') : nameOf(groups, r['to_id']))),
          Col(T('CreatedAt'), prop: 'created_at'),
          Col(T('Actions'),
              width: 200,
              cell: (r, _) => Actions_([
                    CtButton(T('Edit'), size: BtnSize.table, onPressed: () => edit(r)),
                    CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => del(ctx, r)),
                  ])),
        ]),
        const SizedBox(height: 12),
        CtPagination(total: ctl.total, page: ctl.page, pageSize: ctl.pageSize, onChange: ctl.setPage),
      ]),
    ),
  );
  ctl.dispose();
}

/// Tags are stored by the RustDesk client as ARGB integers.
Color tagColor(dynamic v) => Color(asInt(v) & 0xFFFFFFFF);

class TagPage extends StatefulWidget {
  final bool mine;
  const TagPage({super.key, required this.mine});

  @override
  State<TagPage> createState() => _TagPageState();
}

class _TagPageState extends State<TagPage> {
  late final ListCtl ctl;
  List<Row_> users = [];
  List<Row_> cols = [];

  String get base => widget.mine ? '/my/tag' : '/tag';

  @override
  void initState() {
    super.initState();
    final uid = Console.I.args['user_id'];
    ctl = ListCtl((q) => api.get('$base/list', params: q), query: {'user_id': uid})..load();
    if (!widget.mine) Lookups.users().then((u) => setState(() => users = u));
    if (widget.mine || uid != null) _loadCols(uid as int?);
  }

  Future<void> _loadCols(int? uid) async {
    final r = await Lookups.collections(mine: widget.mine, userId: uid);
    if (mounted) setState(() => cols = r);
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _edit([Row_? row]) async {
    final f = <String, dynamic>{
      'id': row?['id'] ?? 0,
      'name': row?['name'] ?? '',
      'color': row == null ? null : asInt(row['color']),
      'user_id': row?['user_id'],
      'collection_id': row?['collection_id'],
    };
    var formCols = widget.mine ? cols : <Row_>[];
    if (!widget.mine && f['user_id'] != null) formCols = await Lookups.collections(mine: false, userId: f['user_id'] as int);
    if (!mounted) return;
    await showCtDialog(
      context,
      title: row == null ? T('Create') : T('Update'),
      width: 800,
      builder: (ctx, set) => Column(children: [
        if (!widget.mine)
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
                  formCols = [];
                });
                if (v != null) {
                  final r = await Lookups.collections(mine: false, userId: v);
                  set(() => formCols = r);
                }
              },
            ),
          ),
        FormItem(
          label: T('AddressBookName'),
          required: !widget.mine,
          child: CtSelect<int>(value: f['collection_id'] as int?, clearable: true, options: collectionOpts(formCols), onChanged: (v) => set(() => f['collection_id'] = v)),
        ),
        FormItem(label: T('Name'), required: true, child: CtInput(value: '${f['name']}', onChanged: (v) => f['name'] = v)),
        FormItem(label: T('Color'), required: true, child: _ColorPicker(value: f['color'] as int?, onChanged: (v) => set(() => f['color'] = v))),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          if (f['color'] == null) {
            Toasts.error('Please choose a colour');
            return;
          }
          try {
            await api.post(asInt(f['id']) > 0 ? '$base/update' : '$base/create', body: f);
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
      await api.post('$base/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ListPage(
      ctl: ctl,
      filters: () => [
        if (!widget.mine)
          QueryField(
            T('Owner'),
            qSelect<int>(ctl, 'user_id', userOpts(users), filterable: true, onChanged: (v) {
              ctl.query['collection_id'] = null;
              setState(() => cols = []);
              if (v != null) _loadCols(v);
            }),
          ),
        QueryField(T('AddressBookName'), qSelect<int>(ctl, 'collection_id', collectionOpts(cols))),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('Add'), tone: Tone.danger, onPressed: () => _edit()),
        ]),
      ],
      columns: () => [
        const Col('ID', prop: 'id'),
        if (!widget.mine)
          Col(T('Owner'), cell: (r, _) => asInt(r['user_id']) > 0 ? CtTag(nameOf(users, r['user_id'], field: 'username')) : const SizedBox()),
        Col(widget.mine ? T('AddressBook') : T('AddressBookName'),
            width: 150,
            cell: (r, _) => Text(asInt(r['collection_id']) == 0
                ? T('MyAddressBook')
                : (widget.mine ? nameOf(cols, r['collection_id']) : '${(r['collection'] as Map?)?['name'] ?? ''}'))),
        Col(T('Name'), prop: 'name'),
        Col(T('Color'),
            cell: (r, _) => Container(
                  width: 50,
                  height: 30,
                  color: c.surfaceHover,
                  alignment: Alignment.center,
                  child: Dot(tagColor(r['color']), size: 10),
                )),
        Col(T('CreatedAt'), prop: 'created_at'),
        if (!widget.mine) Col(T('UpdatedAt'), prop: 'updated_at'),
        Col(T('Actions'),
            width: 200,
            cell: (r, _) => Actions_([
                  CtButton(T('Edit'), size: BtnSize.table, onPressed: () => _edit(r)),
                  CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                ])),
      ],
    );
  }
}

/// A palette plus hex entry, in place of the web's colour picker.
class _ColorPicker extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;
  const _ColorPicker({required this.value, required this.onChanged});

  static const palette = [
    0xFFEF4444, 0xFFF97316, 0xFFF59E0B, 0xFFEAB308, 0xFF84CC16, 0xFF22C55E, 0xFF10B981, 0xFF14B8A6,
    0xFF06B6D4, 0xFF0EA5E9, 0xFF3B82F6, 0xFF6366F1, 0xFF8B5CF6, 0xFFA855F7, 0xFFD946EF, 0xFFEC4899,
    0xFF64748B, 0xFF78716C,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final hex = value == null ? '' : value!.toRadixString(16).padLeft(8, '0').toUpperCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in palette)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Color(p),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: value == p ? c.text : Colors.transparent, width: 2),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(
          width: 140,
          child: CtInput(
            value: hex,
            placeholder: 'AARRGGBB',
            onSubmitted: (v) {
              final n = int.tryParse(v.replaceAll('#', ''), radix: 16);
              if (n != null) onChanged(v.replaceAll('#', '').length <= 6 ? 0xFF000000 | n : n);
            },
          ),
        ),
        const SizedBox(width: 10),
        Container(width: 50, height: 30, color: c.surfaceHover, alignment: Alignment.center, child: value == null ? null : Dot(Color(value!), size: 10)),
      ]),
    ]);
  }
}
