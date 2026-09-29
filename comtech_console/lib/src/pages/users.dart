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

const enableStatus = 1, disableStatus = 2;

String permLabel(String p) => T('Perm_${p.replaceFirst('.', '_')}');

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  final ctl = ListCtl((q) => api.get('/user/list', params: q), query: {'username': ''})..load();
  List<Row_> groups = [];

  @override
  void initState() {
    super.initState();
    Lookups.userGroups().then((g) => setState(() => groups = g));
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    try {
      final d = await api.get('/user/list', params: {...ctl.query, 'page': 1, 'page_size': 1000000});
      await exportCsv('users.csv', rowsOf(d));
    } catch (_) {}
  }

  Future<void> _status(Row_ r, bool on) async {
    r['status'] = on ? enableStatus : disableStatus;
    ctl.touch();
    try {
      await api.post('/user/update', body: r);
      Toasts.success(T('OperationSuccess'));
    } catch (_) {}
    ctl.load();
  }

  Future<void> _resetPassword(Row_ r) async {
    final pw = await prompt(context, T('PleaseInputNewPassword'), title: T('ResetPassword'), password: true);
    if (pw == null || !mounted) return;
    if (!await confirm(context, T('Confirm?', {'param': T('ResetPassword')}), warning: false)) return;
    try {
      await api.post('/user/changePwd', body: {'id': r['id'], 'password': pw});
      Toasts.success(T('OperationSuccess'));
    } catch (_) {}
  }

  Future<void> _resetMfa(Row_ r) async {
    if (!await confirm(context, T('ResetTwoFactorConfirm', {'name': r['username']}), confirmText: T('ResetTwoFactor'))) return;
    try {
      await api.post('/user/mfa/reset', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  Future<void> _del(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('Delete')}))) return;
    try {
      await api.post('/user/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final con = Console.I;
    return ListPage(
      ctl: ctl,
      filters: () => [
        QueryField(T('Username'), CtInput(value: '${ctl.query['username']}', onChanged: (v) => ctl.query['username'] = v, onSubmitted: (_) => ctl.filter())),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('Add'), tone: Tone.danger, onPressed: () => con.go('UserAdd')),
          CtButton(T('Export'), tone: Tone.success, onPressed: _export),
        ]),
      ],
      columns: () => [
        const Col('ID', prop: 'id'),
        Col(T('Username'), prop: 'username'),
        Col(T('Email'), prop: 'email'),
        Col(T('Nickname'), prop: 'nickname'),
        Col(T('Group'), cell: (r, _) => asInt(r['group_id']) > 0 ? CtTag(nameOf(groups, r['group_id'])) : const Text('-')),
        Col(T('AccountEnabled'),
            cell: (r, _) => CtSwitch(
                  value: r['status'] == enableStatus,
                  activeText: T('Enabled'),
                  inactiveText: T('Disabled'),
                  offColor: c.danger,
                  onChanged: (v) => _status(r, v),
                )),
        Col(T('TwoFactorShort'), width: 90, cell: (r, _) => r['totp_enabled'] == true ? CtTag(T('On'), tone: Tone.success) : Text('-', style: TextStyle(color: c.muted))),
        Col(T('Remark'), prop: 'remark'),
        Col(T('CreatedAt'), prop: 'created_at'),
        Col(T('UpdatedAt'), prop: 'updated_at'),
        Col(T('Actions'),
            width: 300,
            cell: (r, _) => Actions_([
                  CtButton(T('Edit'), size: BtnSize.table, onPressed: () => con.go('UserEdit', {'id': r['id']})),
                  CtButton(T('ResetPassword'), tone: Tone.warning, size: BtnSize.table, onPressed: () => _resetPassword(r)),
                  CtMenuButton(
                    button: CtButton(T('More'), size: BtnSize.table, trailingIcon: Icons.keyboard_arrow_down, onPressed: () {}),
                    actions: [
                      MenuAction(T('UserTags'), () => con.go('UserTag', {'user_id': r['id']})),
                      MenuAction(T('UserAddressBook'), () => con.go('UserAddressBook', {'user_id': r['id']})),
                      if (r['totp_enabled'] == true) MenuAction(T('ResetTwoFactor'), () => _resetMfa(r)),
                      MenuAction(T('Delete'), () => _del(r), divided: true),
                    ],
                  ),
                ])),
      ],
    );
  }
}

class UserEditPage extends StatefulWidget {
  const UserEditPage({super.key});

  @override
  State<UserEditPage> createState() => _UserEditPageState();
}

class _UserEditPageState extends State<UserEditPage> {
  final id = asInt(Console.I.args['id']);
  Map<String, dynamic> form = {'status': enableStatus};
  List<Row_> groups = [];
  String? error;

  @override
  void initState() {
    super.initState();
    Lookups.userGroups().then((g) => setState(() => groups = g));
    if (id > 0) {
      api.get('/user/detail/$id').then((d) {
        if (mounted) setState(() => form = Map<String, dynamic>.from(d as Map));
      }).catchError((_) {});
    }
  }

