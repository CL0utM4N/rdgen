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

class DeviceGroupPage extends StatefulWidget {
  const DeviceGroupPage({super.key});

  @override
  State<DeviceGroupPage> createState() => _DeviceGroupPageState();
}

class _DeviceGroupPageState extends State<DeviceGroupPage> {
  final ctl = ListCtl((q) => api.get('/device_group/list', params: q))..load();
  List<Row_> strategies = [];

  @override
  void initState() {
    super.initState();
    Lookups.strategies().then((s) => setState(() => strategies = s));
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _edit([Row_? row]) async {
    final f = <String, dynamic>{'id': row?['id'] ?? 0, 'name': row?['name'] ?? '', 'type': row?['type'] ?? 1, 'strategy_id': row?['strategy_id'] ?? 0};
    await showCtDialog(
      context,
      title: asInt(f['id']) == 0 ? T('Create') : T('Update'),
      width: 800,
      builder: (ctx, set) => Column(children: [
        FormItem(label: T('Name'), required: true, child: CtInput(value: '${f['name']}', onChanged: (v) => f['name'] = v)),
        FormItem(
          label: T('ClientPolicy'),
          child: CtSelect<int>(
            value: asInt(f['strategy_id']),
            options: [Opt(0, T('PolicyDefault')), for (final s in strategies) Opt(asInt(s['id']), '${s['name']}')],
            onChanged: (v) => set(() => f['strategy_id'] = v ?? 0),
          ),
        ),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          try {
            await api.post(asInt(f['id']) > 0 ? '/device_group/update' : '/device_group/create', body: f);
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
      await api.post('/device_group/delete', body: {'id': r['id']});
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
        Buttons([
          CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
          CtButton(T('Add'), tone: Tone.danger, onPressed: () => _edit()),
        ]),
      ],
      columns: () => [
        const Col('ID', prop: 'id'),
        Col(T('Name'), prop: 'name'),
        Col(T('ClientPolicy'),
            cell: (r, _) => asInt(r['strategy_id']) > 0
                ? CtTag(nameOf(strategies, r['strategy_id'], fallback: '-'))
                : Text(T('PolicyDefault'), style: TextStyle(color: c.muted))),
        Col(T('CreatedAt'), prop: 'created_at'),
        Col(T('UpdatedAt'), prop: 'updated_at'),
        Col(T('Actions'),
            width: 300,
            cell: (r, _) => Actions_([
                  CtButton(T('Enrol'), tone: Tone.primary, size: BtnSize.table, onPressed: () => showEnrol(context, r, strategies)),
                  CtButton(T('Edit'), size: BtnSize.table, onPressed: () => _edit(r)),
                  CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                ])),
      ],
    );
  }
}

/// Scripts that install and enrol clients into a device group.
Future<void> showEnrol(BuildContext context, Row_ group, List<Row_> strategies) async {
  final con = Console.I;
  final server = {
    'id': '${con.server['id_server'] ?? ''}'.isNotEmpty ? '${con.server['id_server']}' : Uri.parse(con.host.apiServer).host,
    'relay': '${con.server['relay_server'] ?? ''}',
    'api': '${con.server['api_server'] ?? ''}'.isNotEmpty ? '${con.server['api_server']}' : con.host.apiServer,
    'key': '${con.server['key'] ?? ''}',
  };
  var token = '', app = 'RustDesk', strategy = '', owner = '', os = 'windows', mode = 'install';
  final name = '${group['name'] ?? ''}';

  String ps(String s) => '"${s.replaceAllMapped(RegExp(r'[`"$]'), (m) => '`${m.group(0)}')}"';
  String sh(String s) => '"${s.replaceAllMapped(RegExp(r'[\\"$`]'), (m) => '\\${m.group(0)}')}"';
  String args(String Function(String) q) {
    final a = ['--assign', '--token', q(token.trim().isEmpty ? 'PASTE_API_KEY' : token.trim()), '--device_group_name', q(name)];
    if (strategy.isNotEmpty) a.addAll(['--strategy_name', q(strategy)]);
    if (owner.trim().isNotEmpty) a.addAll(['--user_name', q(owner.trim())]);
    return a.join(' ');
  }

  String options(String cmd, String Function(String) q, [String end = '']) => [
        ('custom-rendezvous-server', server['id']!),
        ('relay-server', server['relay']!),
        ('api-server', server['api']!),
        ('key', server['key']!),
      ].where((x) => x.$2.isNotEmpty).map((x) => '$cmd --option ${x.$1} ${q(x.$2)}$end').join('\n');

  const waitAndAssign = r'''# a fresh install takes a few seconds to get its ID
for ($i = 0; $i -lt 30 -and -not $id; $i++) {
  $id = (& $exe --get-id | Out-String).Trim()
  if (-not $id) { Start-Sleep -Seconds 2 }
}
if (-not $id) { throw "The client has no ID yet" }''';

  String script() {
    if (mode == 'install') {
      if (os == 'mac') {
        return '''# macOS asks the user to allow screen recording and accessibility, so install
# RustDesk from https://rustdesk.com, open it once and approve those first. Then run:
APP=/Applications/RustDesk.app/Contents/MacOS/RustDesk
${options('sudo "\$APP"', sh)}
sudo "\$APP" ${args(sh)}''';
      }
      if (os == 'linux') {
        return '''# Installs the standard RustDesk client (Debian/Ubuntu), points it at ${server['id']}
# and enrols it into $name. Run as root.
set -e
ARCH=\$(uname -m); [ "\$ARCH" = "arm64" ] && ARCH=aarch64
if ! command -v rustdesk >/dev/null; then
  URL=\$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep -o "https://[^\\"]*-\$ARCH\\.deb" | head -1)
  curl -fsSL "\$URL" -o /tmp/rustdesk.deb
  apt-get install -y /tmp/rustdesk.deb
  rm -f /tmp/rustdesk.deb
fi
${options('rustdesk', sh)}
sleep 5
rustdesk ${args(sh)}''';
      }
      return '''# Installs the standard RustDesk client, points it at ${server['id']} and enrols it
# into $name. Run as SYSTEM or an administrator, e.g. from Breeze RMM.
\$ErrorActionPreference = "Stop"
\$exe = Join-Path \$env:ProgramFiles "RustDesk\\rustdesk.exe"
if (-not (Test-Path \$exe)) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  \$rel = Invoke-RestMethod "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" -UseBasicParsing
  \$msi = \$rel.assets | Where-Object { \$_.name -like "*x86_64.msi" } | Select-Object -First 1
  \$file = Join-Path \$env:TEMP \$msi.name
  Invoke-WebRequest \$msi.browser_download_url -OutFile \$file -UseBasicParsing
  Start-Process msiexec.exe -ArgumentList "/i `"\$file`" /qn /norestart" -Wait
  Remove-Item \$file -ErrorAction SilentlyContinue
  for (\$i = 0; \$i -lt 30 -and -not (Test-Path \$exe); \$i++) { Start-Sleep -Seconds 2 }
}
# point it at our server
${options('& \$exe', ps, ' | Out-Null')}
$waitAndAssign
\$out = (& \$exe ${args(ps)} | Out-String).Trim()
if (\$out -ne "Done!") { throw "Enrolment failed: \$out" }
Write-Output "Installed and enrolled \$id into ${name.replaceAll(RegExp(r'[`"$]'), '')}"''';
    }
    final a = app.trim().isEmpty ? 'RustDesk' : app.trim();
    if (os == 'mac') return 'sudo ${sh('/Applications/$a.app/Contents/MacOS/$a')} ${args(sh)}';
    if (os == 'linux') return 'sudo ${a.toLowerCase()} ${args(sh)}';
    return '''# Enrols this PC into $name. Run as SYSTEM or an administrator after the client is installed.
\$exe = Join-Path \$env:ProgramFiles ${ps('$a\\$a.exe')}
if (-not (Test-Path \$exe)) { throw "\$exe not found, install the client first" }
$waitAndAssign
\$out = (& \$exe ${args(ps)} | Out-String).Trim()
if (\$out -ne "Done!") { throw "Enrolment failed: \$out" }
Write-Output "Enrolled \$id"''';
  }

  await showCtDialog(
    context,
    title: T('EnrolDevicesInto', {'name': name}),
    width: 860,
    builder: (ctx, set) {
      final text = script();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CtSegmented<String>(
            value: mode,
            options: [('install', T('EnrolModeInstall')), ('enrol', T('EnrolModeInstalled'))],
            onChanged: (v) => set(() => mode = v),
          ),
        ),
        Muted(mode == 'install' ? T('EnrolInstallIntro', {'server': server['id']}) : T('EnrolIntro'), padding: const EdgeInsets.symmetric(vertical: 12)),
        FormItem(
          label: T('ApiKey'),
          labelWidth: 150,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CtInput(value: token, placeholder: 'rdk_…', password: true, showPassword: true, onChanged: (v) => set(() => token = v)),
            const SizedBox(height: 4),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
              Muted(T('EnrolKeyHelp'), size: 12),
              CtButton(T('ApiKeys'), link: true, tone: Tone.primary, size: BtnSize.small, onPressed: () {
                Navigator.of(ctx).pop();
                Console.I.go('ApiKeys');
              }),
            ]),
          ]),
        ),
        if (mode == 'enrol')
          FormItem(label: T('ClientAppName'), labelWidth: 150, help: T('ClientAppNameHelp'), child: CtInput(value: app, placeholder: 'RustDesk', onChanged: (v) => set(() => app = v))),
        FormItem(
          label: T('ClientPolicy'),
          labelWidth: 150,
          child: CtSelect<String>(
            value: strategy.isEmpty ? null : strategy,
            clearable: true,
            placeholder: T('PolicyInherit'),
            options: [for (final s in strategies) Opt('${s['name']}', '${s['name']}')],
            onChanged: (v) => set(() => strategy = v ?? ''),
          ),
        ),
        FormItem(label: T('Owner'), labelWidth: 150, child: CtInput(value: owner, placeholder: T('Optional'), onChanged: (v) => set(() => owner = v))),
        CtTabs<String>(
          value: os,
          tabs: const [('windows', 'Windows (PowerShell)'), ('mac', 'macOS'), ('linux', 'Linux')],
          onChanged: (v) => set(() => os = v),
        ),
        if (server['key']!.isEmpty) CtAlert(T('EnrolNoServerKey'), type: AlertType.warning, margin: const EdgeInsets.only(bottom: 12)),
        Stack(children: [
          CodeBox(text, block: true),
          Positioned(top: 8, right: 8, child: CtButton(T('Copy'), size: BtnSize.small, icon: Icons.copy_outlined, onPressed: () => copyText(text))),
        ]),
        Muted(
          mode == 'install' ? (os == 'windows' ? T('EnrolInstallWindowsHelp') : T('EnrolUnixHelp')) : (os == 'windows' ? T('EnrolWindowsHelp') : T('EnrolUnixHelp')),
          padding: const EdgeInsets.only(top: 12),
        ),
      ]);
    },
  );
}

