import 'dart:async';
import 'dart:math';

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

class MailPage extends StatefulWidget {
  const MailPage({super.key});

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  Map<String, dynamic> form = {'enable': false, 'tenant_id': '', 'client_id': '', 'client_secret': '', 'secret_set': false, 'allowed_domains': '', 'status': '', 'my_email': ''};
  bool loading = false, saving = false, testing = false;
  int version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await api.get('/settings/mail');
      form = {...Map<String, dynamic>.from(d as Map), 'client_secret': ''};
      final mine = '${form['my_email'] ?? ''}';
      if ('${form['allowed_domains'] ?? ''}'.isEmpty && mine.contains('@')) form['allowed_domains'] = mine.split('@').last;
      version++;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await api.post('/settings/mail', body: form);
      Toasts.success(T('OperationSuccess'));
      _load();
    } catch (_) {}
    if (mounted) setState(() => saving = false);
  }

  Future<void> _test() async {
    setState(() => testing = true);
    try {
      await api.post('/settings/mail/test', timeout: const Duration(seconds: 60));
      Toasts.success(T('TestEmailSent'));
    } catch (_) {}
    if (mounted) setState(() => testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = '${form['status'] ?? ''}';
    Widget text(String k, String label, {String? ph, bool password = false, String? help}) => FormItem(
          label: label,
          labelWidth: 170,
          help: help,
          child: CtInput(key: ValueKey('$k$version'), value: '${form[k] ?? ''}', placeholder: ph, password: password, showPassword: password, onChanged: (v) => form[k] = v),
        );
    return Loading(
      loading: loading,
      child: PageColumn([
        CtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHead(T('MicrosoftGraphEmail'),
                help: T('MicrosoftGraphEmailHelp'),
                trailing: CtTag(status.isNotEmpty ? T('NotReady') : T('Ready'), large: true, tone: status.isNotEmpty ? Tone.warning : Tone.success)),
            const SizedBox(height: 18),
            if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 18), child: CtAlert(status, type: AlertType.warning)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(children: [
                FormItem(
                  label: T('SendEmail'),
                  labelWidth: 170,
                  child: Align(alignment: Alignment.centerLeft, child: CtSwitch(value: form['enable'] == true, onChanged: (v) => setState(() => form['enable'] = v))),
                ),
                text('tenant_id', T('TenantId'), ph: '00000000-0000-0000-0000-000000000000'),
                text('client_id', T('ClientId'), ph: '00000000-0000-0000-0000-000000000000'),
                text('client_secret', T('ClientSecret'),
                    password: true,
                    ph: form['secret_set'] == true ? T('SecretSavedPlaceholder') : '',
                    help: form['secret_set'] == true ? T('SecretSavedHelp') : T('SecretHelp')),
                text('allowed_domains', T('AllowedDomains'), ph: 'comtechit.au', help: T('AllowedDomainsHelp')),
                FormItem(
                  labelWidth: 170,
                  label: '',
                  child: Buttons([
                    CtButton(T('Save'), tone: Tone.primary, loading: saving, onPressed: _save),
                    CtButton(T('SendTestEmail'), loading: testing, onPressed: status.isNotEmpty ? null : _test),
                    if ('${form['my_email'] ?? ''}'.isNotEmpty) Muted(T('TestGoesTo', {'param': form['my_email']})),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
        CtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(T('SetupSteps'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const MarkdownView('''1. In **entra.microsoft.com** go to **App registrations → New registration**. Name it "RustDesk API", single tenant, no redirect URI.
2. Copy the **Directory (tenant) ID** and **Application (client) ID** from its Overview into the fields above.
3. Under **Certificates & secrets**, create a client secret and paste its **Value** above.
4. Give it permission to send, either:
  - **Recommended:** in Exchange Online PowerShell, use "RBAC for Applications" to grant **Application Mail.Send** scoped to a group of staff mailboxes. Don't also add Mail.Send in Entra, as that would allow every mailbox.
  - **Simpler:** under **API permissions**, add **Microsoft Graph → Application permissions → Mail.Send** and grant admin consent. This lets the app send as any mailbox in the tenant.
5. Set each staff member's **Email** on the Users page to their Microsoft 365 address, then save here and send a test.'''),
          ]),
        ),
      ]),
    );
  }
}

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  Map<String, dynamic> form = {
    'mfa_required': 'off',
    'admin_idle_minutes': 30,
    'admin_max_hours': 12,
    'client_days': 30,
    'password_min_length': 10,
    'login_alerts': true,
    'alert_email': '',
    'alert_sender_id': 0,
    'connect_mode': 'off',
    'backup_keep': 14,
    'data_encryption': false,
  };
  List<Row_> senders = [];
  bool loading = false, saving = false;
  int version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await api.get('/security/settings');
      form = {...form, ...Map<String, dynamic>.from(d['settings'] as Map)};
      senders = rowsOf(d['senders']);
      version++;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (form['mfa_required'] != 'off') {
      try {
        final mine = await api.get('/my/mfa', quiet: true);
        if (mine['enabled'] != true && mounted && !await confirm(context, T('RequireTwoFactorSelfWarning'), confirmText: T('Save'))) return;
      } catch (_) {}
    }
    if (form['connect_mode'] == 'enforce' && mounted && !await confirm(context, T('EnforceConnectionsWarning'), confirmText: T('Save'))) return;
    setState(() => saving = true);
    try {
      await api.post('/security/settings', body: form);
      Toasts.success(T('OperationSuccess'));
    } catch (_) {}
    if (mounted) setState(() => saving = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final enc = form['data_encryption'] == true;
    Widget h4(String t) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 14), child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)));
    Widget item(String label, Widget child, {String? help}) => FormItem(label: label, labelWidth: 260, help: help, child: Align(alignment: Alignment.centerLeft, child: child));
    Widget number(String k, int min, int max, String unit) => Row(mainAxisSize: MainAxisSize.min, children: [
          CtNumberInput(value: asInt(form[k]), min: min, max: max, onChanged: (v) => setState(() => form[k] = v)),
          const SizedBox(width: 10),
          Muted(unit),
        ]);
    return Loading(
      loading: loading,
      child: CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHead(T('SecuritySettings'), help: T('SecuritySettingsHelp')),
          const SizedBox(height: 16),
          if (!loading)
            CtAlert(enc ? T('DataEncryptionOn') : T('DataEncryptionOff'),
                description: enc ? T('DataEncryptionOnHelp') : T('DataEncryptionOffHelp'),
                type: enc ? AlertType.success : AlertType.warning,
                margin: const EdgeInsets.only(bottom: 16)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              h4(T('TwoFactorAuth')),
              item(
                T('RequireTwoFactorFor'),
                CtSegmented<String>(
                  value: '${form['mfa_required']}',
                  options: [('off', T('NobodyOptional')), ('admins', T('Administrators')), ('all', T('Everyone'))],
                  onChanged: (v) => setState(() => form['mfa_required'] = v),
                ),
                help: T('RequireTwoFactorHelp'),
              ),
              h4(T('SignInAlerts')),
              item(T('NewIpAlerts'), CtSwitch(value: form['login_alerts'] == true, onChanged: (v) => setState(() => form['login_alerts'] = v)), help: T('NewIpAlertsHelp')),
              item(
                T('AlertCopyTo'),
                CtInput(
                    key: ValueKey('alert$version'),
                    width: 460,
                    value: '${form['alert_email'] ?? ''}',
                    clearable: true,
                    placeholder: 'security@comtechit.au, helpdesk@comtechit.au',
                    onChanged: (v) => form['alert_email'] = v),
                help: T('AlertCopyToHelp'),
              ),
              item(
                T('AlertSender'),
                CtSelect<int>(
                  width: 360,
                  value: asInt(form['alert_sender_id']),
                  options: [Opt(0, T('AlertSenderAuto')), for (final u in senders) Opt(asInt(u['id']), '${u['username']} (${u['email']})')],
                  onChanged: (v) => setState(() => form['alert_sender_id'] = v ?? 0),
                ),
                help: T('AlertSenderHelp'),
              ),
              h4(T('SignedInConnections')),
              item(
                T('SignedInConnectionsMode'),
                CtSegmented<String>(
                  value: '${form['connect_mode']}',
                  options: [('off', T('Off')), ('log', T('LogOnly')), ('enforce', T('Enforce'))],
                  onChanged: (v) => setState(() => form['connect_mode'] = v),
                ),
                help: T('SignedInConnectionsHelp'),
              ),
              h4(T('Backups')),
              item(T('BackupKeep'), number('backup_keep', 1, 365, T('BackupsUnit')), help: T('BackupKeepHelp')),
              h4(T('Sessions')),
              item(T('AdminIdleTimeout'), number('admin_idle_minutes', 5, 1440, T('UnitMinutes')), help: T('AdminIdleTimeoutHelp')),
              item(T('AdminMaxSession'), number('admin_max_hours', 1, 720, T('UnitHours')), help: T('AdminMaxSessionHelp')),
              item(T('ClientSessionLength'), number('client_days', 1, 365, T('UnitDays')), help: T('ClientSessionLengthHelp')),
              h4(T('Passwords')),
              item(T('PasswordMinLength'), number('password_min_length', 8, 64, T('Characters')), help: T('PasswordMinLengthHelp')),
              item('', CtButton(T('Save'), tone: Tone.primary, loading: saving, onPressed: _save)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  List<Row_> checks = [];
  int checkedAt = 0;
  final repo = TextEditingController();
  bool loading = false, running = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    repo.dispose();
    super.dispose();
  }

  void _apply(dynamic d) {
    checks = rowsOf(d['checks']);
    checkedAt = asInt(d['checked_at']) > 0 ? asInt(d['checked_at']) : 0;
    repo.text = '${d['runner_repo'] ?? ''}';
  }

  Future<void> _load() async {
    setState(() => loading = checks.isEmpty);
    try {
      final d = await api.get('/health/list', quiet: true);
      _apply(d);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _run() async {
    setState(() => running = true);
    try {
      _apply(await api.post('/health/run', timeout: const Duration(seconds: 120)));
    } catch (_) {}
    if (mounted) setState(() => running = false);
  }

  Future<void> _saveRepo() async {
    try {
      await api.post('/health/runner_repo', body: {'repo': repo.text});
      Toasts.success(T('OperationSuccess'));
      _run();
    } catch (_) {}
  }

  Tone tone(String s) => switch (s) { 'ok' => Tone.success, 'warn' => Tone.warning, 'fail' => Tone.danger, _ => Tone.info };

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final counts = <String, int>{};
    for (final ch in checks) {
      counts['${ch['status']}'] = (counts['${ch['status']}'] ?? 0) + 1;
    }
    return PageColumn([
      CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHead(
            T('SystemHealth'),
            help: T('SystemHealthHelp'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (checkedAt > 0) Muted(T('LastChecked', {'when': timeAgo(checkedAt)}), size: 12),
              const SizedBox(width: 12),
              CtButton(T('CheckNow'), tone: Tone.primary, loading: running, onPressed: _run),
            ]),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            for (final s in ['fail', 'warn', 'ok']) CtTag('${counts[s] ?? 0} ${T('Health_$s')}', tone: tone(s), plain: true),
          ]),
        ]),
      ),
      CtCard(
        child: Loading(
          loading: loading,
          minHeight: 100,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!loading && checks.isEmpty) Muted(T('HealthNotYet')),
            for (var i = 0; i < checks.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.border))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 5, right: 14), child: Dot(c.tone(tone('${checks[i]['status']}')), size: 10, glow: true)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('${checks[i]['label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        CtTag(T('Health_${checks[i]['status']}'), small: true, tone: tone('${checks[i]['status']}')),
                        Muted(T('HealthSince', {'when': timeAgo(asInt(checks[i]['since']))}), size: 12),
                      ]),
                      Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText('${checks[i]['detail'] ?? ''}', style: TextStyle(fontSize: 13, color: c.text2))),
                      if (checks[i]['key'] == 'runner')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            SizedBox(width: 240, child: CtInput(controller: repo, height: 28, placeholder: 'owner/rustdesk-api')),
                            const SizedBox(width: 8),
                            CtButton(T('Save'), size: BtnSize.small, onPressed: _saveRepo),
                          ]),
                        ),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class WebhooksPage extends StatefulWidget {
  const WebhooksPage({super.key});

  @override
  State<WebhooksPage> createState() => _WebhooksPageState();
}