  Future<void> _submit() async {
    String? e;
    if ('${form['username'] ?? ''}'.isEmpty) {
      e = T('ParamRequired', {'param': T('Username')});
    } else if (form['group_id'] == null) {
      e = T('ParamRequired', {'param': T('Group')});
    } else if (form['status'] == null) {
      e = T('ParamRequired', {'param': T('Status')});
    }
    setState(() => error = e);
    if (e != null) return;
    try {
      await api.post(id > 0 ? '/user/update' : '/user/create', body: form);
      Toasts.success(T('OperationSuccess'));
      Console.I.go('UserList');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    Widget text(String key, String label, {bool required = false, String? help}) => FormItem(
          label: label,
          required: required,
          help: help,
          child: CtInput(key: ValueKey('$key${form['id']}'), value: '${form[key] ?? ''}', onChanged: (v) => form[key] = v),
        );
    return CtCard(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(children: [
            text('username', T('Username'), required: true),
            text('email', T('Email'), help: T('EmailMailboxHelp')),
            text('nickname', T('Nickname')),
            FormItem(
              label: T('Group'),
              required: true,
              child: CtSelect<int>(
                value: form['group_id'] as int?,
                options: [for (final g in groups) Opt(asInt(g['id']), '${g['name']}')],
                onChanged: (v) => setState(() => form['group_id'] = v),
              ),
            ),
            // admin access now comes from the group's role; only offer to clear the old flag
            if (form['is_admin'] == true || form['_was_admin'] == true)
              FormItem(
                label: T('LegacyAdmin'),
                help: T('LegacyAdminHelp'),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CtSwitch(
                    value: form['is_admin'] == true,
                    onChanged: (v) => setState(() {
                      form['_was_admin'] = true;
                      form['is_admin'] = v;
                    }),
                  ),
                ),
              ),
            FormItem(
              label: T('AccountEnabled'),
              required: true,
              help: T('AccountEnabledHelp'),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CtSwitch(
                  value: form['status'] == enableStatus,
                  activeText: T('Enabled'),
                  inactiveText: T('Disabled'),
                  offColor: c.danger,
                  onChanged: (v) => setState(() => form['status'] = v ? enableStatus : disableStatus),
                ),
              ),
            ),
            text('remark', T('Remark')),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: CtAlert(error!, type: AlertType.error)),
            FormItem(
              child: Buttons([
                CtButton(T('Cancel'), onPressed: () => Console.I.go('UserList')),
                CtButton(T('Submit'), tone: Tone.primary, onPressed: _submit),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class UserGroupPage extends StatefulWidget {
  const UserGroupPage({super.key});

  @override
  State<UserGroupPage> createState() => _UserGroupPageState();
}

class _UserGroupPageState extends State<UserGroupPage> {
  final ctl = ListCtl((q) => api.get('/group/list', params: q))..load();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _edit([Row_? row]) async {
    final f = <String, dynamic>{'id': row?['id'] ?? 0, 'name': row?['name'] ?? '', 'type': row?['type'] ?? 1};
    await showCtDialog(
      context,
      title: asInt(f['id']) == 0 ? T('Create') : T('Update'),
      width: 800,
      builder: (ctx, set) => FormItem(label: T('Name'), required: true, child: CtInput(value: '${f['name']}', onChanged: (v) => f['name'] = v)),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          try {
            await api.post(asInt(f['id']) > 0 ? '/group/update' : '/group/create', body: f);
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
      await api.post('/group/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListPage(
      ctl: ctl,
      filters: () => [
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('Add'), tone: Tone.danger, onPressed: () => _edit()),
        ]),
      ],
      columns: () => [
        const Col('ID', prop: 'id'),
        Col(T('Name'), prop: 'name'),
        Col(T('CreatedAt'), prop: 'created_at'),
        Col(T('UpdatedAt'), prop: 'updated_at'),
        Col(T('Actions'),
            minWidth: 320,
            cell: (r, _) => Actions_([
                  CtButton(T('RolePermissions'), tone: Tone.primary, size: BtnSize.table, onPressed: () => showRole(context, r)),
                  CtButton(T('Edit'), size: BtnSize.table, onPressed: () => _edit(r)),
                  CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                ])),
      ],
    );
  }
}

/// What a user group's members may do, and which customers they see.
Future<void> showRole(BuildContext context, Row_ group) async {
  var keys = <String>[];
  var deviceGroups = <Row_>[];
  var form = <String, dynamic>{'permissions': <String>[], 'scoped': false, 'device_group_ids': <int>[]};
  var loading = true;
  var saving = false;
  var started = false;
  await showCtDialog(
    context,
    title: T('RoleFor', {'param': group['name'] ?? ''}),
    width: 720,
    builder: (ctx, set) {
      final c = ctx.ct;
      if (!started) {
        started = true;
        Future.wait([
          api.get('/group_role/permissions').then<dynamic>((v) => v).catchError((_) => null),
          api.get('/group_role/detail/${group['id']}').then<dynamic>((v) => v).catchError((_) => null),
          Lookups.deviceGroups(),
        ]).then((r) => set(() {
              if (r[0] is List) keys = (r[0] as List).map((e) => '$e').toList();
              if (r[1] is Map) {
                final d = Map<String, dynamic>.from(r[1] as Map);
                form = {
                  'permissions': List<String>.from(d['permissions'] ?? const []),
                  'scoped': d['scoped'] == true,
                  'device_group_ids': [for (final i in (d['device_group_ids'] as List? ?? const [])) asInt(i)],
                };
              }
              deviceGroups = r[2] as List<Row_>;
              loading = false;
            }));
      }
      final perms = form['permissions'] as List<String>;
      final full = perms.contains('admin');
      void toggle(String p, bool on) {
        final s = {...perms};
        on ? s.add(p) : s.remove(p);
        if (on && p == 'peers.manage') s.add('peers.view');
        if (!on && p == 'peers.view') s.remove('peers.manage');
        set(() => form['permissions'] = s.toList());
      }

      return Loading(
        loading: loading,
        minHeight: 160,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Muted(T('RoleHint'), padding: const EdgeInsets.only(bottom: 12)),
          for (final p in keys)
            Builder(builder: (_) {
              final on = perms.contains(p) || (p != 'admin' && full);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: on ? c.primarySoft : Colors.transparent,
                  border: Border.all(color: p == 'admin' ? c.tint(c.warning, 0.5) : c.border),
                  borderRadius: BorderRadius.circular(ctRadiusSm),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CtCheckbox(value: on, onChanged: p != 'admin' && full ? null : (v) => toggle(p, v)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(permLabel(p), style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                      Text(T('PermDesc_${p.replaceFirst('.', '_')}'), style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                  ),
                ]),
              );
            }),
          if (!full) ...[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CtSwitch(value: form['scoped'] == true, onChanged: (v) => set(() => form['scoped'] = v)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(T('LimitToDeviceGroups'), style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                  Text(T('LimitToDeviceGroupsHelp'), style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
            ]),
            if (form['scoped'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: CtMultiSelect<int>(
                  values: form['device_group_ids'] as List<int>,
                  placeholder: T('ChooseDeviceGroups'),
                  options: [for (final g in deviceGroups) Opt(asInt(g['id']), '${g['name']}')],
                  onChanged: (v) => set(() => form['device_group_ids'] = v),
                ),
              ),
          ],
        ]),
      );
    },
    footer: (ctx, set) => [
      CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
      CtButton(T('Save'), tone: Tone.primary, loading: saving, onPressed: () async {
        set(() => saving = true);
        try {
          await api.post('/group_role/save', body: {...form, 'group_id': group['id']});
          Toasts.success(T('OperationSuccess'));
          if (ctx.mounted) Navigator.of(ctx).pop();
        } catch (_) {
          set(() => saving = false);
        }
      }),
    ],
  );
}

class ApiKeysPage extends StatefulWidget {
  const ApiKeysPage({super.key});

  @override
  State<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends State<ApiKeysPage> {
  final ctl = ListCtl((q) => api.get('/api_key/list', params: q));
  List<Row_> users = [];
  List<String> permKeys = [];

  @override
  void initState() {
    super.initState();
    Future.wait([
      Lookups.users(),
      api.get('/group_role/permissions', quiet: true).then<dynamic>((v) => v).catchError((_) => null),
    ]).then((r) {
      if (!mounted) return;
      setState(() {
        users = r[0] as List<Row_>;
        if (r[1] is List) permKeys = (r[1] as List).map((e) => '$e').toList();
      });
      ctl.load();
    });
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _edit([Row_? row]) async {
    final perms = row == null || '${row['permissions'] ?? ''}'.isEmpty ? <String>[] : '${row['permissions']}'.split(',');
    final f = <String, dynamic>{
      'id': row?['id'] ?? 0,
      'name': row?['name'] ?? '',
      'user_id': row?['user_id'],
      'expires_days': row == null ? 0 : -1,
      'limited': perms.isNotEmpty,
      'permissions': perms,
      'act_as': row?['act_as'] == true,
    };
    var created = '';
    var submitting = false;
    await showCtDialog(
      context,
      title: asInt(f['id']) > 0 ? T('EditApiKey') : T('NewApiKey'),
      width: 680,
      builder: (ctx, set) {
        final c = ctx.ct;
        if (created.isNotEmpty) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CtAlert(T('CopyKeyNow'), type: AlertType.warning),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: CodeBox(created)),
              const SizedBox(width: 10),
              CtButton(T('Copy'), tone: Tone.primary, onPressed: () => copyText(created)),
            ]),
            Muted(T('KeyUsage'), size: 12, padding: const EdgeInsets.only(top: 12, bottom: 8)),
            CodeBox('Authorization: Bearer $created', block: true),
          ]);
        }
        final chosen = f['permissions'] as List<String>;
        return Column(children: [
          FormItem(label: T('Name'), labelWidth: 150, required: true, child: CtInput(value: '${f['name']}', placeholder: 'Comtech IT POS', onChanged: (v) => f['name'] = v)),
          FormItem(
            label: T('ActsAs'),
            labelWidth: 150,
            required: true,
            help: T('ActsAsHelp'),
            child: CtSelect<int>(
              value: f['user_id'] as int?,
              filterable: true,
              options: [for (final u in users) Opt(asInt(u['id']), '${u['username']}')],
              onChanged: (v) => set(() => f['user_id'] = v),
            ),
          ),
          FormItem(
            label: T('Permissions'),
            labelWidth: 150,
            help: T('KeyPermissionsHelp'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: CtRadios<bool>(
                  value: f['limited'] == true,
                  options: [(false, T('KeyAllOfRole')), (true, T('KeyOnlyThese'))],
                  onChanged: (v) => set(() => f['limited'] = v),
                ),
              ),
              if (f['limited'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(spacing: 16, runSpacing: 8, children: [
                    for (final p in permKeys)
                      SizedBox(
                        width: 200,
                        child: CtCheckbox(
                          value: chosen.contains(p),
                          label: Text(permLabel(p), style: TextStyle(color: c.text2)),
                          onChanged: (v) => set(() => f['permissions'] = v ? [...chosen, p] : chosen.where((x) => x != p).toList()),
                        ),
                      ),
                  ]),
                ),
            ]),
          ),
          FormItem(
            label: T('KeyActAs'),
            labelWidth: 150,
            help: T('KeyActAsHelp'),
            child: Align(alignment: Alignment.centerLeft, child: CtSwitch(value: f['act_as'] == true, onChanged: (v) => set(() => f['act_as'] = v))),
          ),
          FormItem(
            label: T('Expires'),
            labelWidth: 150,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CtSelect<int>(
                width: 200,
                value: f['expires_days'] as int,
                options: [
                  if (asInt(f['id']) > 0) Opt(-1, T('KeepCurrentExpiry')),
                  Opt(0, T('Never')),
                  Opt(30, T('Days', {'param': 30})),
                  Opt(90, T('Days', {'param': 90})),
                  Opt(365, T('Days', {'param': 365})),
                ],
                onChanged: (v) => set(() => f['expires_days'] = v ?? 0),
              ),
            ),
          ),
        ]);
      },
      footer: (ctx, set) => created.isNotEmpty
          ? [CtButton(T('Done'), tone: Tone.primary, onPressed: () => Navigator.of(ctx).pop())]
          : [
              CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
              CtButton(asInt(f['id']) > 0 ? T('Save') : T('Create'), tone: Tone.primary, loading: submitting, onPressed: () async {
                if ('${f['name']}'.isEmpty || f['user_id'] == null) {
                  return Toasts.error(T('ParamRequired', {'param': '${f['name']}'.isEmpty ? T('Name') : T('ActsAs')}));
                }
                if (f['limited'] == true && (f['permissions'] as List).isEmpty) return Toasts.error(T('KeyPickPermission'));
                set(() => submitting = true);
                final data = {
                  'id': f['id'],
                  'name': f['name'],
                  'user_id': f['user_id'],
                  'expires_days': f['expires_days'],
                  'permissions': f['limited'] == true ? f['permissions'] : <String>[],
                  'act_as': f['act_as'],
                };
                try {
                  final d = await api.post(asInt(f['id']) > 0 ? '/api_key/update' : '/api_key/create', body: data);
                  ctl.load();
                  if (asInt(f['id']) > 0) {
                    Toasts.success(T('OperationSuccess'));
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } else {
                    set(() {
                      created = '${d['key']}';
                      submitting = false;
                    });
                  }
                } catch (_) {
                  set(() => submitting = false);
                }
              }),
            ],
    );
  }

  Future<void> _revoke(Row_ r) async {
    if (!await confirm(context, T('RevokeKeyConfirm', {'param': r['name']}), confirmText: T('Revoke'))) return;
    try {
      await api.post('/api_key/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ListPage(
      ctl: ctl,
      sizes: const [10, 20, 50],
      queryAbove: Padding(padding: const EdgeInsets.only(bottom: 12), child: CtAlert(T('ApiKeysHelp'))),
      filters: () => [
        Buttons([
          CtButton(T('NewApiKey'), tone: Tone.primary, onPressed: () => _edit()),
          CtButton(T('Refresh'), onPressed: ctl.load),
        ]),
      ],
      middle: const [CtCard(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: ApiKeyGuide())],
      columns: () => [
        Col(T('Name'), prop: 'name', minWidth: 140, center: false),
        Col(T('Key'), minWidth: 150, center: false, cell: (r, _) => CodeBox('${r['prefix']}…')),
        Col(T('ActsAs'), minWidth: 140, center: false, cell: (r, _) => Text(nameOf(users, r['user_id'], field: 'username', fallback: '#${r['user_id']}'))),
        Col(T('Permissions'),
            minWidth: 240,
            center: false,
            cell: (r, _) => Wrap(spacing: 4, runSpacing: 4, children: [
                  if (r['act_as'] == true) CtTag(T('KeyActsAsUsers'), small: true, tone: Tone.warning),
                  if ('${r['permissions'] ?? ''}'.isEmpty)
                    Text(T('KeyAllOfRole'), style: TextStyle(fontSize: 12, color: c.muted))
                  else
                    for (final p in '${r['permissions']}'.split(',')) CtTag(permLabel(p), small: true),
                ])),
        Col(T('LastUsed'),
            minWidth: 190,
            center: false,
            cell: (r, _) => asInt(r['last_used_at']) > 0
                ? Text.rich(TextSpan(children: [
                    TextSpan(text: formatTime(asInt(r['last_used_at']))),
                    TextSpan(text: '  ${r['last_used_ip'] ?? ''}', style: TextStyle(fontSize: 12, color: c.muted)),
                  ]))
                : Text(T('Never'), style: TextStyle(fontSize: 12, color: c.muted))),
        Col(T('Expires'),
            minWidth: 150,
            center: false,
            cell: (r, _) {
              final e = asInt(r['expires_at']);
              if (e > 0 && e * 1000 < DateTime.now().millisecondsSinceEpoch) return CtTag(T('KeyExpired'), tone: Tone.danger);
              return Text(e > 0 ? formatTime(e) : T('Never'));
            }),
        Col(T('CreatedAt'), prop: 'created_at', minWidth: 150, center: false),
        Col(T('Actions'),
            width: 190,
            cell: (r, _) => Actions_([
                  CtButton(T('Edit'), size: BtnSize.table, onPressed: () => _edit(r)),
                  CtButton(T('Revoke'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _revoke(r)),
                ])),
      ],
    );
  }
}

/// How to use API keys, with the endpoint table and examples.
class ApiKeyGuide extends StatefulWidget {
  const ApiKeyGuide({super.key});

  @override
  State<ApiKeyGuide> createState() => _ApiKeyGuideState();
}

class _ApiKeyGuideState extends State<ApiKeyGuide> {
  String tab = 'ps';

  static const endpoints = [
    ('View devices', [
      ('GET', '/peer/list', 'devices; filter with id, hostname, username, ip, time_ago (e.g. -300 = online in the last 5 min)'),
      ('GET', '/peer/detail/{row_id}', 'one device'),
      ('GET', '/device_group/list', 'device groups (any key can read these)'),
    ]),
    ('Manage devices', [
      ('POST', '/peer/update', 'change a device: group_id, alias, note, strategy_id'),
      ('POST', '/peer/delete', '{"row_id": 12}'),
      ('GET', '/device_approval/list', 'devices waiting for approval (status=0)'),
      ('POST', '/device_approval/decide', '{"id", "approve", "device_group_id"}'),
      ('POST', '/audit_conn/disconnect', 'end a live session: {"id": connection log id}'),
    ]),
    ('Device groups', [
      ('POST', '/device_group/create', '{"name": "Acme", "strategy_id": 0}'),
      ('POST', '/device_group/update', '{"id", "name", "strategy_id"}'),
      ('POST', '/device_group/delete', '{"id": 4}'),
    ]),
    ('Support sessions', [
      ('GET', '/support_session/list', 'sessions and their status (waiting, ready, closed)'),
      ('POST', '/support_session/create', 'customer_name, customer_email, device_group_id, build_id (0 = support apps), send_email, expires_hours'),
      ('POST', '/support_session/close', '{"id": 9}'),
    ]),
    ('Client builder', [
      ('GET', '/client_build/list', 'builds: app_name, platform, status, downloads [{name, url}]'),
      ('GET', '/client_build/detail/{id}', 'one build'),
      ('POST', '/client_build/email', 'email a build\'s download links'),
    ]),
    ('Logs', [
      ('GET', '/audit_conn/list', 'connection log; filter peer_id, from_peer'),
      ('GET', '/audit_file/list', 'file transfers'),
      ('GET', '/audit_alarm/list', 'security alerts from devices'),
      ('GET', '/login_log/list', 'sign-ins'),
      ('GET', '/admin_log/list', 'admin activity'),
    ]),
    ('Client policies', [
      ('GET', '/strategy/list', 'policies (also readable with Manage devices or Device groups)'),
    ]),
    ('Users', [
      ('GET', '/user/list', 'users'),
      ('POST', '/user/create', 'add a user; also /user/update, /user/delete, /user/changePwd, /user/mfa/reset'),
      ('GET', '/group/list', 'user groups (roles)'),
      ('POST', '/group/create', '{"name": "Technicians"}; also /group/update, /group/delete'),
      ('GET', '/group_role/detail/{group_id}', 'a group\'s permissions and customer limits'),
      ('POST', '/group_role/save', '{"group_id", "permissions": [...], "scoped", "device_group_ids": [...]}'),
      ('POST', '/api_key/create', 'make keys (a key can\'t create more than its user has)'),
    ]),
  ];

  Future<String> _reference() async {
    final origin = Console.I.host.apiServer;
    final text = await api.fetchText('/_admin/api-reference.md');
    return text.replaceAll('https://rd.comtechit.au', origin);
  }

  Future<void> _openRef() async {
    String? text;
    await showCtDialog(
      context,
      title: 'API reference',
      width: 960,
      builder: (ctx, set) {
        if (text == null) {
          _reference().then((t) => set(() => text = t)).catchError((_) => set(() => text = 'Could not load the reference.'));
          text = '';
        }
        return text!.isEmpty ? const Loading(loading: true, minHeight: 200, child: SizedBox(height: 200)) : MarkdownView(text!);
      },
    );
  }

  Future<void> _download() async {
    try {
      await saveBytes('rustdesk-api-reference.md', utf8.encode(await _reference()));
    } catch (_) {
      Toasts.error('Could not load the reference.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final base = '${Console.I.host.apiServer}/api/admin';
    final origin = Console.I.host.apiServer;
    TextStyle h4() => TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text);
    Widget p(String s) => Padding(padding: const EdgeInsets.only(bottom: 10), child: MarkdownView(s));
    final examples = {
      'ps': '''\$headers = @{ Authorization = "Bearer rdk_your_key" }
\$base = "$base"
# find a device by ID
\$r = Invoke-RestMethod "\$base/peer/list?page=1&page_size=20&id=123456789" -Headers \$headers
\$r.data.list | Select-Object id, hostname, group_id, last_online_time
# start a support session and email the customer
\$body = @{ customer_name = "Jane Smith"; customer_email = "jane@example.com"; device_group_id = 2; build_id = 0; send_email = \$true } | ConvertTo-Json
\$s = Invoke-RestMethod "\$base/support_session/create" -Method Post -Headers \$headers -Body \$body -ContentType "application/json"
if (\$s.code -ne 0) { throw \$s.message }
"Support link: $origin/support/\$(\$s.data.code)"''',
      'curl': '''# list devices that were online in the last 5 minutes
curl -s -H "Authorization: Bearer rdk_your_key" "$base/peer/list?page=1&page_size=50&time_ago=-300"
# list device groups (customers)
curl -s -H "Authorization: Bearer rdk_your_key" "$base/device_group/list?page=1&page_size=100"
# approve a device waiting for approval, putting it in group 2
curl -s -X POST -H "Authorization: Bearer rdk_your_key" -H "Content-Type: application/json" \\
  -d '{"id": 5, "approve": true, "device_group_id": 2}' "$base/device_approval/decide"''',
      'app': '''rustdesk --assign --token rdk_your_key --device_group_name "Customer" [--strategy_name "Policy"] [--user_name owner]
rustdesk --deploy --token rdk_your_key''',
    };
    return Padding(
      padding: EdgeInsets.zero,
      child: CtCollapse(
        title: const Text('How to use API keys', style: TextStyle(fontWeight: FontWeight.w700)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(ctRadiusSm)),
            child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Building an integration? The full reference lists every endpoint with its request and response fields.'),
              CtButton('Full API reference', tone: Tone.primary, size: BtnSize.small, onPressed: _openRef),
              CtButton('Download for developers (.md)', size: BtnSize.small, onPressed: _download),
            ]),
          ),
          Text('1. Create a key', style: h4()),
          const SizedBox(height: 8),
          p('''1. Pick **Acts as user**. The key can do what that user's role allows, and never more. A dedicated user, such as "POS integration", keeps things clear in the logs.
2. Under **Permissions**, choose **Only these** and tick just what the integration needs (see the table below).
3. Copy the key when it's shown. It's only shown once; if it's lost, revoke it and make a new one.
4. Store it like a password: in the other system's secret settings, never in a script or email.'''),
          Text('2. Send it with every request', style: h4()),
          const SizedBox(height: 8),
          p('All endpoints live under `$base`. Put the key in the `Authorization` header:'),
          const CodeBox('Authorization: Bearer rdk_your_key', block: true),
          const SizedBox(height: 10),
          p('Every response is JSON in the same shape. `code` is `0` when it worked; anything else is an error, with the reason in `message`:'),
          const CodeBox('{ "code": 0, "message": "success", "data": { ... } }\n{ "code": 403, "message": "No access", "data": null }', block: true),
          const SizedBox(height: 10),
          p('A `401` HTTP status means the key is wrong, expired or revoked. `code: 403` means the key (or its user\'s role) doesn\'t include the permission that endpoint needs. Every change a key makes is recorded in **Security & Audit → Admin Activity**.'),
          Text('3. What each permission unlocks', style: h4()),
          const SizedBox(height: 8),
          CtTable(small: true, rows: [for (final e in endpoints) {'perm': e.$1, 'list': e.$2}], columns: [
            Col('Permission', width: 190, center: false, cell: (r, _) => Text('${r['perm']}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Col('Endpoints',
                minWidth: 400,
                center: false,
                cell: (r, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final e in r['list'] as List<(String, String, String)>)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(text: e.$1, style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, color: e.$1 == 'GET' ? c.success : c.warning)),
                            TextSpan(text: '  ${e.$2}', style: TextStyle(fontFamily: 'monospace', color: c.text)),
                            TextSpan(text: '  ${e.$3}', style: TextStyle(color: c.muted)),
                          ])),
                        ),
                    ])),
          ]),
          const SizedBox(height: 10),
          p('Lists take `page` and `page_size` (up to 200) and return `data.list` and `data.total`. POST bodies are JSON. When updating a device, send the whole device back with your changes, because fields you leave out are cleared.'),
          Text('4. Examples', style: h4()),
          const SizedBox(height: 8),
          CtTabs<String>(value: tab, tabs: const [('ps', 'PowerShell'), ('curl', 'curl'), ('app', 'RustDesk app')], onChanged: (v) => setState(() => tab = v)),
          if (tab == 'app') p('Keys also work with the RustDesk app\'s own commands, run as administrator on an installed client. The Enrol button on Device Groups builds these scripts for you.'),
          CodeBox(examples[tab]!, block: true),
          if (tab == 'app') p('\nBoth need **Manage devices**.'),
        ]),
      ),
    );
  }
}

