import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../console.dart';
import '../i18n.dart';
import '../save.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/basic.dart';
import '../widgets/dialog.dart';
import '../widgets/form.dart';
import '../widgets/table.dart';

/// The QR code and key for setting up an authenticator app. It's drawn here,
/// so the secret isn't sent anywhere else.
class MfaQr extends StatelessWidget {
  final String uri;
  final String secret;
  const MfaQr({super.key, required this.uri, required this.secret});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final grouped = RegExp(r'.{1,4}').allMatches(secret).map((m) => m.group(0)).join(' ');
    return Wrap(spacing: 18, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (uri.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          child: QrImageView(data: uri, size: 168, padding: EdgeInsets.zero),
        ),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(T('MfaScanHelp'), style: TextStyle(fontSize: 13, height: 1.5, color: c.text2)),
          const SizedBox(height: 8),
          Text(T('MfaManualKey'), style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(height: 8),
          CodeBox(grouped),
        ]),
      ),
    ]);
  }
}

/// Recovery codes, shown once.
class RecoveryCodes extends StatelessWidget {
  final List<String> codes;
  const RecoveryCodes({super.key, required this.codes});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final text = '${codes.join('\n')}\n';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CtAlert(T('RecoveryCodesTitle'), description: T('RecoveryCodesHelp'), type: AlertType.warning),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final code in codes)
            Container(
              width: w,
              padding: const EdgeInsets.all(8),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(6)),
              child: SelectableText(code, style: TextStyle(fontFamily: 'monospace', fontSize: 14, letterSpacing: 0.8, color: c.text)),
            ),
        ]);
      }),
      const SizedBox(height: 14),
      Buttons([
        CtButton(T('Copy'), size: BtnSize.small, onPressed: () => copyText(text)),
        CtButton(T('Download'), size: BtnSize.small, onPressed: () => saveBytes('recovery-codes.txt', utf8.encode(text))),
      ]),
    ]);
  }
}

/// The change password dialog from the header menu and the profile page.
Future<void> showChangePassword(BuildContext context) async {
  final old = TextEditingController(), next = TextEditingController(), again = TextEditingController();
  String? error;
  await showCtDialog(
    context,
    title: T('ChangePassword'),
    width: 620,
    builder: (ctx, setState) => Column(children: [
      FormItem(
        label: T('OldPassword'),
        labelWidth: 150,
        required: true,
        child: CtInput(controller: old, password: true, showPassword: true, placeholder: T('For OIDC login without a password, enter any 4-20 letters')),
      ),
      FormItem(label: T('NewPassword'), labelWidth: 150, required: true, child: CtInput(controller: next, password: true, showPassword: true)),
      FormItem(label: T('ConfirmPassword'), labelWidth: 150, required: true, child: CtInput(controller: again, password: true, showPassword: true)),
      if (error != null) CtAlert(error!, type: AlertType.error),
    ]),
    footer: (ctx, setState) => [
      CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
      CtButton(T('Confirm'), tone: Tone.primary, onPressed: () async {
        String? e;
        if (old.text.isEmpty) {
          e = T('ParamRequired', {'param': T('OldPassword')});
        } else if (next.text.isEmpty) {
          e = T('ParamRequired', {'param': T('NewPassword')});
        } else if (next.text == old.text) {
          e = T('NewPasswordEqualOldPassword');
        } else if (again.text != next.text) {
          e = T('PasswordNotMatchConfirmPassword');
        }
        setState(() => error = e);
        if (e != null) return;
        if (!await confirm(ctx, T('Confirm?', {'param': T('ChangePassword')}), warning: false)) return;
        try {
          await api.post('/user/changeCurPwd', body: {'old_password': old.text, 'new_password': next.text, 'confirmPwd': again.text});
        } catch (_) {
          return;
        }
        if (!ctx.mounted) return;
        Navigator.of(ctx).pop();
        await alertBox(context, T('OperationSuccess'), title: T('ChangePassword'));
        Console.I.signOut(tellServer: false);
      }),
    ],
  );
}

class MyInfoPage extends StatefulWidget {
  const MyInfoPage({super.key});

  @override
  State<MyInfoPage> createState() => _MyInfoPageState();
}

class _MyInfoPageState extends State<MyInfoPage> {
  List<Row_> oidc = [];
  Map<String, dynamic> mfa = {};
  String setupSecret = '', setupUri = '';
  final setupCode = TextEditingController();
  final manageCode = TextEditingController();
  List<String> newCodes = [];
  List<Row_> apps = [];

  @override
  void initState() {
    super.initState();
    _oauth();
    _mfa();
    _apps();
  }

  @override
  void dispose() {
    setupCode.dispose();
    manageCode.dispose();
    super.dispose();
  }

  Future<void> _oauth() async {
    try {
      final d = await api.post('/user/myOauth', quiet: true);
      setState(() => oidc = [for (final r in (d as List? ?? const [])) Map<String, dynamic>.from(r as Map)]);
    } catch (_) {}
  }

  Future<void> _mfa() async {
    try {
      final d = await api.get('/my/mfa', quiet: true);
      setState(() => mfa = Map<String, dynamic>.from(d as Map));
    } catch (_) {}
  }

  Future<void> _apps() async {
    try {
      final d = await api.get('/my/apps', quiet: true);
      setState(() => apps = rowsOf(d));
    } catch (_) {}
  }

  Future<void> _startSetup() async {
    try {
      final d = await api.post('/my/mfa/setup');
      setState(() {
        setupSecret = '${d['secret']}';
        setupUri = '${d['uri']}';
        setupCode.clear();
      });
    } catch (_) {}
  }