class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  late final ListCtl ctl;
  Map<String, dynamic> settings = {'required': false, 'last_check': 0, 'secret_configured': false};
  bool saving = false;
  Map<String, String> peerInfo = {};
  List<Row_> groups = [];
  final canSettings = can(['settings']);

  @override
  void initState() {
    super.initState();
    ctl = ListCtl((q) => api.get('/device_approval/list', params: q), query: {'status': 0}, pageSize: 20, decorate: _describe)..load();
    _loadSettings();
    Lookups.deviceGroups().then((g) => setState(() => groups = g));
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _describe(List<Row_> rows) async {
    final info = <String, String>{};
    await Future.wait(rows.map((r) async {
      try {
        final d = await api.get('/peer/list', params: {'id': r['peer_id'], 'page': 1, 'page_size': 10}, quiet: true);
        for (final p in rowsOf(d)) {
          if (p['id'] == r['peer_id']) {
            info['${r['peer_id']}'] = [p['hostname'], p['username'], p['os']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
          }
        }
      } catch (_) {}
    }));
    peerInfo = info;
  }

  Future<void> _loadSettings() async {
    try {
      final d = await api.get('/device_approval/settings', quiet: true);
      setState(() => settings = Map<String, dynamic>.from(d as Map));
    } catch (_) {}
  }

  Future<void> _saveRequired(bool on) async {
    if (on && !await confirm(context, T('RequireApprovalConfirm'))) return;
    setState(() => saving = true);
    try {
      final d = await api.post('/device_approval/settings', body: {'required': on});
      Toasts.success(on ? T('ApprovalOnApproved', {'n': d['approved']}) : T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
    if (mounted) setState(() => saving = false);
    _loadSettings();
  }

  Future<void> _approve(Row_ r) async {
    int? group;
    await showCtDialog(
      context,
      title: T('ApproveDevice', {'id': r['peer_id']}),
      width: 520,
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FormItem(
          label: T('DeviceGroup'),
          labelWidth: 130,
          child: CtSelect<int>(
            value: group,
            clearable: true,
            filterable: true,
            placeholder: T('KeepCurrentGroup'),
            options: [for (final g in groups) Opt(asInt(g['id']), '${g['name']}')],
            onChanged: (v) => set(() => group = v),
          ),
        ),
        Muted(T('ApproveDeviceHelp')),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Approve'), tone: Tone.success, onPressed: () async {
          try {
            await api.post('/device_approval/decide', body: {'id': r['id'], 'approve': true, 'device_group_id': group ?? 0});
            Toasts.success(T('DeviceApproved'));
            if (ctx.mounted) Navigator.of(ctx).pop();
            ctl.load();
          } catch (_) {}
        }),
      ],
    );
  }

  Future<void> _reject(Row_ r) async {
    try {
      await api.post('/device_approval/decide', body: {'id': r['id'], 'approve': false});
      ctl.load();
    } catch (_) {}
  }

  Future<void> _del(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('Delete')}))) return;
    try {
      await api.post('/device_approval/delete', body: {'id': r['id']});
      ctl.load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final required = settings['required'] == true;
    final connected = settings['secret_configured'] == true && asInt(settings['last_check']) > 0;
    final pending = asInt((ctl.data is Map ? ctl.data['pending'] : 0));
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => PageColumn([
        CtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHead(
              T('DeviceApprovals'),
              help: T('DeviceApprovalsHelp'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                CtSwitch(value: required, loading: saving, onChanged: canSettings && !saving ? _saveRequired : null),
                const SizedBox(width: 8),
                Text(T('RequireApproval'), style: TextStyle(fontSize: 14, color: required ? c.primary : c.text2)),
              ]),
            ),
            if (required && !connected)
              CtAlert(T('ApprovalServerNotConnected'), description: T('ApprovalServerNotConnectedHelp'), type: AlertType.warning, margin: const EdgeInsets.only(top: 14))
            else if (required)
              Muted(T('ApprovalServerLastCheck', {'time': timeAgo(asInt(settings['last_check']))}), padding: const EdgeInsets.only(top: 14)),
          ]),
        ),
        QueryBar(children: [
          CtSegmented<int>(
            value: asInt(ctl.query['status']),
            options: [
              (0, pending > 0 ? '${T('Waiting')} ($pending)' : T('Waiting')),
              (1, T('Approved')),
              (2, T('Rejected')),
              (-1, T('All')),
            ],
            onChanged: (v) {
              ctl.query['status'] = v;
              ctl.filter();
            },
          ),
        ]),
        CtCard(
          child: CtTable(loading: ctl.loading, rows: ctl.list, columns: [
            const Col('ID', prop: 'peer_id', width: 130),
            Col(T('Device'),
                minWidth: 180,
                center: false,
                cell: (r, _) => peerInfo['${r['peer_id']}'] != null
                    ? Text(peerInfo['${r['peer_id']}']!)
                    : Text(T('NotReportedYet'), style: TextStyle(color: c.muted))),
            Col(T('FromIp'), prop: 'ip', width: 150),
            Col(T('LastSeen'), width: 150, cell: (r, _) => Text(asInt(r['last_seen']) > 0 ? timeAgo(asInt(r['last_seen'])) : '-')),
            Col(T('Status'),
                width: 200,
                cell: (r, _) {
                  final s = asInt(r['status']).clamp(0, 2);
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    CtTag([T('Waiting'), T('Approved'), T('Rejected')][s], tone: [Tone.warning, Tone.success, Tone.danger][s]),
                    if ('${r['decided_by'] ?? ''}'.isNotEmpty) Text('${r['decided_by']}', style: TextStyle(fontSize: 12, color: c.muted)),
                  ]);
                }),
            Col(T('Actions'),
                width: 280,
                cell: (r, _) => Actions_([
                      if (r['status'] != 1) CtButton(T('Approve'), tone: Tone.success, size: BtnSize.table, onPressed: () => _approve(r)),
                      if (r['status'] != 2) CtButton(T('Reject'), tone: Tone.warning, size: BtnSize.table, onPressed: () => _reject(r)),
                      CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                    ])),
          ]),
        ),
        CtPagination(total: ctl.total, page: ctl.page, pageSize: ctl.pageSize, onChange: ctl.setPage),
      ]),
    );
  }
}