class UserTokenPage extends StatefulWidget {
  const UserTokenPage({super.key});

  @override
  State<UserTokenPage> createState() => _UserTokenPageState();
}

class _UserTokenPageState extends State<UserTokenPage> {
  late final ListCtl ctl;
  List<Row_> users = [];

  @override
  void initState() {
    super.initState();
    ctl = ListCtl((q) => api.get('/user_token/list', params: q), query: {'is_my': 0, 'user_id': Console.I.args['user_id']})..load();
    Lookups.users().then((u) => setState(() => users = u));
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _logout(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('Logout')}))) return;
    try {
      await api.post('/user_token/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  Future<void> _batch() async {
    final rows = ctl.selectedRows;
    if (rows.isEmpty) return;
    if (!await confirm(context, T('Confirm?', {'param': T('BatchDelete')}))) return;
    try {
      await api.post('/user_token/batchDelete', body: {'ids': rows.map((r) => r['id']).toList()});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    String mask(String t) => t.length < 8 ? '****' : '${t.substring(0, 4)}****${t.substring(t.length - 4)}';
    return ListPage(
      ctl: ctl,
      selectable: true,
      filters: () => [
        QueryField(T('User'), qSelect<int>(ctl, 'user_id', [for (final u in users) Opt(asInt(u['id']), '${u['username']}')], filterable: true)),
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('BatchDelete'), tone: Tone.danger, onPressed: _batch),
        ]),
      ],
      columns: () => [
        const Col('id', prop: 'id', width: 100),
        Col(T('Owner'), cell: (r, _) => asInt(r['user_id']) > 0 ? CtTag(nameOf(users, r['user_id'], field: 'username')) : const SizedBox()),
        Col(T('SignedInWith'),
            width: 170,
            cell: (r, _) => r['client'] == 'integration'
                ? CtTag('${r['app_name'] ?? ''}'.isEmpty ? T('App') : '${r['app_name']}', small: true, tone: Tone.warning)
                : Text({'webadmin': T('WebConsole'), 'app': 'RustDesk app', 'webclient': 'Web client'}[r['client']] ??
                    ('${r['client'] ?? ''}'.isEmpty ? '-' : '${r['client']}'))),
        Col(T('Token'), cell: (r, _) => Text(mask('${r['token'] ?? ''}'))),
        Col(T('CreatedAt'), prop: 'created_at'),
        Col(T('ExpireTime'),
            cell: (r, _) {
              final e = asInt(r['expired_at']);
              return CtTag(e > 0 ? formatTime(e) : '-', tone: e * 1000 < DateTime.now().millisecondsSinceEpoch ? Tone.info : Tone.success);
            }),
        Col(T('Actions'), width: 200, cell: (r, _) => CtButton(T('Logout'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _logout(r))),
      ],
    );
  }
}