  Future<void> _enable() async {
    try {
      final d = await api.post('/my/mfa/enable', body: {'secret': setupSecret, 'code': setupCode.text.trim()});
      setState(() {
        newCodes = List<String>.from(d['recovery_codes'] ?? const []);
        setupSecret = '';
      });
      Toasts.success(T('TwoFactorOn'));
      _mfa();
    } catch (_) {}
  }

  Future<void> _regenerate() async {
    final code = manageCode.text.trim();
    manageCode.clear();
    try {
      final d = await api.post('/my/mfa/recovery', body: {'code': code});
      setState(() => newCodes = List<String>.from(d['recovery_codes'] ?? const []));
      _mfa();
    } catch (_) {}
  }

  Future<void> _disable() async {
    final code = manageCode.text.trim();
    manageCode.clear();
    try {
      await api.post('/my/mfa/disable', body: {'code': code});
      setState(() => newCodes = []);
      Toasts.success(T('TwoFactorOff'));
      _mfa();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final con = Console.I;
    final enabled = mfa['enabled'] == true, required = mfa['required'] == true;
    return PageColumn([
      CtCard(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(children: [
              FormItem(label: '${T('Username')}:', child: Padding(padding: const EdgeInsets.only(top: 7), child: Text('${con.user['username'] ?? ''}'))),
              FormItem(label: '${T('Email')}:', child: Padding(padding: const EdgeInsets.only(top: 7), child: Text('${con.user['email'] ?? ''}'))),
              FormItem(
                label: '${T('Password')}:',
                child: Align(alignment: Alignment.centerLeft, child: CtButton(T('ChangePassword'), tone: Tone.danger, onPressed: () => showChangePassword(context))),
              ),
              FormItem(
                label: 'OIDC:',
                margin: EdgeInsets.zero,
                child: CtTable(
                  rows: oidc,
                  columns: [
                    Col(T('IdP'), prop: 'op'),
                    Col(T('Status'),
                        cell: (r, _) => r['status'] == 1 ? CtTag(T('HasBind'), tone: Tone.success) : CtTag(T('NoBind'), tone: Tone.danger)),
                    Col(T('Actions'),
                        width: 200,
                        cell: (r, _) => r['status'] == 1
                            ? CtButton(T('UnBind'), tone: Tone.danger, size: BtnSize.small, onPressed: () => _unbind(r))
                            : CtButton(T('ToBind'), tone: Tone.success, size: BtnSize.small, onPressed: () => _bind(r))),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
      CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CardHead(T('TwoFactorAuth'),
              titleSize: 16,
              help: T('TwoFactorAuthHelp'),
              trailing: CtTag(enabled ? T('On') : (required ? T('Required') : T('Off')),
                  large: true, tone: enabled ? Tone.success : (required ? Tone.danger : Tone.info))),
          const SizedBox(height: 14),
          if (newCodes.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 16), child: RecoveryCodes(codes: newCodes)),
          if (!enabled) ...[
            if (setupSecret.isEmpty)
              CtButton(T('SetUpTwoFactor'), tone: Tone.primary, onPressed: _startSetup)
            else ...[
              MfaQr(uri: setupUri, secret: setupSecret),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(children: [
                  Expanded(child: CtInput(controller: setupCode, placeholder: T('MfaCode'), maxLength: 6, onSubmitted: (_) => _enable())),
                  const SizedBox(width: 8),
                  CtButton(T('Verify'), tone: Tone.primary, onPressed: _enable),
                  const SizedBox(width: 8),
                  CtButton(T('Cancel'), onPressed: () => setState(() => setupSecret = '')),
                ]),
              ),
            ],
          ] else ...[
            Muted(T('RecoveryCodesLeft', {'n': mfa['recovery_left'] ?? 0})),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Row(children: [
                Expanded(child: CtInput(controller: manageCode, placeholder: T('MfaCodeOrRecovery'), maxLength: 12)),
                const SizedBox(width: 8),
                CtButton(T('NewRecoveryCodes'), onPressed: _regenerate),
                if (!required) ...[const SizedBox(width: 8), CtButton(T('TurnOff'), tone: Tone.danger, onPressed: _disable)],
              ]),
            ),
          ],
        ]),
      ),
      CtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(T('AuthorisedApps'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Muted(T('AuthorisedAppsHelp'), padding: const EdgeInsets.only(top: 4, bottom: 12)),
          if (apps.isEmpty)
            Muted(T('NoAuthorisedApps'))
          else
            CtTable(small: true, rows: apps, columns: [
              Col(T('App'), prop: 'app_name', minWidth: 160, center: false),
              Col(T('SignedIn'), prop: 'created_at', width: 170, center: false),
              Col(T('LastUsed'), width: 170, center: false, cell: (r, _) => Text(asInt(r['last_used_at']) > 0 ? timeAgo(asInt(r['last_used_at'])) : '-')),
              Col(T('Actions'), width: 110, cell: (r, _) => CtButton(T('Revoke'), tone: Tone.danger, size: BtnSize.small, onPressed: () => _revoke(r))),
            ]),
        ]),
      ),
      if (con.hello.isNotEmpty) CtCard(child: MarkdownView(con.hello)),
    ]);
  }

  Future<void> _bind(Row_ r) async {
    try {
      final d = await api.post('/oauth/bind', body: {'op': r['op']});
      openUrl('${d['url']}');
    } catch (_) {}
  }

  Future<void> _unbind(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('UnBind')}))) return;
    try {
      await api.post('/oauth/unbind', body: {'op': r['op']});
      _oauth();
    } catch (_) {}
  }

  Future<void> _revoke(Row_ r) async {
    if (!await confirm(context, T('RevokeAppConfirm', {'name': r['app_name']}), confirmText: T('Revoke'))) return;
    try {
      await api.post('/my/apps/revoke', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      _apps();
    } catch (_) {}
  }
}