/// The client policy settings, grouped as on the web.
class PolicyOption {
  final String key;
  final String label;
  final String type;
  final List<(String, String)> choices;
  final String? placeholder;
  final String? help;
  const PolicyOption(this.key, this.label, this.type, {this.choices = const [], this.placeholder, this.help});
}

const policyGroups = <(String, List<PolicyOption>)>[
  (
    'PolicyGroupPermissions',
    [
      PolicyOption('access-mode', 'Permissions preset', 'select', choices: [('full', 'Full access'), ('view', 'View only'), ('custom', 'Custom (the switches below)')]),
      PolicyOption('enable-keyboard', 'Keyboard and mouse', 'switch'),
      PolicyOption('enable-clipboard', 'Clipboard', 'switch'),
      PolicyOption('enable-file-transfer', 'File transfer', 'switch'),
      PolicyOption('enable-audio', 'Audio', 'switch'),
      PolicyOption('enable-camera', 'Camera', 'switch'),
      PolicyOption('enable-terminal', 'Terminal', 'switch'),
      PolicyOption('enable-remote-printer', 'Remote printer', 'switch'),
      PolicyOption('enable-tunnel', 'TCP tunnelling', 'switch'),
      PolicyOption('enable-remote-restart', 'Remote restart', 'switch'),
      PolicyOption('enable-record-session', 'Recording sessions', 'switch'),
      PolicyOption('enable-block-input', 'Blocking user input', 'switch'),
      PolicyOption('enable-privacy-mode', 'Privacy mode', 'switch'),
      PolicyOption('allow-remote-config-modification', 'Changing settings remotely', 'switch'),
    ]
  ),
  (
    'PolicyGroupSecurity',
    [
      PolicyOption('approve-mode', 'Accepting connections', 'select',
          choices: [('password', 'Password only'), ('click', 'Click to accept only'), ('both', 'Password or click (RustDesk default)')]),
      PolicyOption('verification-method', 'Passwords accepted', 'select',
          choices: [('use-temporary-password', 'One-time password'), ('use-permanent-password', 'Permanent password'), ('use-both-passwords', 'Both')]),
      PolicyOption('temporary-password-length', 'One-time password length', 'select', choices: [('6', '6'), ('8', '8'), ('10', '10')]),
      PolicyOption('allow-numeric-one-time-password', 'Numbers-only one-time password', 'switch'),
      PolicyOption('whitelist', 'IP whitelist', 'text',
          placeholder: '203.0.113.10,198.51.100.0/24', help: 'Comma separated IPs or ranges allowed to connect. Blocked attempts appear under Security alerts.'),
      PolicyOption('enable-trusted-devices', 'Trusted devices (skip 2FA)', 'switch'),
      PolicyOption('allow-only-conn-window-open', 'Only while the RustDesk window is open', 'switch'),
      PolicyOption('allow-auto-disconnect', 'Disconnect idle sessions', 'switch'),
      PolicyOption('auto-disconnect-timeout', 'Idle timeout (minutes)', 'text', placeholder: '10'),
      PolicyOption('allow-auto-record-incoming', 'Record incoming sessions automatically', 'switch'),
    ]
  ),
  (
    'PolicyGroupNetwork',
    [
      PolicyOption('enable-lan-discovery', 'LAN discovery', 'switch'),
      PolicyOption('direct-server', 'Direct IP access', 'switch'),
      PolicyOption('direct-access-port', 'Direct IP access port', 'text', placeholder: '21118'),
      PolicyOption('enable-udp-punch', 'UDP hole punching', 'switch'),
      PolicyOption('enable-ipv6-punch', 'IPv6 P2P', 'switch'),
      PolicyOption('allow-websocket', 'Use WebSocket', 'switch'),
      PolicyOption('disable-udp', 'Disable UDP (TCP only)', 'switch'),
    ]
  ),
  (
    'PolicyGroupOther',
    [
      PolicyOption('allow-remove-wallpaper', 'Remove wallpaper during sessions', 'switch'),
      PolicyOption('keep-awake-during-incoming-sessions', 'Keep awake during sessions', 'switch'),
      PolicyOption('enable-hwcodec', 'Hardware encoding', 'switch'),
      PolicyOption('enable-abr', 'Adaptive bitrate', 'switch'),
      PolicyOption('enable-directx-capture', 'DirectX capture', 'switch'),
      PolicyOption('allow-auto-update', 'Automatic updates', 'switch'),
      PolicyOption('enable-check-update', 'Check for updates', 'switch'),
    ]
  ),
];

