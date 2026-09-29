import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../console.dart';
import '../i18n.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/basic.dart';
import '../widgets/table.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Row_> peers = [], groups = [], users = [], logins = [], builds = [];
  int buildTotal = 0;
  bool loading = false;
  int updatedAt = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() {});
      if (DateTime.now().millisecondsSinceEpoch - updatedAt > 60000) _load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<PageResult?> _get(String path, int size) async {
    try {
      return PageResult.from(await api.get(path, params: {'page': 1, 'page_size': size}, quiet: true));
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    // only ask for what the user's role can see
    final r = await Future.wait([
      can(['peers.view']) ? _get('/peer/list', 1000) : Future.value(null),
      _get('/device_group/list', 1000),
      _get('/user/list', 1000),
      can(['logs']) ? _get('/login_log/list', 6) : Future.value(null),
      can(['client_builder']) ? _get('/client_build/list', 5) : Future.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0] != null) peers = r[0]!.list;
      if (r[1] != null) groups = r[1]!.list;
      if (r[2] != null) users = r[2]!.list;
      if (r[3] != null) logins = r[3]!.list;
      if (r[4] != null) {
        builds = r[4]!.list;
        buildTotal = r[4]!.total;
      }
      loading = false;
      updatedAt = DateTime.now().millisecondsSinceEpoch;
    });
  }

  String pct(int n, int total) => total == 0 ? '0%' : '${(n / total * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final con = Console.I;
    final online = peers.where((p) => isOnline(p['last_online_time'])).length;
    final h = DateTime.now().hour;
    final greeting = T(h < 12 ? 'GoodMorning' : (h < 18 ? 'GoodAfternoon' : 'GoodEvening'));

    final stats = [
      if (can(['peers.view'])) ('TotalDevices', Icons.desktop_windows_outlined, '${peers.length}', '', 'Peer'),
      if (can(['peers.view'])) ('Online', Icons.check_circle_outline, '$online', peers.isEmpty ? '' : pct(online, peers.length), 'Peer'),
      if (can(['device_groups'])) ('DeviceGroups', Icons.folder_copy_outlined, '${groups.length}', '', 'DeviceGroup'),
      if (can(['users'])) ('Users', Icons.person_outline, '${users.length}', '', 'UserList'),
      if (can(['client_builder'])) ('ClientBuilds', Icons.inventory_2_outlined, '$buildTotal', '', 'ClientBuild'),
    ];

    final os = <String, int>{};
    for (final p in peers) {
      final n = osName('${p['os'] ?? ''}');
      os[n] = (os[n] ?? 0) + 1;
    }
    final osList = os.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final recent = [...peers]..sort((a, b) => asInt(b['last_online_time']).compareTo(asInt(a['last_online_time'])));

    Widget panel(String title, Widget body, {Widget? trailing}) => Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(ctRadius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              if (trailing != null) trailing,
            ]),
            const SizedBox(height: 14),
            body,
          ]),
        );
    Widget viewAll(String route) => CtButton(T('ViewAll'), link: true, tone: Tone.primary, onPressed: () => con.go(route));
    Widget empty([bool small = false]) => Padding(
          padding: EdgeInsets.symmetric(vertical: small ? 14 : 30),
          child: Center(child: Muted(T('NoDevicesYet'))),
        );

    final devicesPanel = panel(
      T('RecentDevices'),
      trailing: viewAll('Peer'),
      recent.isEmpty
          ? empty()
          : Column(children: [
              for (var i = 0; i < recent.length && i < 7; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.border))),
                  child: Row(children: [
                    Dot(isOnline(recent[i]['last_online_time']) ? c.success : c.borderStrong, glow: isOnline(recent[i]['last_online_time'])),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_label(recent[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text('${recent[i]['id']} · ${osName('${recent[i]['os'] ?? ''}')}', style: TextStyle(fontSize: 12, color: c.muted)),
                      ]),
                    ),
                    if (asInt(recent[i]['group_id']) > 0)
                      Padding(padding: const EdgeInsets.only(right: 12), child: CtTag(nameOf(groups, recent[i]['group_id']), small: true, plain: true)),
                    SizedBox(
                      width: 80,
                      child: Text(asInt(recent[i]['last_online_time']) > 0 ? timeAgo(asInt(recent[i]['last_online_time'])) : '-',
                          textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.muted)),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: T('Connect'),
                      child: IconButton(
                        icon: Icon(Icons.play_circle_outline, size: 20, color: c.success),
                        splashRadius: 16,
                        onPressed: () => con.host.connect('${recent[i]['id']}'),
                      ),
                    ),
                  ]),
                ),
            ]),
    );

    final fleetPanel = panel(
      T('FleetStatus'),
      trailing: Text('$online/${peers.length} ${T('OnlineLower')}', style: TextStyle(fontSize: 13, color: c.muted)),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CtBar(fraction: peers.isEmpty ? 0 : online / peers.length),
        const SizedBox(height: 10),
        Row(children: [
          Dot(c.success),
          const SizedBox(width: 6),
          Text('${T('Online')} $online', style: TextStyle(fontSize: 13, color: c.text2)),
          const SizedBox(width: 18),
          Dot(c.borderStrong),
          const SizedBox(width: 6),
          Text('${T('Offline')} ${peers.length - online}', style: TextStyle(fontSize: 13, color: c.text2)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 10),
          child: Text(T('Platforms'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
        ),
        if (osList.isEmpty) empty(true),
        for (final o in osList)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 70, child: Text(o.key, style: TextStyle(fontSize: 13, color: c.text2))),
              const SizedBox(width: 10),
              Expanded(child: CtBar(fraction: o.value / peers.length, height: 6, color: c.primary)),
              const SizedBox(width: 10),
              SizedBox(width: 24, child: Text('${o.value}', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: c.muted))),
            ]),
          ),
      ]),
    );

    final loginsPanel = panel(
      T('RecentLogins'),
      trailing: viewAll('LoginLog'),
      CtTable(small: true, rows: logins, columns: [
        Col(T('User'), minWidth: 110, cell: (r, _) => Text(_user(r['user_id']))),
        Col(T('Client'), prop: 'client', minWidth: 90),
        const Col('IP', prop: 'ip', minWidth: 120),
        Col(T('Time'), prop: 'created_at', minWidth: 170),
      ]),
    );

    final buildsPanel = panel(
      T('ClientBuilds'),
      trailing: viewAll('ClientBuild'),
      builds.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Center(child: Muted(T('NoBuildsYet'))))
          : Column(children: [
              for (var i = 0; i < builds.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.border))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text.rich(TextSpan(children: [
                          TextSpan(text: '${builds[i]['app_name']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                          TextSpan(text: ' · ${builds[i]['platform']}', style: TextStyle(color: c.muted, fontSize: 13)),
                        ])),
                        Text('${builds[i]['created_at'] ?? ''}', style: TextStyle(fontSize: 12, color: c.muted)),
                      ]),
                    ),
                    CtTag(T('BuildStatus_${builds[i]['status']}'), small: true, tone: buildTone('${builds[i]['status']}')),
                  ]),
                ),
            ]),
    );

    final left = [if (can(['peers.view'])) devicesPanel, if (can(['logs'])) loginsPanel];
    final right = [if (can(['peers.view'])) fleetPanel, if (can(['client_builder'])) buildsPanel];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('$greeting, ${con.displayName}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
        Text(T('UpdatedAgo', {'param': updatedAt == 0 ? '-' : timeAgo(updatedAt ~/ 1000)}), style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(width: 10),
        CtIconButton(Icons.refresh, size: 32, spinning: loading, onPressed: loading ? null : _load),
      ]),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, box) {
        final n = stats.length;
        if (n == 0) return const SizedBox();
        final perRow = (box.maxWidth / 156).floor().clamp(1, n);
        final w = (box.maxWidth - 16 * (perRow - 1)) / perRow;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          for (final s in stats) SizedBox(width: w, child: _Stat(label: T(s.$1), icon: s.$2, value: s.$3, sub: s.$4, onTap: () => con.go(s.$5))),
        ]);
      }),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 960) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap([...left, ...right]));
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap(left))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _gap(right))),
        ]);
      }),
    ]);
  }

  List<Widget> _gap(List<Widget> ws) => [
        for (var i = 0; i < ws.length; i++) ...[if (i > 0) const SizedBox(height: 16), ws[i]],
      ];

  String _label(Row_ p) {
    for (final k in ['alias', 'hostname', 'id']) {
      if ('${p[k] ?? ''}'.isNotEmpty) return '${p[k]}';
    }
    return '';
  }

  String _user(dynamic id) {
    for (final u in users) {
      if (u['id'] == id) return '${u['nickname'] ?? ''}'.isNotEmpty ? '${u['nickname']}' : '${u['username']}';
    }
    return id == null || id == 0 ? '-' : '#$id';
  }
}

Tone buildTone(String s) => switch (s) {
      'success' => Tone.success,
      'failure' || 'error' => Tone.danger,
      'in_progress' => Tone.warning,
      _ => Tone.info,
    };

class _Stat extends StatefulWidget {
  final String label;
  final IconData icon;
  final String value;
  final String sub;
  final VoidCallback onTap;
  const _Stat({required this.label, required this.icon, required this.value, required this.sub, required this.onTap});

  @override
  State<_Stat> createState() => _StatState();
}

class _StatState extends State<_Stat> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: hover ? c.borderStrong : c.border),
            borderRadius: BorderRadius.circular(ctRadius),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted))),
              Icon(widget.icon, size: 18, color: c.muted),
            ]),
            const SizedBox(height: 10),
            Text.rich(TextSpan(children: [
              TextSpan(text: widget.value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
              if (widget.sub.isNotEmpty) TextSpan(text: '  ${widget.sub}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.success)),
            ])),
          ]),
        ),
      ),
    );
  }
}
