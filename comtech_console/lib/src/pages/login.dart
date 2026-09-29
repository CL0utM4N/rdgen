import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../console.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/basic.dart';
import '../widgets/dialog.dart';
import '../widgets/form.dart';
import 'my.dart' show MfaQr, RecoveryCodes;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  final captcha = TextEditingController();
  final code = TextEditingController();
  final codeFocus = FocusNode();

  List<String> providers = [];
  bool disablePwd = false;
  String captchaId = '';
  Uint8List? captchaImage;
  bool busy = false;

  // two-factor step after a correct password
  String ticket = '';
  bool setup = false;
  String uri = '';
  String secret = '';
  List<String> recovery = [];

  Timer? oidcTimer;
  String oidcWaiting = '';

  @override
  void initState() {
    super.initState();
    _options();
  }

  @override
  void dispose() {
    oidcTimer?.cancel();
    for (final c in [username, password, captcha, code]) {
      c.dispose();
    }
    codeFocus.dispose();
    super.dispose();
  }

  Future<void> _options() async {
    try {
      final d = await api.get('/login-options', quiet: true);
      if (d is Map) {
        setState(() {
          providers = List<String>.from(d['ops'] ?? const []);
          disablePwd = d['disable_pwd'] == true;
        });
        if (d['need_captcha'] == true) _loadCaptcha();
      } else if (d is List) {
        setState(() => providers = d.map((e) => '$e').toList());
      }
    } catch (_) {}
  }

  Future<void> _loadCaptcha() async {
    try {
      final d = await api.get('/captcha', quiet: true);
      final cap = d['captcha'];
      final b64 = '${cap['b64']}';
      setState(() {
        captchaId = '${cap['id']}';
        captchaImage = base64Decode(b64.substring(b64.indexOf(',') + 1));
      });
    } catch (_) {}
  }

  Future<void> _login() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final d = await api.post('/login', body: {
        'username': username.text.trim(),
        'password': password.text,
        'platform': Console.I.host.platform,
        'captcha': captcha.text.trim(),
        'captcha_id': captchaId,
      });
      if (d is Map && '${d['mfa_ticket'] ?? ''}'.isNotEmpty) {
        ticket = '${d['mfa_ticket']}';
        setup = d['mfa_setup'] == true;
        code.clear();
        if (setup) {
          try {
            final s = await api.post('/login/mfa/setup', body: {'ticket': ticket});
            uri = '${s['uri']}';
            secret = '${s['secret']}';
          } catch (_) {}
        }
        setState(() {});
        codeFocus.requestFocus();
      } else if (d is Map) {
        _done(Map<String, dynamic>.from(d));
      }
    } on ApiError catch (e) {
      // 110: too many tries, a captcha is needed now
      if (e.code == 110) _loadCaptcha();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verify() async {
    if (code.text.trim().isEmpty || busy) return;
    setState(() => busy = true);
    try {
      final d = await api.post('/login/mfa', body: {'ticket': ticket, 'code': code.text.trim()});
      final data = Map<String, dynamic>.from(d as Map);
      // codes come back only when two-factor was set up just now
      final codes = List<String>.from(data['recovery_codes'] ?? const []);
      if (codes.isNotEmpty) {
        setState(() {
          recovery = codes;
          ticket = '';
          pending = data;
        });
        return;
      }
      _done(data);
    } on ApiError catch (e) {
      code.clear();
      // an expired or used up ticket means signing in again
      if (e.message.contains('sign in again')) _cancelMfa();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Map<String, dynamic>? pending;

  void _cancelMfa() => setState(() {
        ticket = '';
        setup = false;
        uri = '';
        secret = '';
        password.clear();
      });

  void _done(Map<String, dynamic> data) {
    Toasts.success(T('LoginSuccess'));
    Console.I.signedIn_(data);
  }

  Future<void> _oidc(String op) async {
    try {
      final d = await api.post('/oidc/auth', body: {
        'deviceInfo': {'name': 'Comtech console', 'os': Console.I.host.platform, 'type': 'webadmin'},
        'id': '${Console.I.host.platform}-console',
        'op': op,
        'uuid': '',
      });
      final c = '${d['code']}';
      await launchUrl(Uri.parse('${d['url']}'), mode: LaunchMode.externalApplication);
      setState(() => oidcWaiting = op);
      var tries = 0;
      oidcTimer?.cancel();
      oidcTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
        if (++tries > 90) {
          t.cancel();
          if (mounted) setState(() => oidcWaiting = '');
          return;
        }
        try {
          final u = await api.get('/oidc/auth-query', params: {'code': c, 'uuid': ''}, quiet: true);
          if (u is Map && '${u['token'] ?? ''}'.isNotEmpty) {
            t.cancel();
            if (mounted) setState(() => oidcWaiting = '');
            _done(Map<String, dynamic>.from(u));
          }
        } catch (_) {
          // not finished in the browser yet
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    Widget form;
    if (recovery.isNotEmpty) {
      form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RecoveryCodes(codes: recovery),
        const SizedBox(height: 16),
        CtButton(T('SavedContinue'), tone: Tone.primary, size: BtnSize.large, expand: true, onPressed: () => _done(pending!)),
      ]);
    } else if (ticket.isNotEmpty) {
      form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (setup) ...[
          Muted(T('MfaSetupAtLogin'), padding: const EdgeInsets.only(bottom: 14), color: c.text2),
          MfaQr(uri: uri, secret: secret),
          const SizedBox(height: 14),
        ] else
          Muted(T('MfaEnterCode'), padding: const EdgeInsets.only(bottom: 14), color: c.text2),
        FormItem(
          top: true,
          label: T('MfaCode'),
          child: CtInput(controller: code, focusNode: codeFocus, height: 40, maxLength: 12, onSubmitted: (_) => _verify()),
        ),
        CtButton(T('Verify'), tone: Tone.primary, size: BtnSize.large, expand: true, loading: busy, onPressed: _verify),
        const SizedBox(height: 10),
        CtButton(T('Back'), size: BtnSize.large, expand: true, onPressed: _cancelMfa),
        if (!setup) Muted(T('MfaUseRecovery'), size: 12, padding: const EdgeInsets.only(top: 10)),
      ]);
    } else {
      form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!disablePwd) ...[
          FormItem(top: true, label: T('Username'), child: CtInput(controller: username, height: 40, autofocus: true, onSubmitted: (_) => _login())),
          FormItem(
            top: true,
            label: T('Password'),
            child: CtInput(controller: password, height: 40, password: true, showPassword: true, onSubmitted: (_) => _login()),
          ),
          if (captchaImage != null)
            FormItem(
              top: true,
              label: T('Captcha'),
              child: CtInput(
                controller: captcha,
                height: 40,
                onSubmitted: (_) => _login(),
                append: GestureDetector(
                  onTap: _loadCaptcha,
                  child: MouseRegion(cursor: SystemMouseCursors.click, child: Image.memory(captchaImage!, width: 150, height: 38, fit: BoxFit.cover)),
                ),
              ),
            ),
          CtButton(T('Login'), tone: Tone.primary, size: BtnSize.large, expand: true, loading: busy, onPressed: _login),
        ],
        if (providers.isNotEmpty && !disablePwd)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(children: [
              Expanded(child: Divider(color: c.border)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(T('or login in with'), style: TextStyle(fontSize: 13, color: c.muted))),
              Expanded(child: Divider(color: c.border)),
            ]),
          ),
        for (final p in providers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CtButton(
              oidcWaiting == p ? T('WaitingForBrowser') : T(p),
              size: BtnSize.large,
              expand: true,
              loading: oidcWaiting == p,
              icon: Icons.login,
              onPressed: () => _oidc(p),
            ),
          ),
      ]);
    }
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(center: const Alignment(0, -1.2), radius: 1.2, colors: [c.primarySoft, c.bg], stops: const [0, 0.7]),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 50, offset: Offset(0, 20))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: c.primarySoft, spreadRadius: 4)],
                    image: const DecorationImage(image: AssetImage('packages/comtech_console/assets/comtech-logo.jpg'), fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('ComTech IT', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.text)),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 24),
                child: Text(T('SignInToContinue'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.muted)),
              ),
              form,
            ]),
          ),
        ),
      ),
    );
  }
}
