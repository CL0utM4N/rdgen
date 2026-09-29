import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../theme.dart';
import 'basic.dart';

enum ToastType { success, warning, error, info }

class _Toast {
  final String message;
  final ToastType type;
  _Toast(this.message, this.type);
}

/// ElMessage: short notices at the top of the window.
class Toasts {
  static final items = ValueNotifier<List<_Toast>>([]);

  static void show(String message, [ToastType type = ToastType.info]) {
    if (message.isEmpty) return;
    final t = _Toast(message, type);
    items.value = [...items.value, t];
    Timer(Duration(seconds: type == ToastType.error ? 5 : 3), () {
      items.value = items.value.where((x) => x != t).toList();
    });
  }

  static void success(String m) => show(m, ToastType.success);
  static void warning(String m) => show(m, ToastType.warning);
  static void error(String m) => show(m, ToastType.error);
}

class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ValueListenableBuilder<List<_Toast>>(
      valueListenable: Toasts.items,
      builder: (context, list, _) => Positioned(
        top: 20,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final t in list)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: c.tint(_col(c, t.type), c.dark ? 0.2 : 0.1),
                  border: Border.all(color: c.tint(_col(c, t.type), 0.3)),
                  borderRadius: BorderRadius.circular(ctRadiusSm),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_icon(t.type), size: 16, color: _col(c, t.type)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(t.message,
                        style: TextStyle(fontSize: 14, color: _col(c, t.type), decoration: TextDecoration.none, fontWeight: FontWeight.w400)),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  static Color _col(CtColors c, ToastType t) => switch (t) {
        ToastType.success => c.success,
        ToastType.warning => c.warning,
        ToastType.error => c.danger,
        ToastType.info => c.info,
      };

  static IconData _icon(ToastType t) => switch (t) {
        ToastType.success => Icons.check_circle,
        ToastType.warning => Icons.warning_rounded,
        ToastType.error => Icons.cancel,
        ToastType.info => Icons.info,
      };
}

/// The console theme for dialogs, which open above the whole app.
bool dialogDark = false;

/// el-dialog. [builder] gets a setState for the dialog's own content.
Future<T?> showCtDialog<T>(
  BuildContext context, {
  required String title,
  double width = 600,
  required Widget Function(BuildContext context, StateSetter setState) builder,
  List<Widget> Function(BuildContext context, StateSetter setState)? footer,
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: Colors.black54,
    builder: (ctx) => Theme(
      data: consoleTheme(dialogDark),
      child: Builder(builder: (ctx) {
        final c = ctx.ct;
        final size = MediaQuery.of(ctx).size;
        return Dialog(
          backgroundColor: c.surface,
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ctRadius), side: BorderSide(color: c.border)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: size.height * 0.92),
            child: StatefulBuilder(builder: (ctx, setState) {
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                  child: Row(children: [
                    Expanded(child: Text(title, style: TextStyle(fontSize: 18, color: c.text))),
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: c.muted),
                      splashRadius: 16,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: DefaultTextStyle.merge(style: TextStyle(color: c.text2, fontSize: 14), child: builder(ctx, setState)),
                  ),
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 8, children: footer(ctx, setState)),
                  ),
              ]);
            }),
          ),
        );
      }),
    ),
  );
}

/// ElMessageBox.confirm
Future<bool> confirm(BuildContext context, String message, {String? confirmText, String? title, bool warning = true}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Theme(
      data: consoleTheme(dialogDark),
      child: Builder(builder: (ctx) {
        final c = ctx.ct;
        return Dialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ctRadius), side: BorderSide(color: c.border)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (title != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(title, style: TextStyle(fontSize: 18, color: c.text))),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (warning) Padding(padding: const EdgeInsets.only(right: 10), child: Icon(Icons.warning_rounded, color: c.warning, size: 22)),
                  Expanded(child: Text(message, style: TextStyle(fontSize: 14, color: c.text2, height: 1.5))),
                ]),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop(false)),
                  const SizedBox(width: 12),
                  CtButton(confirmText ?? T('Confirm'), tone: Tone.primary, onPressed: () => Navigator.of(ctx).pop(true)),
                ]),
              ]),
            ),
          ),
        );
      }),
    ),
  );
  return ok == true;
}

/// ElMessageBox.alert
Future<void> alertBox(BuildContext context, String message, {String? title}) => showCtDialog(
      context,
      title: title ?? '',
      width: 460,
      builder: (ctx, _) => SelectableText(message, style: const TextStyle(height: 1.5)),
      footer: (ctx, _) => [CtButton('OK', tone: Tone.primary, onPressed: () => Navigator.of(ctx).pop())],
    );

/// ElMessageBox.prompt
Future<String?> prompt(BuildContext context, String message, {String? title, bool password = false}) {
  final ctl = TextEditingController();
  return showCtDialog<String>(
    context,
    title: title ?? '',
    width: 460,
    builder: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(message),
      const SizedBox(height: 12),
      CtInput(controller: ctl, autofocus: true, password: password, showPassword: password, onSubmitted: (v) => Navigator.of(ctx).pop(v)),
    ]),
    footer: (ctx, _) => [
      CtButton(T('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
      CtButton(T('Confirm'), tone: Tone.primary, onPressed: () => Navigator.of(ctx).pop(ctl.text)),
    ],
  );
}

Future<void> copyText(String text, {String? done}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    Toasts.success(done ?? T('Copied'));
  } catch (_) {
    Toasts.error(T('CopyFailed'));
  }
}

/// A small copy icon next to IDs.
class CopyIcon extends StatelessWidget {
  final String text;
  const CopyIcon(this.text, {super.key});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => copyText(text),
          child: Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.copy_outlined, size: 13, color: context.ct.muted)),
        ),
      );
}