class OauthPage extends StatefulWidget {
  const OauthPage({super.key});

  @override
  State<OauthPage> createState() => _OauthPageState();
}

class _OauthPageState extends State<OauthPage> {
  final ctl = ListCtl((q) => api.get('/oauth/list', params: q))..load();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  String get redirect {
    final s = '${Console.I.server['api_server'] ?? ''}';
    return '${s.isNotEmpty ? s : Console.I.host.apiServer}/api/oidc/callback';
  }

  Future<void> _edit([Row_? row]) async {
    final f = <String, dynamic>{
      'id': row?['id'] ?? 0,
      'op': row?['op'] ?? '',
      'oauth_type': row?['oauth_type'] ?? '',
      'issuer': row?['issuer'] ?? '',
      'client_id': row?['client_id'] ?? '',
      'client_secret': row?['client_secret'] ?? '',
      'redirect_url': '',
      'scopes': row?['scopes'] ?? '',
      'auto_register': row?['auto_register'] == true,
      'pkce_enable': row?['pkce_enable'] == true,
      'pkce_method': '${row?['pkce_method'] ?? ''}'.isEmpty ? 'S256' : row!['pkce_method'],
    };
    final editing = asInt(f['id']) > 0;
    String? error;
    await showCtDialog(
      context,
      title: editing ? T('Update') : T('Create'),
      width: 800,
      builder: (ctx, set) {
        final oidc = f['oauth_type'] == 'oidc';
        Widget text(String key, String label, {String? ph, bool required = false, bool password = false}) => FormItem(
              label: label,
              required: required,
              child: CtInput(value: '${f[key]}', placeholder: ph, password: password, showPassword: password, onChanged: (v) => f[key] = v),
            );
        return Column(children: [
          FormItem(
            label: 'Type',
            required: true,
            child: CtRadios<String>(
              vertical: true,
              value: '${f['oauth_type']}',
              options: const [('github', 'GitHub'), ('google', 'Google'), ('linuxdo', 'LinuxDo'), ('oidc', 'OIDC')],
              onChanged: editing ? null : (v) => set(() => f['oauth_type'] = v),
            ),
          ),
          if (oidc) text('op', 'IdP', ph: T('Your IdP Name')),
          if (oidc) text('issuer', 'Issuer', required: true, ph: "${T('Check your IdP docs, without')} '/.well-known/openid-configuration'"),
          if (oidc) text('scopes', 'Scopes', ph: "${T('Optional, default is')} 'openid,profile,email'"),
          text('client_id', 'ClientId', required: true),
          text('client_secret', 'ClientSecret', required: true, password: editing),
          FormItem(
            label: 'RedirectUrl',
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(children: [Flexible(child: SelectableText(redirect)), CopyIcon(redirect)]),
            ),
          ),
          FormItem(
            label: 'PkceEnable',
            child: Align(alignment: Alignment.centerLeft, child: CtSwitch(value: f['pkce_enable'] == true, onChanged: (v) => set(() => f['pkce_enable'] = v))),
          ),
          if (f['pkce_enable'] == true)
            FormItem(
              label: 'PkceMethod',
              child: CtSelect<String>(
                value: '${f['pkce_method']}',
                options: const [Opt('S256', 'S256 (Recommended)'), Opt('plain', 'Plain')],
                onChanged: (v) => set(() => f['pkce_method'] = v ?? 'S256'),
              ),
            ),
          FormItem(
            label: T('AutoRegister'),
            help: T('AutoRegisterNote'),
            child: Align(alignment: Alignment.centerLeft, child: CtSwitch(value: f['auto_register'] == true, onChanged: (v) => set(() => f['auto_register'] = v))),
          ),
          if (error != null) CtAlert(error!, type: AlertType.error),
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          String? e;
          for (final k in ['oauth_type', 'client_id', 'client_secret', if (f['oauth_type'] == 'oidc') 'issuer']) {
            if ('${f[k]}'.isEmpty) {
              e = T('ParamRequired', {'param': k});
              break;
            }
          }
          if (e == null && f['pkce_enable'] == true && !['S256', 'plain'].contains(f['pkce_method'])) e = T('InvalidParam', {'param': 'pkce_method'});
          set(() => error = e);
          if (e != null) return;
          try {
            await api.post(editing ? '/oauth/update' : '/oauth/create', body: f);
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
      await api.post('/oauth/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListPage(
      ctl: ctl,
      filters: () => [
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('Add'), tone: Tone.danger, onPressed: () => _edit()),
        ]),
      ],
      columns: () => [
        const Col('ID', prop: 'id'),
        Col(T('IdP'), prop: 'op'),
        Col(T('Type'), prop: 'oauth_type'),
        Col(T('AutoRegister'), prop: 'auto_register'),
        Col(T('PkceEnable'), prop: 'pkce_enable'),
        Col(T('PkceMethod'), prop: 'pkce_method'),
        Col(T('CreatedAt'), prop: 'created_at'),
        Col(T('UpdatedAt'), prop: 'updated_at'),
        Col(T('Actions'),
            minWidth: 180,
            cell: (r, _) => Actions_([
                  CtButton(T('Edit'), size: BtnSize.table, onPressed: () => _edit(r)),
                  CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                ])),
      ],
    );
  }
}
