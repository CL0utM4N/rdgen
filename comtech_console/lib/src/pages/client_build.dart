import 'dart:async';
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
import '../widgets/select.dart';
import '../widgets/table.dart';
import 'dashboard.dart' show buildTone;

const buildPlatforms = [
  ('windows', 'Windows 64-bit'),
  ('windows-x86', 'Windows 32-bit'),
  ('linux', 'Linux'),
  ('macos', 'macOS'),
  ('android', 'Android'),
  ('ios', 'iOS'),
];
const platformHelp = {'macos': 'PlatformHelpMacos', 'android': 'PlatformHelpAndroid', 'linux': 'PlatformHelpLinux'};
const buildImages = [('icon', 'AppIcon'), ('logo', 'AppLogo'), ('privacy', 'PrivacyScreen')];
const buildPermissions = [
  'enable_keyboard', 'enable_clipboard', 'enable_file_transfer', 'enable_audio', 'enable_tcp', 'enable_remote_restart',
  'enable_recording', 'enable_blocking_input', 'enable_remote_modi', 'enable_printer', 'enable_camera', 'enable_terminal',
];

/// The options a build preset stores and applies. Keep in step with
/// presetFields in the server's service/buildPreset.go.
const _presetKeys = [
  'app_name', 'company_name', 'note',
  'direction', 'password_approve_mode',
  'permissions_override', 'permissions_type',
  'enable_keyboard', 'enable_clipboard', 'enable_file_transfer', 'enable_audio', 'enable_tcp',
  'enable_remote_restart', 'enable_recording', 'enable_blocking_input', 'enable_remote_modi',
  'enable_printer', 'enable_camera', 'enable_terminal',
  'disable_installation', 'disable_settings', 'deny_lan', 'enable_direct_ip', 'auto_close',
  'hide_cm', 'remove_wallpaper', 'remove_new_version_notif',
  'theme', 'theme_override', 'android_app_id',
  'default_manual', 'override_manual',
  'icon', 'logo', 'privacy',
];

class ClientBuildPage extends StatefulWidget {
  const ClientBuildPage({super.key});

  @override
  State<ClientBuildPage> createState() => _ClientBuildPageState();
}

class _ClientBuildPageState extends State<ClientBuildPage> {
  final ctl = ListCtl((q) => api.get('/client_build/list', params: q));
  Map<String, dynamic> opts = {'loaded': false, 'ready': false, 'reason': '', 'callback_url': '', 'versions': []};
  Map<String, dynamic>? base;
  List<Row_> groups = [], users = [];
  Timer? timer;

  /// Builds whose BitLocker switch is being saved.
  final Set<int> savingBitlocker = {};