class _WebhooksPageState extends State<WebhooksPage> {
  List<Row_> list = [];
  List<String> events = [];
  bool loading = false;
  int testing = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await api.get('/webhook/list');
      list = rowsOf(d);
      events = [for (final e in (d['events'] as List? ?? const [])) '$e'];
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String _secret() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _edit([Row_? row]) async {
    final ev = row == null ? <String>[] : '${row['events']}'.split(',');
    var all = ev.contains('*');
    final f = <String, dynamic>{
      'id': row?['id'] ?? 0,
      'name': row?['name'] ?? '',
      'url': row?['url'] ?? '',
      'secret': row == null ? _secret() : '',
      'events': ev.where((e) => e != '*').toList(),
      'enabled': row == null ? true : row['enabled'] == true,
    };
    final secret = TextEditingController(text: '${f['secret']}');
    var saving = false;
    await showCtDialog(
      context,
      title: asInt(f['id']) > 0 ? T('Update') : T('AddWebhook'),
      width: 720,
      builder: (ctx, set) {
        final c = ctx.ct;
        final chosen = f['events'] as List<String>;
        return Column(children: [
          FormItem(label: T('Name'), labelWidth: 140, child: CtInput(value: '${f['name']}', placeholder: 'POS', onChanged: (v) => f['name'] = v)),
          FormItem(label: T('Address'), labelWidth: 140, child: CtInput(value: '${f['url']}', placeholder: 'https://pos.example.com/hooks/rustdesk', onChanged: (v) => f['url'] = v)),
          FormItem(
            label: T('Secret'),
            labelWidth: 140,
            help: T('WebhookSecretHelp'),
            child: CtInput(
              controller: secret,
              placeholder: asInt(f['id']) > 0 ? T('SecretKeep') : '',
              append: CtButton(T('Generate'), onPressed: () => secret.text = _secret()),
            ),
          ),
          FormItem(
            label: T('Events'),
            labelWidth: 140,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 6), child: CtCheckbox(value: all, label: Text(T('AllEvents')), onChanged: (v) => set(() => all = v))),
              if (!all)
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CtCheckbox(
                      value: chosen.contains(e),
                      label: Text.rich(TextSpan(children: [
                        TextSpan(text: e, style: TextStyle(color: c.text)),
                        TextSpan(text: ' — ${T('Event_${e.replaceFirst('.', '_')}')}', style: TextStyle(fontSize: 12, color: c.muted)),
                      ])),
                      onChanged: (v) => set(() => f['events'] = v ? [...chosen, e] : chosen.where((x) => x != e).toList()),
                    ),
                  ),
            ]),
          ),
          FormItem(
            label: T('Enabled'),
            labelWidth: 140,
            child: Align(alignment: Alignment.centerLeft, child: CtSwitch(value: f['enabled'] == true, onChanged: (v) => set(() => f['enabled'] = v))),
          ),
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Save'), tone: Tone.primary, loading: saving, onPressed: () async {
          set(() => saving = true);
          try {
            await api.post('/webhook/save', body: {...f, 'secret': secret.text, 'events': all ? ['*'] : f['events']});
            Toasts.success(T('OperationSuccess'));
            if (ctx.mounted) Navigator.of(ctx).pop();
            _load();
          } catch (_) {
            set(() => saving = false);
          }
        }),
      ],
    );
  }

  Future<void> _del(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('Delete')}))) return;
    try {
      await api.post('/webhook/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      _load();
    } catch (_) {}
  }

  Future<void> _test(Row_ r) async {
    setState(() => testing = asInt(r['id']));
    try {
      final d = await api.post('/webhook/test', body: {'id': r['id']});
      if ('${d['error'] ?? ''}'.isNotEmpty) {
        Toasts.error(T('WebhookTestFailed', {'error': d['error']}));
      } else {
        Toasts.success(T('WebhookTestOk', {'status': d['status']}));
      }
      _load();
    } catch (_) {}
    if (mounted) setState(() => testing = 0);
  }

  Future<void> _deliveries(Row_ r) async {
    var rows = <Row_>[];
    var started = false;
    await showCtDialog(
      context,
      title: T('DeliveriesFor', {'name': r['name']}),
      width: 1100,
      builder: (ctx, set) {
        if (!started) {
          started = true;
          api.get('/webhook/deliveries', params: {'webhook_id': r['id'], 'limit': 100}).then((d) => set(() => rows = rowsOf(d))).catchError((_) {});
        }
        return CtTable(small: true, rows: rows, columns: [
          Col(T('Time'), prop: 'created_at', width: 160),
          Col(T('Event'), prop: 'event', width: 190),
          Col(T('Result'), width: 110, cell: (d, _) => CtTag('${d['status'] ?? ''}'.isEmpty || d['status'] == 0 ? T('NoResponse') : '${d['status']}', small: true, tone: '${d['error'] ?? ''}'.isNotEmpty ? Tone.danger : Tone.success)),
          Col(T('Attempt'), prop: 'attempts', width: 80),
          const Col('ms', prop: 'duration_ms', width: 70),
          Col(T('Details'), minWidth: 200, center: false, cell: (d, _) {
            final t = '${d['error'] ?? ''}'.isNotEmpty ? '${d['error']}' : '${d['payload'] ?? ''}';
            return Tooltip(message: t, child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis));
          }),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return PageColumn([
      CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHead(T('Webhooks'), help: T('WebhooksHelp'), trailing: CtButton(T('AddWebhook'), tone: Tone.primary, onPressed: () => _edit())),
          const SizedBox(height: 12),
          CtCollapse(
            title: Text(T('WebhookHowTo')),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Muted(T('WebhookHowToText'), padding: const EdgeInsets.only(bottom: 10)),
              const CodeBox('''POST https://your-app/rustdesk-events
X-RustDesk-Event: support_session.ready
X-RustDesk-Signature: sha256=<hex HMAC-SHA256 of the raw body, keyed with the secret>
{"event":"support_session.ready","time":1790000000,"data":{"id":12,"peer_id":"123456789",...}}''', block: true),
            ]),
          ),
        ]),
      ),
      CtCard(
        child: CtTable(loading: loading, rows: list, columns: [
          Col(T('Name'), prop: 'name', width: 160),
          Col(T('Address'), prop: 'url', minWidth: 240, ellipsis: true),
          Col(T('Events'),
              minWidth: 220,
              cell: (r, _) => Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
                    for (final e in '${r['events']}'.split(',')) CtTag(e == '*' ? T('AllEvents') : e, small: true),
                  ])),
          Col(T('Status'),
              width: 190,
              cell: (r, _) {
                if (r['enabled'] != true) return CtTag(T('Disabled'), tone: Tone.info);
                if (asInt(r['last_at']) == 0) return Muted(T('NotUsedYet'), size: 12);
                final err = '${r['last_error'] ?? ''}';
                return Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Tooltip(
                    message: err.isNotEmpty ? err : T('Delivered'),
                    child: CtTag(asInt(r['last_status']) == 0 ? T('NoResponse') : '${r['last_status']}', tone: err.isNotEmpty ? Tone.danger : Tone.success),
                  ),
                  Text(timeAgo(asInt(r['last_at'])), style: TextStyle(fontSize: 12, color: c.muted)),
                ]);
              }),
          Col(T('Actions'),
              width: 330,
              cell: (r, _) => Actions_([
                    CtButton(T('SendTest'), size: BtnSize.table, loading: testing == r['id'], onPressed: () => _test(r)),
                    CtButton(T('Deliveries'), size: BtnSize.table, onPressed: () => _deliveries(r)),
                    CtButton(T('Edit'), tone: Tone.primary, size: BtnSize.table, onPressed: () => _edit(r)),
                    CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                  ])),
        ]),
      ),
    ]);
  }
}

