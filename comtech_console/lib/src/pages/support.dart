import 'dart:async';

import 'package:flutter/material.dart';

import '../console.dart';
import '../i18n.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/basic.dart';
import '../widgets/dialog.dart';
import '../widgets/form.dart';
import '../widgets/select.dart';
import '../widgets/table.dart';

const platformNames = {'windows': 'Windows', 'windows-x86': 'Windows 32-bit', 'linux': 'Linux', 'macos': 'macOS', 'android': 'Android'};
String platformName(String p) => platformNames[p] ?? p;

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final ctl = ListCtl((q) => api.get('/support_session/list', params: q));
  Map<String, dynamic> opts = {'loaded': false, 'mail_ready': false, 'mail_reason': '', 'builds': [], 'public_base': '', 'default_device_group_id': 0, 'can_set_default': false};
  List<Row_> groups = [];
  Timer? timer;
  final canSetApps = can(['client_builder']);

  @override
  void initState() {
    super.initState();
    _options();
    ctl.load();
    // a waiting session turns ready when the customer opens their app
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ctl.list.any((s) => s['status'] == 'waiting' && s['expired'] != true)) ctl.load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    ctl.dispose();
    super.dispose();
  }

  Future<void> _options() async {
    final r = await Future.wait([
      api.get('/support_session/options', quiet: true).then<dynamic>((v) => v).catchError((_) => null),
      Lookups.deviceGroups(),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] is Map) opts = {...Map<String, dynamic>.from(r[0] as Map), 'loaded': true};
      groups = r[1] as List<Row_>;
    });
  }

  List<Row_> get builds => rowsOf(opts['builds']);
  bool get mailReady => opts['mail_ready'] == true;
  bool get supportApps => opts['support_apps'] == true || (opts['support_apps'] is num && opts['support_apps'] != 0);

  String groupName(dynamic id) => nameOf(groups, id, fallback: '#$id');
  String buildLabel(Row_ b) => [
        b['app_name'],
        platformName('${b['platform']}'),
        asInt(b['device_group_id']) > 0 ? groupName(b['device_group_id']) : T('NoDeviceGroup'),
        '#${b['id']}',
      ].join(' · ');
  String buildName(dynamic id) {
    if (asInt(id) == 0) return T('SupportAppsOption');
    final b = builds.where((b) => b['id'] == id).firstOrNull;
    return b == null ? T('DeletedClient') : buildLabel(b);
  }

  bool active(Row_ r) => r['status'] != 'closed' && r['expired'] != true;
  String statusLabel(Row_ r) => r['expired'] == true
      ? 'SessionExpired'
      : ({'waiting': 'SessionWaiting', 'ready': 'SessionReady', 'closed': 'SessionEnded'}[r['status']] ?? '${r['status']}');
  Tone statusTone(Row_ r) => r['expired'] == true || r['status'] == 'closed' ? Tone.info : (r['status'] == 'ready' ? Tone.success : Tone.warning);
  String hoursLabel(int h) => h < 24 ? T('Hours', {'param': h}) : T('Days', {'param': h ~/ 24});

  Future<void> _apps() async {
    await _options();
    Map<String, dynamic> current = {};
    try {
      final d = await api.get('/support_session/apps', quiet: true);
      current = Map<String, dynamic>.from(d['apps'] as Map? ?? {});
    } catch (_) {}
    if (!mounted) return;
    const platforms = ['windows', 'macos', 'android', 'linux'];
    final apps = {for (final p in platforms) p: asInt(current[p]) == 0 ? null : asInt(current[p])};
    await showCtDialog(
      context,
      title: T('SupportApps'),
      width: 640,
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Muted(T('SupportAppsHelp'), padding: const EdgeInsets.only(bottom: 16)),
        for (final p in platforms)
          FormItem(
            label: platformName(p),
            child: CtSelect<int>(
              value: apps[p],
              clearable: true,
              placeholder: T('None'),
              options: [
                for (final b in builds.where((b) => b['platform'] == p || (p == 'windows' && b['platform'] == 'windows-x86')))
                  Opt(asInt(b['id']), buildLabel(b)),
              ],
              onChanged: (v) => set(() => apps[p] = v),
            ),
          ),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Save'), tone: Tone.primary, onPressed: () async {
          try {
            await api.post('/support_session/apps', body: {'apps': {for (final p in platforms) p: apps[p] ?? 0}});
            Toasts.success(T('OperationSuccess'));
            if (ctx.mounted) Navigator.of(ctx).pop();
            _options();
          } catch (_) {}
        }),
      ],
    );
  }

  Future<void> _create() async {
    await _options();
    if (!mounted) return;
    final f = <String, dynamic>{
      'customer_name': '',
      'customer_email': '',
      'note': '',
      'message': '',
      'build_id': supportApps ? 0 : (builds.isEmpty ? null : builds.first['id']),
      'expires_hours': 24,
      'send_email': mailReady,
      'device_group_id': asInt(opts['default_device_group_id']) == 0 ? null : asInt(opts['default_device_group_id']),
    };
    var submitting = false;
    await showCtDialog(
      context,
      title: T('NewSupportSession'),
      width: 640,
      builder: (ctx, set) {
        final c = ctx.ct;
        final gid = asInt(f['device_group_id']);
        final defaultId = asInt(opts['default_device_group_id']);
        return Column(children: [
          FormItem(label: T('CustomerName'), labelWidth: 170, child: CtInput(value: '${f['customer_name']}', onChanged: (v) => f['customer_name'] = v)),
          FormItem(
            label: T('CustomerEmail'),
            labelWidth: 170,
            child: CtInput(value: '${f['customer_email']}', placeholder: 'name@company.com', onChanged: (v) => f['customer_email'] = v),
          ),
          FormItem(
            label: T('SupportClient'),
            labelWidth: 170,
            required: true,
            help: T('SupportClientHelp'),
            child: CtSelect<int>(
              value: f['build_id'] as int?,
              options: [
                if (supportApps) Opt(0, T('SupportAppsOption')),
                for (final b in builds)
                  Opt(
                    asInt(b['id']),
                    buildLabel(b),
                    child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${b['app_name']} · ${platformName('${b['platform']}')}'),
                      CtTag(asInt(b['device_group_id']) > 0 ? groupName(b['device_group_id']) : T('NoDeviceGroup'),
                          small: true, plain: true, tone: asInt(b['device_group_id']) > 0 ? Tone.primary : Tone.info),
                      Text('#${b['id']}${'${b['note'] ?? ''}'.isNotEmpty ? ' · ${b['note']}' : ''}', style: TextStyle(fontSize: 12, color: c.muted)),
                    ]),
                  ),
              ],
              onChanged: (v) => set(() => f['build_id'] = v),
            ),
          ),
          FormItem(
            label: T('DeviceGroup'),
            labelWidth: 170,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CtSelect<int>(
                value: f['device_group_id'] as int?,
                clearable: true,
                filterable: true,
                placeholder: T('NoDeviceGroup'),
                options: [for (final g in groups) Opt(asInt(g['id']), '${g['name']}')],
                onChanged: (v) => set(() => f['device_group_id'] = v),
              ),
              const SizedBox(height: 4),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                Text(T('SessionGroupHelp'), style: TextStyle(fontSize: 12, color: c.muted, height: 1.45)),
                if (opts['can_set_default'] == true && gid != defaultId)
                  CtButton(T('SetAsDefault'), link: true, tone: Tone.primary, size: BtnSize.small, onPressed: () async {
                    try {
                      await api.post('/support_session/default_group', body: {'device_group_id': gid});
                      set(() => opts['default_device_group_id'] = gid);
                      Toasts.success(T('DefaultSaved'));
                    } catch (_) {}
                  })
                else if (gid != 0 && gid == defaultId)
                  Text(T('DefaultTag'), style: TextStyle(fontSize: 12, color: c.success)),
              ]),
            ]),
          ),
          FormItem(
            label: T('LinkExpiresAfter'),
            labelWidth: 170,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CtSelect<int>(
                width: 200,
                value: f['expires_hours'] as int,
                options: [for (final h in [2, 8, 24, 72, 168]) Opt(h, hoursLabel(h))],
                onChanged: (v) => set(() => f['expires_hours'] = v ?? 24),
              ),
            ),
          ),
          FormItem(label: T('InternalNote'), labelWidth: 170, child: CtInput(value: '${f['note']}', placeholder: T('InternalNoteHelp'), onChanged: (v) => f['note'] = v)),
          FormItem(
            label: T('EmailInvite'),
            labelWidth: 170,
            child: Align(alignment: Alignment.centerLeft, child: CtSwitch(value: f['send_email'] == true, onChanged: mailReady ? (v) => set(() => f['send_email'] = v) : null)),
          ),
          if (f['send_email'] == true)
            FormItem(label: T('MessageToCustomer'), labelWidth: 170, child: CtInput(value: '${f['message']}', rows: 3, onChanged: (v) => f['message'] = v)),
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(f['send_email'] == true ? T('CreateAndSend') : T('Create'), tone: Tone.primary, loading: submitting, onPressed: () async {
          set(() => submitting = true);
          try {
            await api.post('/support_session/create', body: {...f, 'device_group_id': f['device_group_id'] ?? 0}, timeout: const Duration(seconds: 60));
            Toasts.success(f['send_email'] == true ? T('InviteSent') : T('SessionCreated'));
            if (ctx.mounted) Navigator.of(ctx).pop();
            ctl.filter();
          } catch (_) {
            set(() => submitting = false);
            ctl.load();
          }
        }),
      ],
    );
  }

  Future<void> _resend(Row_ r) async {
    final msg = TextEditingController();
    var sending = false;
    await showCtDialog(
      context,
      title: T('ResendEmail'),
      width: 560,
      builder: (ctx, set) => FormItem(top: true, label: T('MessageToCustomer'), child: CtInput(controller: msg, rows: 3)),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Send'), tone: Tone.primary, loading: sending, onPressed: () async {
          set(() => sending = true);
          try {
            await api.post('/support_session/resend', body: {'id': r['id'], 'message': msg.text}, timeout: const Duration(seconds: 60));
            Toasts.success(T('InviteSent'));
            if (ctx.mounted) Navigator.of(ctx).pop();
            ctl.load();
          } catch (_) {
            set(() => sending = false);
          }
        }),
      ],
    );
  }

  Future<void> _act(Row_ r, String action, String path) async {
    if (!await confirm(context, T('Confirm?', {'param': T(action)}))) return;
    try {
      await api.post(path, body: {'id': r['id']});
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final host = Console.I.host;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => PageColumn([
        QueryBar(
          above: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (opts['loaded'] == true && builds.isEmpty)
              CtAlert(T('SupportNeedsBuild'), margin: const EdgeInsets.only(bottom: 12))
            else if (opts['loaded'] == true && !supportApps)
              CtAlert(T('SupportAppsNotSet'), margin: const EdgeInsets.only(bottom: 12)),
            if (opts['loaded'] == true && !mailReady)
              CtAlert(T('EmailNotConfigured'), description: '${opts['mail_reason'] ?? ''}', type: AlertType.warning, margin: const EdgeInsets.only(bottom: 12)),
          ]),
          children: [
            Buttons([
              CtButton(T('NewSupportSession'), tone: Tone.primary, onPressed: builds.isEmpty && !supportApps ? null : _create),
              CtButton(T('Refresh'), onPressed: ctl.load),
              if (canSetApps) CtButton(T('SupportApps'), onPressed: _apps),
            ]),
          ],
        ),
        CtCard(
          child: CtTable(loading: ctl.loading, rows: ctl.list, columns: [
            Col(T('Customer'),
                minWidth: 190,
                center: false,
                cell: (r, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text([r['customer_name'], r['customer_email'], '-'].firstWhere((v) => v != null && '$v'.isNotEmpty).toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if ('${r['customer_name'] ?? ''}'.isNotEmpty && '${r['customer_email'] ?? ''}'.isNotEmpty)
                        Text('${r['customer_email']}', style: TextStyle(fontSize: 12, color: c.muted)),
                      if ('${r['note'] ?? ''}'.isNotEmpty) Text('${r['note']}', style: TextStyle(fontSize: 12, color: c.muted)),
                    ])),
            Col(T('Status'),
                width: 170,
                cell: (r, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                      CtTag(T(statusLabel(r)), tone: statusTone(r)),
                      if (asInt(r['opened_at']) > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(T('LinkOpenedFrom', {'ip': '${r['opened_ip'] ?? ''}'.isEmpty ? '?' : r['opened_ip']}),
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: c.muted)),
                        )
                      else if (active(r))
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text(T('LinkNotOpened'), style: TextStyle(fontSize: 11.5, color: c.muted))),
                    ])),
            Col(T('DeviceId'),
                width: 140,
                cell: (r, _) => '${r['peer_id'] ?? ''}'.isNotEmpty
                    ? Text('${r['peer_id']}', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600))
                    : Text('-', style: TextStyle(color: c.muted))),
            Col(T('DeviceGroup'),
                minWidth: 120, cell: (r, _) => asInt(r['device_group_id']) > 0 ? CtTag(groupName(r['device_group_id']), plain: true) : const SizedBox()),
            Col(T('Client'), minWidth: 120, cell: (r, _) => Text(buildName(r['build_id']), textAlign: TextAlign.center)),
            Col(T('Expires'), width: 150, cell: (r, _) => Text(formatTime(asInt(r['expires_at'])))),
            Col(T('Actions'),
                width: 360,
                cell: (r, _) => Actions_([
                      if ('${r['peer_id'] ?? ''}'.isNotEmpty)
                        CtButton(T('Connect'), tone: Tone.success, size: BtnSize.table, onPressed: () => host.connect('${r['peer_id']}')),
                      CtButton(T('CopyLink'), size: BtnSize.table, onPressed: () => copyText('${opts['public_base']}${r['code']}')),
                      if ('${r['customer_email'] ?? ''}'.isNotEmpty && active(r))
                        CtButton(T('ResendEmail'), size: BtnSize.table, onPressed: mailReady ? () => _resend(r) : null),
                      if (active(r)) CtButton(T('End'), tone: Tone.warning, size: BtnSize.table, onPressed: () => _act(r, 'End', '/support_session/close')),
                      CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _act(r, 'Delete', '/support_session/delete')),
                    ])),
          ]),
        ),
        CtPagination(total: ctl.total, page: ctl.page, pageSize: ctl.pageSize, sizes: const [10, 20, 50], onChange: ctl.setPage),
      ]),
    );
  }
}