  @override
  void initState() {
    super.initState();
    _options().then((_) => ctl.load());
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ctl.list.any((b) => b['status'] == 'queued' || b['status'] == 'in_progress')) ctl.load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    ctl.dispose();
    super.dispose();
  }

  Future<void> _options() async {
    try {
      final d = await api.get('/client_build/options', quiet: true);
      opts = {...Map<String, dynamic>.from(d as Map), 'loaded': true};
    } catch (_) {}
    groups = await Lookups.deviceGroups();
    users = await Lookups.users();
    if (mounted) setState(() {});
  }

  List<Row_> get basePlatforms => rowsOf(base?['platforms']);
  bool get anyBase => basePlatforms.any((p) => p['ready'] == true);
  List<String> files(Row_ r) => '${r['files'] ?? ''}'.isEmpty ? [] : '${r['files']}'.split(',');
  String downloadUrl(Row_ r, String f) =>
      '${Console.I.host.apiServer}/api/clientgen/download/${r['uuid']}/${Uri.encodeComponent(f)}?key=${r['download_key']}';

  Future<void> _email(Row_ r) async {
    final to = TextEditingController(), msg = TextEditingController();
    var sending = false;
    await showCtDialog(
      context,
      title: T('EmailClientTo'),
      width: 560,
      builder: (ctx, set) => Column(children: [
        FormItem(top: true, label: T('CustomerEmail'), required: true, child: CtInput(controller: to, placeholder: 'name@company.com')),
        FormItem(top: true, label: T('MessageToCustomer'), child: CtInput(controller: msg, rows: 3)),
      ]),
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Send'), tone: Tone.primary, loading: sending, onPressed: () async {
          if (to.text.trim().isEmpty) return Toasts.error(T('ParamRequired', {'param': T('CustomerEmail')}));
          set(() => sending = true);
          try {
            await api.post('/client_build/email', body: {'id': r['id'], 'to': to.text.trim(), 'message': msg.text}, timeout: const Duration(seconds: 60));
            Toasts.success(T('EmailSent'));
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (_) {
            set(() => sending = false);
          }
        }),
      ],
    );
  }

  Future<void> _rebuild(Row_ r) async {
    if (!await confirm(context, T('RebuildConfirm', {'id': r['id']}), confirmText: T('Rebuild'), warning: false)) return;
    try {
      final d = await api.post('/client_build/rebuild', body: {'id': r['id']}, timeout: const Duration(seconds: 60));
      Toasts.success(T('RebuildStarted', {'id': d['id']}));
      ctl.load();
    } catch (_) {}
  }

  bool isWindows(dynamic platform) => '$platform'.startsWith('windows');

  Future<void> _setBitlocker(Row_ r, bool on) async {
    final id = asInt(r['id']);
    setState(() => savingBitlocker.add(id));
    try {
      final d = await api.post('/client_build/bitlocker', body: {'id': id, 'enabled': on});
      r['bitlocker_escrow'] = d is Map ? d['bitlocker_escrow'] == true : on;
      Toasts.success(T(r['bitlocker_escrow'] == true ? 'BitlockerBuildOn' : 'BitlockerBuildOff'));
    } catch (_) {}
    if (mounted) setState(() => savingBitlocker.remove(id));
    ctl.touch();
  }

  Future<void> _del(Row_ r) async {
    if (!await confirm(context, T('Confirm?', {'param': T('Delete')}))) return;
    try {
      await api.post('/client_build/delete', body: {'id': r['id']});
      Toasts.success(T('OperationSuccess'));
      ctl.load();
    } catch (_) {}
  }

  Map<String, dynamic> _defaults() => {
        'platform': 'windows',
        'instant': basePlatforms.any((p) => p['key'] == 'windows' && p['ready'] == true),
        'version': (opts['versions'] as List?)?.isNotEmpty == true ? '${(opts['versions'] as List).first}' : '1.4.9',
        'file_name': 'ComtechSupport',
        'app_name': '',
        'company_name': '',
        'note': '',
        'device_group_id': null,
        'preset_user_id': null,
        'server_host': opts['server_host'] ?? '',
        'server_port': opts['server_port'] ?? '',
        'api_server': opts['api_server'] ?? '',
        'key': opts['key'] ?? '',
        'url_link': '',
        'download_link': '',
        'android_app_id': '',
        'direction': 'both',
        'disable_installation': false,
        'disable_settings': false,
        'bitlocker_escrow': false,
        'theme': 'system',
        'theme_override': false,
        'password_approve_mode': 'password-click',
        'permanent_password': '',
        'deny_lan': false,
        'enable_direct_ip': false,
        'auto_close': false,
        'hide_cm': false,
        'permissions_override': false,
        'permissions_type': 'custom',
        'enable_keyboard': true,
        'enable_clipboard': true,
        'enable_file_transfer': true,
        'enable_audio': true,
        'enable_tcp': true,
        'enable_remote_restart': true,
        'enable_recording': true,
        'enable_blocking_input': true,
        'enable_remote_modi': false,
        'enable_printer': true,
        'enable_camera': true,
        'enable_terminal': true,
        'remove_wallpaper': true,
        'delay_fix': true,
        'x_offline': false,
        'remove_new_version_notif': false,
        'default_manual': '',
        'override_manual': '',
        'icon': '',
        'logo': '',
        'privacy': '',
      };

  Future<void> _create() async {
    final f = _defaults();
    var tab = 'general';
    var submitting = false;
    int? presetId;
    var presets = <Row_>[];
    Future<void> loadPresets() async {
      try {
        final d = await api.get('/build_preset/list', quiet: true);
        presets = rowsOf(d['list']);
      } catch (_) {}
    }

    await loadPresets();
    if (!mounted) return;
    Row_? caps() => basePlatforms.where((p) => p['key'] == f['platform']).firstOrNull;
    bool instant() => f['instant'] == true && caps()?['ready'] == true;

    await showCtDialog(
      context,
      title: T('NewClientBuild'),
      width: 900,
      builder: (ctx, set) {
        final c = ctx.ct;
        final cp = caps();
        final inst = instant();
        String imageOff(String key) {
          if (!inst) return '';
          if (key == 'privacy') return T('PrivacyNeedsGitHub');
          if (key == 'icon' && cp!['icon'] != true) return '${cp['icon_reason'] ?? ''}';
          if (key == 'logo' && cp!['logo'] != true) return T('LogoNotAvailable');
          return '';
        }

        String instantHelp() {
          if (cp == null) return T('InstantNotForPlatform');
          if ('${cp['problem'] ?? ''}'.isNotEmpty) return '${cp['problem']}';
          if (cp['ready'] != true) return T('InstantNoBase', {'platform': cp['label']});
          return T('InstantBuildHelpPlatform', {'v': (cp['current'] as Map?)?['version'], 'output': cp['output']});
        }

        Widget item(String label, Widget child, {String? help, bool required = false, bool warn = false}) =>
            FormItem(label: label, labelWidth: 200, required: required, help: help, warnHelp: warn, child: child);
        Widget text(String key, String label, {String? placeholder, bool enabled = true, String? help, bool warn = false, bool required = false}) =>
            item(label, CtInput(value: '${f[key] ?? ''}', placeholder: placeholder, enabled: enabled, onChanged: (v) => f[key] = v), help: help, warn: warn, required: required);
        Widget sw(String key, String label, {bool enabled = true, String? help}) =>
            item(label, Align(alignment: Alignment.centerLeft, child: CtSwitch(value: f[key] == true, onChanged: enabled ? (v) => set(() => f[key] = v) : null)), help: help);
        Widget note(String t, [AlertType type = AlertType.info]) => Padding(padding: const EdgeInsets.only(bottom: 18), child: CtAlert(t, type: type));

        final general = [
          item(
            T('Platform'),
            Align(
              alignment: Alignment.centerLeft,
              child: CtSegmented<String>(
                value: '${f['platform']}',
                options: buildPlatforms,
                onChanged: (v) => set(() {
                  f['platform'] = v;
                  f['instant'] = caps()?['ready'] == true;
                }),
              ),
            ),
            required: true,
            help: !inst && platformHelp[f['platform']] != null ? T(platformHelp[f['platform']]!) : null,
          ),
          item(T('InstantBuild'), Align(alignment: Alignment.centerLeft, child: CtSwitch(value: f['instant'] == true, onChanged: cp?['ready'] == true && f['platform'] != 'ios' ? (v) => set(() => f['instant'] = v) : null)),
              help: instantHelp()),
          if (inst && '${cp!['note'] ?? ''}'.isNotEmpty) note('${cp['note']}'),
          item(
            T('Version'),
            Align(
              alignment: Alignment.centerLeft,
              child: CtSelect<String>(
                width: 200,
                value: '${f['version']}',
                options: [for (final v in (opts['versions'] as List? ?? const [])) Opt('$v', v == 'master' ? 'master (nightly)' : '$v')],
                onChanged: inst ? null : (v) => set(() => f['version'] = v),
              ),
            ),
            required: true,
            help: inst ? T('VersionFromBase', {'v': (cp!['current'] as Map?)?['version']}) : null,
          ),
          text('file_name', T('ExeFileName'), required: true),
          text('app_name', T('AppName'),
              placeholder: 'RustDesk',
              enabled: !(inst && cp!['name'] != true),
              help: inst && '${cp!['name_reason'] ?? ''}'.isNotEmpty ? '${cp['name_reason']}' : null,
              warn: inst && cp!['name'] != true),
          text('company_name', T('CompanyName')),
          item(
            T('DeviceGroup'),
            CtSelect<int>(
              value: f['device_group_id'] as int?,
              clearable: true,
              filterable: true,
              options: [for (final g in groups) Opt(asInt(g['id']), '${g['name']}')],
              onChanged: (v) => set(() => f['device_group_id'] = v),
            ),
            help: T('DeviceGroupHelp'),
          ),
          item(
            T('PresetUser'),
            CtSelect<int>(
              value: f['preset_user_id'] as int?,
              clearable: true,
              filterable: true,
              options: [for (final u in users) Opt(asInt(u['id']), '${u['username']}')],
              onChanged: (v) => set(() => f['preset_user_id'] = v),
            ),
            help: T('PresetUserHelp'),
          ),
          text('note', T('Note')),
          item(
            T('ConnectionDirection'),
            CtRadios<String>(
              value: '${f['direction']}',
              options: [('incoming', T('IncomingOnly')), ('outgoing', T('OutgoingOnly')), ('both', T('Bidirectional'))],
              onChanged: (v) => set(() => f['direction'] = v),
            ),
          ),
          sw('disable_installation', T('DisableInstallation')),
          sw('disable_settings', T('DisableSettings')),
          if (isWindows(f['platform']))
            item(
              '',
              Align(
                alignment: Alignment.centerLeft,
                child: CtCheckbox(
                  value: f['bitlocker_escrow'] == true,
                  label: Text(T('BitlockerEscrow')),
                  onChanged: opts['bitlocker_available'] == true ? (v) => set(() => f['bitlocker_escrow'] = v) : null,
                ),
              ),
              help: opts['bitlocker_available'] == true ? T('BitlockerEscrowHelp') : T('BitlockerNeedsSetting'),
              warn: opts['bitlocker_available'] != true,
            ),
        ];
        final server = [
          note(T('ServerDefaultsHelp')),
          text('server_host', T('ServerHost')),
          text('server_port', T('ServerPort')),
          text('api_server', T('ApiServer')),
          text('key', 'Key'),
          text('url_link', T('UrlLink'), placeholder: 'https://rustdesk.com', enabled: !inst),
          text('download_link', T('DownloadLink'), placeholder: 'https://rustdesk.com/download', enabled: !inst),
          text('android_app_id', T('AndroidAppId'), placeholder: 'com.carriez.flutter_hbb', enabled: !inst && f['platform'] == 'android'),
          if (inst) note(T('FixedInBaseLinks'), AlertType.warning),
        ];
        final visual = [
          for (final img in buildImages)
            Opacity(
              opacity: imageOff(img.$1).isEmpty ? 1 : 0.6,
              child: item(
                T(img.$2),
                Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  CtButton(T('ChooseFile'), icon: Icons.image_outlined, onPressed: imageOff(img.$1).isNotEmpty ? null : () => _pickImage(f, img.$1, set)),
                  if ('${f[img.$1]}'.isNotEmpty && imageOff(img.$1).isEmpty) ...[
                    Container(
                      height: 64,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(6)),
                      child: Image.memory(base64Decode('${f[img.$1]}'.substring('${f[img.$1]}'.indexOf(',') + 1)), fit: BoxFit.contain),
                    ),
                    CtButton(T('Delete'), link: true, tone: Tone.danger, onPressed: () => set(() => f[img.$1] = '')),
                  ],
                ]),
                help: imageOff(img.$1).isEmpty ? null : imageOff(img.$1),
                warn: true,
              ),
            ),
          item(
            T('Theme'),
            CtRadios<String>(
              value: '${f['theme']}',
              options: [('light', T('Light')), ('dark', T('Dark')), ('system', T('FollowSystem'))],
              onChanged: (v) => set(() => f['theme'] = v),
            ),
          ),
          sw('theme_override', T('LockTheme')),
        ];
        final security = [
          item(
            T('ApproveMode'),
            CtSelect<String>(
              value: '${f['password_approve_mode']}',
              options: [Opt('password', T('ApproveByPassword')), Opt('click', T('ApproveByClick')), Opt('password-click', T('ApproveByBoth'))],
              onChanged: (v) => set(() => f['password_approve_mode'] = v ?? 'password-click'),
            ),
          ),
          item(T('PermanentPassword'),
              CtInput(value: '${f['permanent_password']}', password: true, showPassword: true, onChanged: (v) => f['permanent_password'] = v),
              help: T('PermanentPasswordHelp')),
          sw('deny_lan', T('DenyLan')),
          sw('enable_direct_ip', T('EnableDirectIp')),
          sw('auto_close', T('AutoClose')),
          sw('hide_cm', T('HideCm'), help: T('HideCmHelp')),
        ];
        final permissions = [
          sw('permissions_override', T('LockPermissions')),
          item(
            T('PermissionsType'),
            CtRadios<String>(
              value: '${f['permissions_type']}',
              options: [('custom', T('Custom')), ('full', T('FullAccess')), ('view', T('ScreenShare'))],
              onChanged: (v) => set(() => f['permissions_type'] = v),
            ),
          ),
          for (final p in buildPermissions) sw(p, T('Perm_$p')),
        ];
        final advanced = [
          sw('remove_wallpaper', T('RemoveWallpaper')),
          if (inst) note(T('FixedInBase'), AlertType.warning),
          sw('delay_fix', T('DelayFix'), enabled: !inst),
          sw('x_offline', T('XOffline'), enabled: !inst),
          sw('remove_new_version_notif', T('RemoveNewVersionNotif'), enabled: !inst),
          item(T('DefaultSettings'), CtInput(value: '${f['default_manual']}', rows: 4, placeholder: 'key=value', onChanged: (v) => f['default_manual'] = v)),
          item(T('OverrideSettings'), CtInput(value: '${f['override_manual']}', rows: 4, placeholder: 'key=value', onChanged: (v) => f['override_manual'] = v)),
        ];
        final tabs = {'general': general, 'server': server, 'visual': visual, 'security': security, 'permissions': permissions, 'advanced': advanced};
        Row_? selectedPreset() => presets.where((p) => asInt(p['id']) == presetId).firstOrNull;
        Future<void> savePreset() async {
          final name = (await prompt(ctx, T('PresetName'), title: T('SaveAsPreset')))?.trim() ?? '';
          if (name.isEmpty) return;
          try {
            await api.post('/build_preset/create', body: {
              'name': name,
              'options': {for (final k in _presetKeys) k: f[k]},
            });
            await loadPresets();
            presetId = null;
            Toasts.success(T('PresetSaved'));
            set(() {});
          } catch (_) {}
        }

        Future<void> deletePreset() async {
          final sel = selectedPreset();
          if (sel == null || !await confirm(ctx, T('DeletePresetConfirm', {'name': '${sel['name']}'}))) return;
          try {
            await api.post('/build_preset/delete', body: {'id': sel['id']});
            await loadPresets();
            presetId = null;
            Toasts.success(T('PresetDeleted'));
            set(() {});
          } catch (_) {}
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(children: [
              Text(T('Preset')),
              const SizedBox(width: 12),
              CtSelect<int>(
                width: 260,
                value: presetId,
                clearable: true,
                placeholder: T('NonePreset'),
                options: [for (final p in presets) Opt(asInt(p['id']), '${p['name']}')],
                onChanged: (v) => set(() {
                  presetId = v;
                  final o = selectedPreset()?['options'];
                  if (o is Map) {
                    for (final k in _presetKeys) {
                      if (o.containsKey(k)) f[k] = o[k];
                    }
                  }
                }),
              ),
              const SizedBox(width: 8),
              CtButton(T('DeletePreset'), onPressed: presetId == null ? null : deletePreset),
              const Spacer(),
              CtButton(T('SaveAsPreset'), onPressed: savePreset),
            ]),
          ),
          CtTabs<String>(
            value: tab,
            tabs: [
              ('general', T('General')),
              ('server', T('Server')),
              ('visual', T('Appearance')),
              ('security', T('Security')),
              ('permissions', T('Permissions')),
              ('advanced', T('Advanced')),
            ],
            onChanged: (v) => set(() => tab = v),
          ),
          ...tabs[tab]!,
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(instant() ? T('MakeInstaller') : T('StartBuild'), tone: Tone.primary, loading: submitting, onPressed: () async {
          if ('${f['file_name']}'.isEmpty) {
            set(() => tab = 'general');
            return Toasts.error(T('ParamRequired', {'param': T('ExeFileName')}));
          }
          set(() => submitting = true);
          final data = {
            ...f,
            'device_group_id': f['device_group_id'] ?? 0,
            'preset_user_id': f['preset_user_id'] ?? 0,
            'instant': instant(),
            'bitlocker_escrow': f['bitlocker_escrow'] == true && isWindows(f['platform']) && opts['bitlocker_available'] == true,
          };
          try {
            final d = await api.post('/client_build/create', body: data, timeout: const Duration(seconds: 120));
            Toasts.success(!instant() ? T('BuildStarted') : (d is Map && d['status'] == 'in_progress' ? T('InstallerMaking') : T('InstallerReady')));
            if (ctx.mounted) Navigator.of(ctx).pop();
            ctl.filter();
          } catch (_) {
            set(() => submitting = false);
          }
        }),
      ],
    );
  }

  Future<void> _pickImage(Map<String, dynamic> f, String key, StateSetter set) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png'], withData: true);
    final file = r?.files.single;
    if (file?.bytes == null) return;
    if (!file!.name.toLowerCase().endsWith('.png')) return Toasts.error(T('PngOnly'));
    if (file.size > 2 * 1024 * 1024) return Toasts.error(T('ImageTooLarge'));
    set(() => f[key] = 'data:image/png;base64,${base64Encode(file.bytes!)}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => PageColumn([
        BaseCard(onStatus: (s) => setState(() => base = s)),
        const TechCard(),
        QueryBar(
          above: opts['loaded'] == true && opts['ready'] != true && !anyBase
              ? CtAlert(
                  T('ClientBuilderNotReady'),
                  type: AlertType.warning,
                  margin: const EdgeInsets.only(bottom: 12),
                  body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${opts['reason'] ?? ''}'),
                    Text('${T('ClientBuilderGenUrl')}: ${opts['callback_url'] ?? ''}'),
                  ]),
                )
              : null,
          children: [
            Buttons([
              CtButton(T('NewClientBuild'), tone: Tone.primary, onPressed: opts['ready'] == true || anyBase ? _create : null),
              CtButton(T('Refresh'), onPressed: ctl.load),
            ]),
          ],
        ),
        CtCard(
          child: CtTable(loading: ctl.loading, rows: ctl.list, columns: [
            const Col('ID', prop: 'id', width: 70),
            Col(T('AppName'), prop: 'app_name'),
            Col(T('Platform'), prop: 'platform', width: 110),
            Col(T('Version'), prop: 'version', width: 90),
            Col(T('DeviceGroup'), minWidth: 170, cell: (r, _) => asInt(r['device_group_id']) > 0 ? CtTag(nameOf(groups, r['device_group_id'])) : const SizedBox()),
            Col(T('Note'), prop: 'note'),
            Col(T('Status'),
                width: 160,
                cell: (r, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                      CtTag(T('BuildStatus_${r['status']}'), tone: buildTone('${r['status']}')),
                      if ('${r['message'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${r['message']}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: c.muted)),
                        ),
                    ])),
            Col(T('Installers'),
                minWidth: 150,
                cell: (r, _) {
                  final fs = files(r);
                  if (fs.isEmpty) return const Text('-');
                  return CtMenuButton(
                    button: CtButton(T('Download'), size: BtnSize.table, trailingIcon: Icons.keyboard_arrow_down, onPressed: () {}),
                    actions: [for (final f in fs) MenuAction(f, () => openUrl(downloadUrl(r, f)))],
                  );
                }),
            Col(T('BitlockerColumn'),
                width: 110,
                cell: (r, _) => isWindows(r['platform']) && '${r['kind'] ?? ''}'.isEmpty
                    ? Tooltip(
                        message: T('BitlockerBuildHelp'),
                        child: CtSwitch(
                          value: r['bitlocker_escrow'] == true,
                          loading: savingBitlocker.contains(asInt(r['id'])),
                          onChanged: (v) => _setBitlocker(r, v),
                        ),
                      )
                    : const Text('-')),
            Col(T('CreatedAt'), prop: 'created_at', width: 160),
            Col(T('Actions'),
                width: 320,
                cell: (r, _) => Actions_([
                      if ('${r['files'] ?? ''}'.isNotEmpty && opts['mail_ready'] == true)
                        CtButton(T('Email'), tone: Tone.primary, size: BtnSize.table, onPressed: () => _email(r)),
                      if ('${r['log_url'] ?? ''}'.isNotEmpty) CtButton(T('BuildLog'), size: BtnSize.table, onPressed: () => openUrl('${r['log_url']}')),
                      if (r['status'] != 'queued' && r['status'] != 'in_progress')
                        CtButton(T('Rebuild'),
                            tone: r['status'] == 'failure' || r['status'] == 'error' ? Tone.warning : null, size: BtnSize.table, onPressed: () => _rebuild(r)),
                      CtButton(T('Delete'), tone: Tone.danger, size: BtnSize.table, onPressed: () => _del(r)),
                    ])),
          ]),
        ),
        CtPagination(total: ctl.total, page: ctl.page, pageSize: ctl.pageSize, sizes: const [10, 20, 50], onChange: ctl.setPage),
      ]),
    );
  }
}