PolicyOption? policyOption(String key) {
  for (final g in policyGroups) {
    for (final o in g.$2) {
      if (o.key == key) return o;
    }
  }
  return null;
}

class StrategyPage extends StatefulWidget {
  const StrategyPage({super.key});

  @override
  State<StrategyPage> createState() => _StrategyPageState();
}

class _StrategyPageState extends State<StrategyPage> {
  List<Row_> list = [];
  int defaultId = 0;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await api.get('/strategy/list');
      setState(() {
        list = rowsOf(d);
        defaultId = asInt(d['default_id']);
      });
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String _describe(String k, dynamic v) {
    final o = policyOption(k);
    final label = o?.label ?? k;
    if (v == 'Y') return '$label: ${T('On')}';
    if (v == 'N') return '$label: ${T('Off')}';
    final choice = o?.choices.where((c) => c.$1 == v).firstOrNull;
    if (choice != null) return '$label: ${choice.$2}';
    if (k == 'approve-mode' && v == '') return '$label: Password or click';
    return '$label: $v';
  }

  Future<void> _saveDefault(int? id) async {
    try {
      await api.post('/strategy/default', body: {'id': id ?? 0});
      Toasts.success(T('OperationSuccess'));
    } catch (_) {}
    _load();
  }

  Future<void> _edit([Row_? row]) async {
    final name = TextEditingController(text: '${row?['name'] ?? ''}');
    final note = TextEditingController(text: '${row?['note'] ?? ''}');
    final opts = <String, String?>{};
    final extra = <(TextEditingController, TextEditingController)>[];
    for (final g in policyGroups) {
      for (final o in g.$2) {
        if (o.type == 'switch') opts[o.key] = 'unset';
      }
    }
    final given = Map<String, dynamic>.from(row?['options'] as Map? ?? {});
    given.forEach((k, v) {
      if (k == 'approve-mode' && v == '') {
        opts[k] = 'both';
      } else if (policyOption(k) != null) {
        opts[k] = '$v';
      } else {
        extra.add((TextEditingController(text: k), TextEditingController(text: '$v')));
      }
    });
    var saving = false;
    await showCtDialog(
      context,
      title: row == null ? T('Create') : T('Update'),
      width: 860,
      builder: (ctx, set) {
        final c = ctx.ct;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormItem(label: T('Name'), labelWidth: 250, required: true, child: CtInput(controller: name, maxLength: 100)),
          FormItem(label: T('Note'), labelWidth: 250, child: CtInput(controller: note, maxLength: 500)),
          Muted(T('PolicyUnsetHelp'), padding: const EdgeInsets.only(bottom: 8)),
          for (final g in policyGroups) ...[
            Padding(padding: const EdgeInsets.only(top: 10, bottom: 12), child: Text(T(g.$1), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
            for (final o in g.$2)
              FormItem(
                label: o.label,
                labelWidth: 250,
                help: o.help,
                child: o.type == 'switch'
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: CtSegmented<String>(
                          small: true,
                          value: opts[o.key],
                          options: [('unset', T('NotSet')), ('Y', T('On')), ('N', T('Off'))],
                          onChanged: (v) => set(() => opts[o.key] = v),
                        ),
                      )
                    : o.type == 'select'
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: CtSelect<String>(
                              width: 320,
                              value: opts[o.key],
                              clearable: true,
                              placeholder: T('NotSet'),
                              options: [for (final ch in o.choices) Opt(ch.$1, ch.$2)],
                              onChanged: (v) => set(() => opts[o.key] = v),
                            ),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: CtInput(width: 320, value: opts[o.key] ?? '', clearable: true, placeholder: o.placeholder, onChanged: (v) => opts[o.key] = v),
                          ),
              ),
          ],
          Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(T('PolicyOtherOptions'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
          Muted(T('PolicyOtherOptionsHelp'), padding: const EdgeInsets.only(bottom: 10)),
          for (var i = 0; i < extra.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: CtInput(controller: extra[i].$1, placeholder: 'option-name')),
                const SizedBox(width: 8),
                Expanded(child: CtInput(controller: extra[i].$2, placeholder: 'value')),
                const SizedBox(width: 8),
                CtButton('', icon: Icons.delete_outline, onPressed: () => set(() => extra.removeAt(i))),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: CtButton(T('AddOption'), onPressed: () => set(() => extra.add((TextEditingController(), TextEditingController())))),
          ),
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, loading: saving, onPressed: () async {
          final options = <String, String>{};
          opts.forEach((k, v) {
            if (v == null || v == '' || v == 'unset') return;
            options[k] = k == 'approve-mode' && v == 'both' ? '' : v;
          });
          for (final e in extra) {
            if (e.$1.text.trim().isNotEmpty) options[e.$1.text.trim()] = e.$2.text;
          }
          set(() => saving = true);
          try {
            await api.post('/strategy/save', body: {'id': row?['id'] ?? 0, 'name': name.text, 'note': note.text, 'options': options});
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
    if (!await confirm(context, T('PolicyDeleteConfirm', {'name': r['name']}), confirmText: T('Delete'))) return;
    try {
      await api.post('/strategy/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return PageColumn([
      CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CardHead(T('ClientPolicies'), help: T('ClientPoliciesHelp'), trailing: CtButton(T('Add'), tone: Tone.primary, onPressed: () => _edit())),
          const SizedBox(height: 16),
          QueryField(
            T('PolicyDefaultFor'),
            CtSelect<int>(
              value: defaultId,
              options: [Opt(0, T('None')), for (final s in list) Opt(asInt(s['id']), '${s['name']}')],
              onChanged: _saveDefault,
            ),
            width: 260,
          ),
        ]),
      ),
      CtCard(
        child: CtTable(loading: loading, rows: list, columns: [
          Col(T('Name'),
              minWidth: 160,
              center: false,
              cell: (r, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (r['id'] == defaultId) CtTag(T('Default'), small: true, tone: Tone.success),
                    ]),
                    if ('${r['note'] ?? ''}'.isNotEmpty) Text('${r['note']}', style: TextStyle(color: c.muted, fontSize: 12)),
                  ])),
          Col(T('Settings'),
              minWidth: 280,
              center: false,
              cell: (r, _) {
                final o = Map<String, dynamic>.from(r['options'] as Map? ?? {});
                if (o.isEmpty) return Text('-', style: TextStyle(color: c.muted));
                return Wrap(spacing: 4, runSpacing: 4, children: [for (final e in o.entries) CtTag(_describe(e.key, e.value), small: true, tone: Tone.info)]);
              }),
          Col(T('UsedBy'), width: 170, cell: (r, _) => Text(T('PolicyUsage', {'devices': r['devices'], 'groups': r['groups']}))),
          Col(T('Actions'),
              width: 180,
              cell: (r, _) => Actions_([
                    CtButton(T('Edit'), size: BtnSize.table, onPressed: () => _edit(r)),
                    CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                  ])),
        ]),
      ),
    ]);
  }
}
