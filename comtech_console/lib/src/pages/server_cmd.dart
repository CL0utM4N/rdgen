import 'package:flutter/material.dart';

import '../console.dart';
import '../i18n.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/basic.dart';
import '../widgets/dialog.dart';
import '../widgets/form.dart';
import '../widgets/table.dart';

const idTarget = '21115', relayTarget = '21117';

Future<String?> sendCmd(String cmd, String target, {String option = '', bool quiet = false}) async {
  try {
    final d = await api.post('/rustdesk/sendCmd', body: {'cmd': cmd, 'option': option, 'target': target}, quiet: quiet);
    return d == null ? '' : '$d';
  } catch (_) {
    return null;
  }
}

class ServerCmdPage extends StatefulWidget {
  const ServerCmdPage({super.key});

  @override
  State<ServerCmdPage> createState() => _ServerCmdPageState();
}

class _ServerCmdPageState extends State<ServerCmdPage> {
  bool idOk = false, relayOk = false, mustLoginOk = false;
  String tab = 'Simple';
  final ctl = ListCtl((q) => api.get('/rustdesk/cmdList', params: q))..load();
  final relayKey = GlobalKey<_SimpleCardState>();

  @override
  void initState() {
    super.initState();
    _checkId();
    _checkRelay();
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _checkId() async {
    final r = await sendCmd('h', idTarget, quiet: true);
    setState(() {
      idOk = r != null && r.isNotEmpty;
      mustLoginOk = idOk && r!.split('\n').any((l) => l.contains('must-login'));
    });
  }

  Future<void> _checkRelay() async {
    final r = await sendCmd('h', relayTarget, quiet: true);
    setState(() => relayOk = r != null && r.isNotEmpty);
  }

  bool canSend(String target) => target == idTarget ? idOk : (target == relayTarget ? relayOk : false);

  Future<void> _edit([Row_? row]) async {
    final f = <String, dynamic>{
      if (row != null) 'id': row['id'],
      'cmd': row?['cmd'] ?? '',
      'alias': row?['alias'] ?? '',
      'option': row?['option'] ?? '',
      'target': row?['target'] ?? '',
      'explain': row?['explain'] ?? '',
    };
    await showCtDialog(
      context,
      title: row == null ? T('Create') : T('Update'),
      width: 600,
      builder: (ctx, set) {
        Widget text(String k) => FormItem(label: k, labelWidth: 150, child: CtInput(value: '${f[k]}', onChanged: (v) => f[k] = v));
        return Column(children: [
          text('cmd'),
          text('alias'),
          text('option'),
          FormItem(
            label: 'target',
            labelWidth: 150,
            child: CtRadios<String>(
              value: '${f['target']}',
              options: const [(idTarget, 'id_server'), (relayTarget, 'relay_server')],
              onChanged: (v) => set(() => f['target'] = v),
            ),
          ),
          text('explain'),
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          if ('${f['cmd']}'.isEmpty) return Toasts.error(T('ParamRequired', {'param': 'cmd'}));
          try {
            await api.post(row != null ? '/rustdesk/cmdUpdate' : '/rustdesk/cmdCreate', body: f);
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
      await api.post('/rustdesk/cmdDelete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  Future<void> _send(Row_ r) async {
    final cmd = TextEditingController(text: '${r['cmd'] ?? ''}');
    final option = TextEditingController();
    final target = '${r['target']}';
    final example = '${r['cmd'] ?? ''} ${r['option'] ?? ''}'.trim();
    var result = '';
    await showCtDialog(
      context,
      title: T('SendCmd'),
      width: 760,
      builder: (ctx, set) {
        final ok = canSend(target);
        return Column(children: [
          FormItem(label: 'cmd', labelWidth: 150, child: CtInput(controller: cmd, enabled: ok)),
          FormItem(
            label: 'option',
            labelWidth: 150,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CtInput(controller: option, enabled: ok),
              if (example.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Example: '),
                    TextSpan(text: example, style: TextStyle(color: ctx.ct.primary)),
                  ])),
                ),
            ]),
          ),
          FormItem(
            labelWidth: 150,
            label: '',
            child: Align(
              alignment: Alignment.centerLeft,
              child: CtButton(T('Send'), tone: Tone.primary, onPressed: !ok
                  ? null
                  : () async {
                      final r = await sendCmd(cmd.text, target, option: option.text);
                      if (r != null) {
                        Toasts.success(T('OperationSuccess'));
                        set(() => result = r);
                      }
                    }),
            ),
          ),
          FormItem(label: T('Result'), labelWidth: 150, child: CodeBox(result.isEmpty ? ' ' : result, block: true)),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    Widget status(String label, bool ok, VoidCallback refresh) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Text('$label ${T('Status')}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            ok ? CtTag(T('Available'), tone: Tone.success) : CtTag(T('NotAvailable'), tone: Tone.danger),
            const SizedBox(width: 8),
            CtButton(T('Refresh'), link: true, tone: Tone.primary, onPressed: refresh),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(T('ServerCmdTips', {'wiki': 'WIKI'}).replaceAll(RegExp(r'<[^>]+>'), ''), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          CtButton('WIKI', link: true, tone: Tone.primary, onPressed: () => openUrl('https://github.com/lejianwen/rustdesk-api/wiki/Rustdesk-Command')),
        ]),
      ),
      status('ID', idOk, _checkId),
      status('RELAY', relayOk, _checkRelay),
      const SizedBox(height: 8),
      CtTabs<String>(value: tab, tabs: [('Simple', T('Simple')), ('Advanced', T('Advanced'))], onChanged: (v) => setState(() => tab = v)),
      if (tab == 'Simple')
        Wrap(spacing: 16, runSpacing: 16, children: [
          _SimpleCard(key: relayKey, title: 'RELAY_SERVERS', canSend: idOk, kind: _Kind.relayServers),
          _SimpleCard(title: 'ALWAYS_USE_RELAY', canSend: idOk, kind: _Kind.alwaysRelay, onSaved: () => relayKey.currentState?.save()),
          _SimpleCard(title: 'MUST_LOGIN', canSend: mustLoginOk && idOk, kind: _Kind.mustLogin),
          _SimpleCard(title: 'USAGE', canSend: relayOk, kind: _Kind.usage),
          _SimpleCard(title: 'BLOCK_LIST', canSend: relayOk, kind: _Kind.blocklist),
          _SimpleCard(title: 'BLACK_LIST', canSend: relayOk, kind: _Kind.blacklist),
        ])
      else
        ListenableBuilder(
          listenable: ctl,
          builder: (context, _) => PageColumn([
            QueryBar(children: [
              Buttons([
                CtButton(T('Filter'), tone: Tone.primary, onPressed: ctl.filter),
                CtButton(T('Add'), tone: Tone.danger, onPressed: () => _edit()),
                CtButton('${T('Send')} To Id', tone: Tone.success, onPressed: idOk ? () => _send({'cmd': '', 'option': '', 'target': idTarget}) : null),
                CtButton('${T('Send')} To Relay', tone: Tone.success, onPressed: relayOk ? () => _send({'cmd': '', 'option': '', 'target': relayTarget}) : null),
              ]),
            ]),
            CtCard(
              child: CtTable(loading: ctl.loading, rows: ctl.list, columns: [
                const Col('cmd', prop: 'cmd'),
                const Col('alias', prop: 'alias'),
                const Col('option', prop: 'option'),
                const Col('explain', prop: 'explain'),
                Col('actions',
                    minWidth: 220,
                    cell: (r, _) => Actions_([
                          CtButton(T('Send'), tone: Tone.success, size: BtnSize.table, onPressed: canSend('${r['target']}') ? () => _send(r) : null),
                          if (asInt(r['id']) > 0) CtButton(T('Edit'), tone: Tone.primary, size: BtnSize.table, onPressed: () => _edit(r)),
                          if (asInt(r['id']) > 0) CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                        ])),
              ]),
            ),
          ]),
        ),
      if (tab == 'Simple') SizedBox(height: 0, child: Container(color: c.bg)),
    ]);
  }
}

enum _Kind { relayServers, alwaysRelay, mustLogin, usage, blocklist, blacklist }

class _SimpleCard extends StatefulWidget {
  final String title;
  final bool canSend;
  final _Kind kind;
  final VoidCallback? onSaved;
  const _SimpleCard({super.key, required this.title, required this.canSend, required this.kind, this.onSaved});

  @override
  State<_SimpleCard> createState() => _SimpleCardState();
}

class _SimpleCardState extends State<_SimpleCard> {
  bool loading = false;
  final option = TextEditingController();
  bool flag = false;
  List<String> list = [];
  List<List<String>> usage = [];

  @override
  void initState() {
    super.initState();
    if (widget.canSend) get();
  }

  @override
  void didUpdateWidget(covariant _SimpleCard old) {
    super.didUpdateWidget(old);
    if (widget.canSend && !old.canSend) get();
  }

  @override
  void dispose() {
    option.dispose();
    super.dispose();
  }

  String get listCmd => widget.kind == _Kind.blocklist ? 'blocklist' : 'blacklist';

  Future<void> get() async {
    setState(() => loading = true);
    switch (widget.kind) {
      case _Kind.relayServers:
        final r = await sendCmd('rs', idTarget);
        if (r != null) option.text = r.split('\n').where((l) => l.isNotEmpty).join(',');
      case _Kind.alwaysRelay:
        final r = await sendCmd('aur', idTarget);
        if (r != null) flag = r.trim() == 'ALWAYS_USE_RELAY: true';
      case _Kind.mustLogin:
        final r = await sendCmd('ml', idTarget);
        if (r != null) flag = r.trim() == 'MUST_LOGIN: true';
      case _Kind.usage:
        final r = await sendCmd('u', relayTarget);
        if (r != null) usage = r.split('\n').where((l) => l.isNotEmpty).map((l) => l.split(' ')).toList();
      case _Kind.blocklist:
      case _Kind.blacklist:
        final r = await sendCmd(listCmd, relayTarget);
        if (r != null) list = r.split('\n').where((l) => l.isNotEmpty).toList();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    String? r;
    switch (widget.kind) {
      case _Kind.relayServers:
        r = await sendCmd('rs', idTarget, option: option.text);
      case _Kind.alwaysRelay:
        r = await sendCmd('aur', idTarget, option: flag ? 'Y' : 'N');
      case _Kind.mustLogin:
        r = await sendCmd('ml', idTarget, option: flag ? 'Y' : 'N');
      default:
        return;
    }
    if (r != null) {
      Toasts.success(T('OperationSuccess'));
      widget.onSaved?.call();
    }
  }

  Future<void> _listForm(bool add) async {
    final input = TextEditingController();
    await showCtDialog(
      context,
      title: add ? 'add' : 'delete',
      width: 520,
      builder: (ctx, set) => FormItem(
        label: 'IP',
        labelWidth: 100,
        help: add ? 'Separate multiple IPs with |' : 'Separate multiple IPs with |, or enter all to remove every entry',
        child: CtInput(controller: input),
      ),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Submit'), tone: Tone.primary, onPressed: () async {
          final r = await sendCmd('$listCmd-${add ? 'add' : 'remove'}', relayTarget, option: input.text);
          if (r != null) {
            Toasts.success(T('OperationSuccess'));
            get();
          }
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final ok = widget.canSend;
    Widget body;
    switch (widget.kind) {
      case _Kind.relayServers:
        body = CtInput(controller: option, enabled: ok);
      case _Kind.alwaysRelay:
      case _Kind.mustLogin:
        body = Align(alignment: Alignment.centerLeft, child: CtSwitch(value: flag, onChanged: ok ? (v) => setState(() => flag = v) : null));
      case _Kind.usage:
        body = CtTable(small: true, rows: [for (final u in usage) {for (var i = 0; i < u.length; i++) '$i': u[i]}], columns: const [
          Col('IP', prop: '0', minWidth: 60),
          Col('TIME', prop: '1', minWidth: 60),
          Col('TOTAL', prop: '2', minWidth: 60),
          Col('HIGHEST', prop: '3', minWidth: 60),
          Col('AVG', prop: '4', minWidth: 60),
          Col('SPEED', prop: '5', minWidth: 60),
        ]);
      case _Kind.blocklist:
      case _Kind.blacklist:
        body = CtInput(key: ValueKey(list.join('|')), value: list.join('|'), rows: 5, enabled: ok);
    }
    final isList = widget.kind == _Kind.blocklist || widget.kind == _Kind.blacklist;
    return SizedBox(
      width: widget.kind == _Kind.usage ? 520 : 340,
      child: Container(
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(ctRadius)),
        child: Loading(
          loading: loading,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
              child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                body,
                const SizedBox(height: 14),
                Buttons([
                  CtButton(T('Refresh'), onPressed: ok ? get : null),
                  if (isList) ...[
                    CtButton(T('Add'), tone: Tone.primary, onPressed: ok ? () => _listForm(true) : null),
                    CtButton(T('Delete'), tone: Tone.danger, onPressed: ok ? () => _listForm(false) : null),
                  ] else if (widget.kind != _Kind.usage)
                    CtButton(T('Save'), tone: Tone.primary, onPressed: ok ? save : null),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