/// Base clients: what instant builds are made from, and building new ones.
class BaseCard extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onStatus;
  const BaseCard({super.key, required this.onStatus});

  @override
  State<BaseCard> createState() => _BaseCardState();
}

class _BaseCardState extends State<BaseCard> {
  Map<String, dynamic> st = {'platforms': [], 'latest': '', 'options': {}, 'public_key': '', 'problem': ''};
  bool loading = false;
  String starting = '';
  Timer? timer;
  final canSettings = can(['settings']);

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (rowsOf(st['platforms']).any((p) => p['building'] != null)) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => loading = true);
    try {
      final d = await api.get('/client_build/base', quiet: true, timeout: const Duration(seconds: 60));
      st = Map<String, dynamic>.from(d as Map);
      widget.onStatus(st);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _build(Row_ row) async {
    if (!await confirm(context, T('BuildBaseConfirm', {'v': st['latest'] ?? '', 'platform': row['label']}), confirmText: T('BuildBase'), warning: false)) return;
    setState(() => starting = '${row['key']}');
    try {
      await api.post('/client_build/base/build', body: {'version': st['latest'], 'platform': row['key']}, timeout: const Duration(seconds: 60));
      Toasts.success(T('BaseBuildStarted'));
      _load();
    } catch (_) {}
    if (mounted) setState(() => starting = '');
  }

  Future<void> _settings() async {
    final f = <String, dynamic>{'auto_update': true, 'push_updates': false, 'company': '', 'website': '', 'android_name': '', ...Map<String, dynamic>.from(st['options'] as Map? ?? {})};
    var saving = false;
    await showCtDialog(
      context,
      title: T('BaseClientSettings'),
      width: 680,
      builder: (ctx, set) {
        Widget sw(String k, String label, String help) => FormItem(
              label: label,
              labelWidth: 210,
              help: help,
              child: Align(alignment: Alignment.centerLeft, child: CtSwitch(value: f[k] == true, onChanged: (v) => set(() => f[k] = v))),
            );
        Widget text(String k, String label, String help, [String? ph]) =>
            FormItem(label: label, labelWidth: 210, help: help, child: CtInput(value: '${f[k] ?? ''}', placeholder: ph, onChanged: (v) => f[k] = v));
        return Column(children: [
          sw('auto_update', T('AutomaticUpdates'), T('AutomaticUpdatesHelp')),
          sw('push_updates', T('PushUpdates'), T('PushUpdatesHelp')),
          text('company', T('CompanyName'), T('BaseCompanyHelp')),
          text('website', T('UrlLink'), T('BaseWebsiteHelp'), 'https://comtechit.au'),
          text('android_name', T('AndroidAppName'), T('AndroidAppNameHelp'), 'RustDesk'),
          FormItem(label: T('SettingsKey'), labelWidth: 210, help: T('SettingsKeyHelp'), child: CodeBox('${st['public_key'] ?? ''}')),
        ]);
      },
      footer: (ctx, set) => [
        CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        CtButton(T('Save'), tone: Tone.primary, loading: saving, onPressed: () async {
          set(() => saving = true);
          try {
            await api.post('/client_build/base/options', body: f);
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

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final options = Map<String, dynamic>.from(st['options'] as Map? ?? {});
    final latest = '${st['latest'] ?? ''}';
    return CtCard(
      child: Loading(
        loading: loading,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHead(
            T('InstantBuilds'),
            titleSize: 16,
            help: T('InstantBuildsHelp'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${T('LatestRelease')}: ', style: TextStyle(color: c.muted, fontSize: 13)),
                TextSpan(text: latest.isEmpty ? '?' : latest, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ])),
              if (canSettings) ...[const SizedBox(width: 12), CtButton(T('Settings'), onPressed: _settings)],
            ]),
          ),
          if ('${st['problem'] ?? ''}'.isNotEmpty) CtAlert('${st['problem']}', type: AlertType.warning, margin: const EdgeInsets.only(top: 12)),
          const SizedBox(height: 12),
          CtTable(small: true, border: false, rows: rowsOf(st['platforms']), columns: [
            Col(T('Platform'), width: 120, center: false, cell: (r, _) => Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Col(T('BaseClient'),
                width: 220,
                center: false,
                cell: (r, _) {
                  final cur = r['current'] as Map?;
                  return Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    cur != null ? Text('RustDesk ${cur['version']}') : Text(T('NoBaseYet'), style: TextStyle(color: c.warning)),
                    if (cur != null && r['update_available'] == true && r['building'] == null)
                      CtTag(T('UpdateAvailable'), small: true, tone: Tone.warning)
                    else if (cur != null && r['update_available'] != true)
                      CtTag(T('UpToDate'), small: true, tone: Tone.success),
                  ]);
                }),
            Col(T('Status'),
                minWidth: 260,
                center: false,
                cell: (r, _) {
                  final building = r['building'] as Map?, failure = r['last_failure'] as Map?, cur = r['current'] as Map?;
                  Widget line(String text, Color color, [String? log]) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(text, style: TextStyle(fontSize: 12, color: color)),
                        if (log != null && log.isNotEmpty) CtButton(T('BuildLog'), link: true, tone: Tone.primary, size: BtnSize.small, onPressed: () => openUrl(log)),
                      ]);
                  if (building != null) return line(T('BaseBuilding', {'v': building['version']}), c.muted, '${building['log_url'] ?? ''}');
                  if (failure != null) return line('${T('BaseFailed', {'v': failure['version']})}: ${failure['message']}', c.danger, '${failure['log_url'] ?? ''}');
                  if ('${r['problem'] ?? ''}'.isNotEmpty) return line('${r['problem']}', c.warning);
                  if ('${cur?['message'] ?? ''}'.isNotEmpty) return line('${cur!['message']}', c.muted);
                  if (cur != null) return line(T('InstantMakes', {'output': r['output']}), c.muted);
                  return const SizedBox();
                }),
            if (canSettings)
              Col('',
                  width: 210,
                  right: true,
                  cell: (r, _) => CtButton(
                        latest.isNotEmpty ? T('BuildBaseVersion', {'v': latest}) : T('BuildBase'),
                        size: BtnSize.small,
                        tone: r['update_available'] == true ? Tone.primary : null,
                        loading: starting == r['key'],
                        onPressed: r['building'] != null || '${st['problem'] ?? ''}'.isNotEmpty ? null : () => _build(r),
                      )),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 24, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '${T('AutomaticUpdates')}: ', style: TextStyle(color: c.muted, fontSize: 13)),
              TextSpan(text: options['auto_update'] == true ? T('On') : T('Off'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ])),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${T('PushUpdates')}: ', style: TextStyle(color: c.muted, fontSize: 13)),
              TextSpan(text: options['push_updates'] == true ? T('On') : T('Off'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ])),
          ]),
        ]),
      ),
    );
  }
}