class BackupsPage extends StatefulWidget {
  const BackupsPage({super.key});

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  List<Row_> list = [];
  String problem = '';
  int keep = 14;
  bool loading = false, running = false;
  String verifying = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await api.get('/backup/list');
      list = rowsOf(d);
      problem = '${d['problem'] ?? ''}';
      keep = asInt(d['keep']);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String size(num n) => n > (1 << 20) ? '${(n / (1 << 20)).toStringAsFixed(1)} MB' : '${(n / 1024).ceil()} KB';

  Future<void> _run() async {
    setState(() => running = true);
    try {
      await api.post('/backup/run', timeout: const Duration(seconds: 300));
      Toasts.success(T('BackupDone'));
      _load();
    } catch (_) {}
    if (mounted) setState(() => running = false);
  }

  Future<void> _verify(Row_ r) async {
    setState(() => verifying = '${r['name']}');
    try {
      final d = await api.post('/backup/verify', body: {'name': r['name']}, timeout: const Duration(seconds: 300));
      if (mounted) await alertBox(context, '${d['result']}', title: T('TestRestore'));
    } catch (_) {}
    if (mounted) setState(() => verifying = '');
  }

  Future<String> _link(Row_ r) async {
    try {
      final d = await api.post('/backup/link', body: {'name': r['name']});
      return '${Console.I.host.apiServer}${d['url']}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _del(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('Delete')}))) return;
    try {
      await api.post('/backup/delete', body: {'name': r['name']});
      Toasts.success(T('OperationSuccess'));
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PageColumn([
      CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHead(T('Backups'), help: T('BackupsHelp', {'keep': keep}), trailing: CtButton(T('BackUpNow'), tone: Tone.primary, loading: running, onPressed: problem.isNotEmpty ? null : _run)),
          if (problem.isNotEmpty) CtAlert(problem, type: AlertType.warning, margin: const EdgeInsets.only(top: 14)),
          const SizedBox(height: 12),
          CtCollapse(
            title: Text(T('BackupRestoreHow')),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Muted(T('BackupOffsiteText'), padding: const EdgeInsets.only(bottom: 8)),
              const CodeBox('curl -fo "rustdesk-api-\$(date +%F).rdbak" "<download link>"', block: true),
              Muted(T('BackupRestoreText'), padding: const EdgeInsets.only(top: 12, bottom: 8)),
              const CodeBox('''cd ~/comtech-remote-stack/rustdesk
docker compose stop rustdesk-api
docker compose run --rm --entrypoint /app/apimain rustdesk-api restore-backup /app/data/backups/<name>.rdbak
docker compose up -d rustdesk-api''', block: true),
            ]),
          ),
        ]),
      ),
      CtCard(
        child: CtTable(loading: loading, rows: list, columns: [
          Col(T('File'), prop: 'name', minWidth: 260, center: false),
          Col(T('Time'), width: 190, cell: (r, _) => Text(formatTime(asInt(r['created_at'])))),
          Col(T('Size'), width: 110, cell: (r, _) => Text(size(asInt(r['size'])))),
          Col(T('Actions'),
              width: 360,
              cell: (r, _) => Actions_([
                    CtButton(T('TestRestore'), size: BtnSize.table, loading: verifying == r['name'], onPressed: () => _verify(r)),
                    CtButton(T('Download'), tone: Tone.primary, size: BtnSize.table, onPressed: () async {
                      final u = await _link(r);
                      if (u.isNotEmpty) openUrl(u);
                    }),
                    CtButton(T('CopyLink'), size: BtnSize.table, onPressed: () async {
                      final u = await _link(r);
                      if (u.isNotEmpty) copyText(u, done: T('BackupLinkCopied'));
                    }),
                    CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                  ])),
        ]),
      ),
    ]);
  }
}