/// Our own staff's app, which opens on the console.
class TechCard extends StatefulWidget {
  const TechCard({super.key});

  @override
  State<TechCard> createState() => _TechCardState();
}

class _TechCardState extends State<TechCard> {
  List<Row_> apps = [];
  bool loading = false;
  String making = '';
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    // macOS and Linux take a minute or two
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (apps.any((a) => (a['build'] as Map?)?['status'] == 'in_progress')) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => loading = true);
    try {
      final d = await api.get('/client_build/technician', quiet: true);
      apps = rowsOf(d['apps']);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _make(Row_ a) async {
    setState(() => making = '${a['platform']}');
    try {
      await api.post('/client_build/technician/make', body: {'platform': a['platform']}, timeout: const Duration(seconds: 120));
      Toasts.success(T('TechnicianStarted'));
      _load();
    } catch (_) {}
    if (mounted) setState(() => making = '');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return CtCard(
      child: Loading(
        loading: loading,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHead(T('TechnicianApp'), titleSize: 16, help: T('TechnicianAppHelp')),
          const SizedBox(height: 12),
          CtTable(small: true, border: false, rows: apps, columns: [
            Col(T('Platform'), width: 120, center: false, cell: (r, _) => Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Col(T('Version'),
                width: 190,
                center: false,
                cell: (r, _) => Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      (r['links'] as List).isNotEmpty
                          ? Text('RustDesk ${(r['build'] as Map?)?['version'] ?? ''}')
                          : Text(T('TechnicianNotMade'), style: TextStyle(fontSize: 12, color: c.muted)),
                      if (r['outdated'] == true) CtTag(T('UpdateAvailable'), small: true, tone: Tone.warning),
                    ])),
            Col(T('Installers'),
                minWidth: 300,
                center: false,
                cell: (r, _) {
                  final b = r['build'] as Map?;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (b?['status'] == 'in_progress') Text(T('TechnicianMaking'), style: TextStyle(fontSize: 12, color: c.muted)),
                    if (b?['status'] == 'failure' || b?['status'] == 'error')
                      Text(T('TechnicianFailed', {'msg': b?['message']}), style: TextStyle(fontSize: 12, color: c.danger)),
                    for (final l in rowsOf(r['links']))
                      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        CtButton('${l['name']}', link: true, tone: Tone.primary, onPressed: () => openUrl('${l['url']}')),
                        CtButton(T('CopyLink'), link: true, size: BtnSize.small, onPressed: () => copyText('${l['url']}')),
                      ]),
                  ]);
                }),
            Col('',
                width: 200,
                right: true,
                cell: (r, _) {
                  final base = '${r['base_version'] ?? ''}';
                  if (base.isEmpty) return CtButton(T('TechnicianNeedsBase', {'platform': r['label']}), size: BtnSize.small);
                  final made = (r['links'] as List).isNotEmpty;
                  return CtButton(
                    !made ? T('TechnicianMake') : (r['outdated'] == true ? T('TechnicianUpdate', {'v': base}) : T('TechnicianRemake')),
                    size: BtnSize.small,
                    tone: !made || r['outdated'] == true ? Tone.primary : null,
                    loading: making == r['platform'],
                    onPressed: (r['build'] as Map?)?['status'] == 'in_progress' ? null : () => _make(r),
                  );
                }),
          ]),
        ]),
      ),
    );
  }
}
