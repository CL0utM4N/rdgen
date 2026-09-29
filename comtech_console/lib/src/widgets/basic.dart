import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

enum BtnSize { small, table, normal, large }

double _btnHeight(BtnSize s) => switch (s) {
      BtnSize.small => 24,
      BtnSize.table => 28,
      BtnSize.normal => 32,
      BtnSize.large => 42,
    };

/// An Element Plus style button. Coloured buttons other than primary use soft
/// tinted backgrounds, as the web console does.
class CtButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Tone? tone;
  final BtnSize size;
  final bool loading;
  final bool link;
  final bool soft;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool expand;

  const CtButton(
    this.label, {
    super.key,
    this.onPressed,
    this.tone,
    this.size = BtnSize.normal,
    this.loading = false,
    this.link = false,
    this.soft = false,
    this.icon,
    this.trailingIcon,
    this.expand = false,
  });

  @override
  State<CtButton> createState() => _CtButtonState();
}

class _CtButtonState extends State<CtButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final enabled = widget.onPressed != null && !widget.loading;
    final tone = widget.tone;
    Color bg, border, fg;
    if (widget.link) {
      bg = Colors.transparent;
      border = Colors.transparent;
      fg = tone == null ? c.text2 : c.tone(tone);
      if (hover && enabled) fg = fg.withOpacity(0.75);
    } else if (tone == null || tone == Tone.plain) {
      bg = hover && enabled ? c.tint(c.primary, 0.08) : c.surface;
      border = hover && enabled ? c.tint(c.primary, 0.35) : c.borderStrong;
      fg = hover && enabled ? c.primary : c.text2;
    } else if (tone == Tone.primary && !widget.soft) {
      bg = hover && enabled ? c.primaryHover : c.primary;
      border = bg;
      fg = Colors.white;
    } else {
      final t = c.tone(tone);
      bg = c.tint(t, hover && enabled ? 0.2 : 0.1);
      border = widget.soft && tone == Tone.primary ? Colors.transparent : c.tint(t, 0.2);
      fg = t;
    }
    final h = _btnHeight(widget.size);
    final fs = widget.size == BtnSize.small || widget.size == BtnSize.table ? 12.0 : (widget.size == BtnSize.large ? 15.0 : 14.0);
    final children = <Widget>[
      if (widget.loading)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: SizedBox(width: fs, height: fs, child: CircularProgressIndicator(strokeWidth: 1.6, color: fg)),
        )
      else if (widget.icon != null)
        Padding(padding: EdgeInsets.only(right: widget.label.isEmpty ? 0 : 6), child: Icon(widget.icon, size: fs + 2, color: fg)),
      if (widget.label.isNotEmpty)
        Flexible(
          child: Text(widget.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: fs, fontWeight: FontWeight.w500, height: 1.1)),
        ),
      if (widget.trailingIcon != null)
        Padding(padding: const EdgeInsets.only(left: 4), child: Icon(widget.trailingIcon, size: fs, color: fg)),
    ];
    return Opacity(
      opacity: enabled || widget.loading ? 1 : 0.5,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: enabled ? widget.onPressed : null,
          child: Container(
            height: widget.link ? null : h,
            constraints: BoxConstraints(minWidth: widget.link ? 0 : h),
            padding: EdgeInsets.symmetric(horizontal: widget.link ? 0 : (widget.size == BtnSize.small ? 8 : (widget.size == BtnSize.table ? 10 : 15))),
            decoration: widget.link
                ? null
                : BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(widget.size == BtnSize.small ? 6 : ctRadiusSm)),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// A square icon button, like the menu and refresh buttons in the header.
class CtIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool spinning;
  const CtIconButton(this.icon, {super.key, this.onPressed, this.tooltip, this.size = 36, this.spinning = false});

  @override
  State<CtIconButton> createState() => _CtIconButtonState();
}

class _CtIconButtonState extends State<CtIconButton> with SingleTickerProviderStateMixin {
  bool hover = false;
  late final AnimationController spin = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didUpdateWidget(covariant CtIconButton old) {
    super.didUpdateWidget(old);
    widget.spinning ? spin.repeat() : spin.reset();
  }

  @override
  void initState() {
    super.initState();
    if (widget.spinning) spin.repeat();
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    Widget b = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: hover ? c.surfaceHover : c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(ctRadiusSm),
          ),
          child: RotationTransition(
            turns: spin,
            child: Icon(widget.icon, size: 16, color: hover ? c.text : c.text2),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) b = Tooltip(message: widget.tooltip!, child: b);
    return b;
  }
}

/// el-tag
class CtTag extends StatelessWidget {
  final String text;
  final Tone tone;
  final bool plain;
  final bool small;
  final bool large;
  final IconData? icon;
  const CtTag(this.text, {super.key, this.tone = Tone.primary, this.plain = false, this.small = false, this.large = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final col = c.tone(tone);
    final h = small ? 20.0 : (large ? 32.0 : 24.0);
    return Container(
      height: h,
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9),
      decoration: BoxDecoration(
        color: plain ? c.surface : c.tint(col, 0.1),
        border: Border.all(color: c.tint(col, plain ? 0.45 : 0.22)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icon, size: 12, color: col)),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: col, fontSize: small ? 11.5 : (large ? 14 : 12), height: 1.1)),
        ),
      ]),
    );
  }
}

/// el-card
class CtCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  const CtCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(ctRadius),
        boxShadow: c.dark
            ? null
            : const [
                BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
                BoxShadow(color: Color(0x0F101828), blurRadius: 3, offset: Offset(0, 1)),
              ],
      ),
      child: child,
    );
  }
}

enum AlertType { info, success, warning, error }

/// el-alert
class CtAlert extends StatelessWidget {
  final String title;
  final String? description;
  final Widget? body;
  final AlertType type;
  final bool showIcon;
  final EdgeInsets margin;
  const CtAlert(this.title,
      {super.key, this.description, this.body, this.type = AlertType.info, this.showIcon = true, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final col = switch (type) {
      AlertType.info => c.info,
      AlertType.success => c.success,
      AlertType.warning => c.warning,
      AlertType.error => c.danger,
    };
    final icon = switch (type) {
      AlertType.info => Icons.info,
      AlertType.success => Icons.check_circle,
      AlertType.warning => Icons.warning_rounded,
      AlertType.error => Icons.cancel,
    };
    final hasBody = (description != null && description!.isNotEmpty) || body != null;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(color: c.tint(col, c.dark ? 0.16 : 0.1), borderRadius: BorderRadius.circular(4)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showIcon) Padding(padding: const EdgeInsets.only(right: 8, top: 1), child: Icon(icon, size: hasBody ? 22 : 16, color: col)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: col, fontSize: 13, fontWeight: hasBody ? FontWeight.w600 : FontWeight.w400, height: 1.4)),
            if (description != null && description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(description!, style: TextStyle(color: col, fontSize: 12, height: 1.45)),
              ),
            if (body != null) Padding(padding: const EdgeInsets.only(top: 4), child: DefaultTextStyle.merge(style: TextStyle(color: col, fontSize: 12), child: body!)),
          ]),
        ),
      ]),
    );
  }
}

/// el-switch, with optional text inside the pill.
class CtSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? activeText;
  final String? inactiveText;
  final Color? offColor;
  final bool loading;
  const CtSwitch({super.key, required this.value, this.onChanged, this.activeText, this.inactiveText, this.offColor, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final text = value ? activeText : inactiveText;
    final bg = value ? c.primary : (offColor ?? c.borderStrong);
    final enabled = onChanged != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(
          onTap: enabled ? () => onChanged!(!value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 20,
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (value && text != null)
                Padding(padding: const EdgeInsets.only(left: 5, right: 4), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1))),
              if (!value) _knob(),
              if (value && text == null) const SizedBox(width: 20),
              if (!value && text != null)
                Padding(padding: const EdgeInsets.only(left: 4, right: 5), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1))),
              if (!value && text == null) const SizedBox(width: 20),
              if (value) _knob(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _knob() => Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: loading ? const Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 1.5)) : null,
      );
}

/// el-checkbox with its label.
class CtCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? label;
  final bool? tristate;
  const CtCheckbox({super.key, required this.value, this.onChanged, this.label, this.tristate});

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: 18,
      height: 18,
      child: Checkbox(
        value: tristate == true ? null : value,
        tristate: tristate == true,
        onChanged: onChanged == null ? null : (v) => onChanged!(tristate == true ? false : v ?? false),
      ),
    );
    if (label == null) return box;
    return MouseRegion(
      cursor: onChanged == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          box,
          const SizedBox(width: 8),
          Flexible(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: label!)),
        ]),
      ),
    );
  }
}

/// A row of el-radio options.
class CtRadios<V> extends StatelessWidget {
  final V? value;
  final List<(V, String)> options;
  final ValueChanged<V>? onChanged;
  final bool vertical;
  const CtRadios({super.key, required this.value, required this.options, this.onChanged, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final items = options
        .map((o) => MouseRegion(
              cursor: onChanged == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onChanged == null ? null : () => onChanged!(o.$1),
                child: Padding(
                  padding: EdgeInsets.only(right: vertical ? 0 : 24, bottom: vertical ? 6 : 0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: o.$1 == value ? c.primary : c.surface,
                        border: Border.all(color: o.$1 == value ? c.primary : c.borderStrong),
                      ),
                      child: o.$1 == value
                          ? Center(child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)))
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(o.$2, style: TextStyle(fontSize: 14, color: o.$1 == value ? c.primary : c.text2)),
                  ]),
                ),
              ),
            ))
        .toList();
    return Opacity(
      opacity: onChanged == null ? 0.6 : 1,
      child: vertical
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: items)
          : Wrap(runSpacing: 8, children: items),
    );
  }
}

/// el-radio-button: joined buttons where one is selected.
class CtSegmented<V> extends StatelessWidget {
  final V? value;
  final List<(V, String)> options;
  final ValueChanged<V>? onChanged;
  final bool small;
  const CtSegmented({super.key, required this.value, required this.options, this.onChanged, this.small = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return Opacity(
      opacity: onChanged == null ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: c.borderStrong), borderRadius: BorderRadius.circular(ctRadiusSm)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ctRadiusSm - 1),
          child: IntrinsicHeight(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) VerticalDivider(width: 1, thickness: 1, color: c.borderStrong),
                MouseRegion(
                  cursor: onChanged == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onChanged == null ? null : () => onChanged!(options[i].$1),
                    child: Container(
                      height: small ? 24 : 32,
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(horizontal: small ? 11 : 15),
                      color: options[i].$1 == value ? c.primary : c.surface,
                      child: Text(options[i].$2,
                          style: TextStyle(
                            fontSize: small ? 12 : 14,
                            color: options[i].$1 == value ? Colors.white : c.text2,
                          )),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// el-input
class CtInput extends StatefulWidget {
  final TextEditingController? controller;
  final String? value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? placeholder;
  final bool password;
  final bool showPassword;
  final bool clearable;
  final bool enabled;
  final int rows;
  final double? width;
  final int? maxLength;
  final Widget? append;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool mono;
  final double height;
  final TextInputType? keyboardType;

  const CtInput({
    super.key,
    this.controller,
    this.value,
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.password = false,
    this.showPassword = false,
    this.clearable = false,
    this.enabled = true,
    this.rows = 1,
    this.width,
    this.maxLength,
    this.append,
    this.autofocus = false,
    this.focusNode,
    this.mono = false,
    this.height = 32,
    this.keyboardType,
  });

  @override
  State<CtInput> createState() => _CtInputState();
}

class _CtInputState extends State<CtInput> {
  late final TextEditingController ctl = widget.controller ?? TextEditingController(text: widget.value ?? '');
  late final FocusNode focus = widget.focusNode ?? FocusNode();
  bool obscure = true;
  bool hover = false;

  @override
  void initState() {
    super.initState();
    focus.addListener(_refresh);
    ctl.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant CtInput old) {
    super.didUpdateWidget(old);
    if (widget.controller == null && widget.value != null && widget.value != ctl.text) {
      ctl.value = TextEditingValue(text: widget.value!, selection: TextSelection.collapsed(offset: widget.value!.length));
    }
  }

  @override
  void dispose() {
    focus.removeListener(_refresh);
    ctl.removeListener(_refresh);
    if (widget.controller == null) ctl.dispose();
    if (widget.focusNode == null) focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final multi = widget.rows > 1;
    final borderCol = focus.hasFocus ? c.primary : (hover && widget.enabled ? c.muted : c.borderStrong);
    final field = TextField(
      controller: ctl,
      focusNode: focus,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: widget.password && obscure,
      minLines: multi ? widget.rows : 1,
      maxLines: multi ? widget.rows + 6 : 1,
      maxLength: widget.maxLength,
      keyboardType: widget.keyboardType ?? (multi ? TextInputType.multiline : null),
      style: TextStyle(fontSize: 14, color: widget.enabled ? c.text : c.muted, fontFamily: widget.mono ? 'monospace' : null),
      cursorColor: c.primary,
      cursorHeight: 16,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: widget.placeholder,
        hintStyle: TextStyle(color: c.muted, fontSize: 14),
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: multi ? 6 : (widget.height - 18) / 2),
      ),
    );
    Widget box = MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Container(
        width: widget.width,
        constraints: multi ? null : BoxConstraints.tightFor(height: widget.height),
        decoration: BoxDecoration(
          color: widget.enabled ? c.surface2 : c.surfaceHover,
          border: Border.all(color: borderCol),
          borderRadius: widget.append == null
              ? BorderRadius.circular(ctRadiusSm)
              : const BorderRadius.horizontal(left: Radius.circular(ctRadiusSm)),
        ),
        child: Row(crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
          Expanded(child: field),
          if (widget.clearable && ctl.text.isNotEmpty && hover && widget.enabled)
            _suffix(Icons.cancel_outlined, () {
              ctl.clear();
              widget.onChanged?.call('');
            }),
          if (widget.password && widget.showPassword) _suffix(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, () => setState(() => obscure = !obscure)),
        ]),
      ),
    );
    if (widget.append != null) {
      box = Row(mainAxisSize: widget.width == null ? MainAxisSize.max : MainAxisSize.min, children: [
        widget.width == null ? Expanded(child: box) : box,
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border(top: BorderSide(color: c.borderStrong), right: BorderSide(color: c.borderStrong), bottom: BorderSide(color: c.borderStrong)),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(ctRadiusSm)),
          ),
          child: ClipRRect(borderRadius: const BorderRadius.horizontal(right: Radius.circular(ctRadiusSm - 1)), child: widget.append!),
        ),
      ]);
    }
    return box;
  }

  Widget _suffix(IconData icon, VoidCallback onTap) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(icon, size: 14, color: context.ct.muted)),
        ),
      );
}

/// el-input-number with its controls on the right.
class CtNumberInput extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;
  final double width;
  const CtNumberInput({super.key, required this.value, this.min = 0, this.max = 1 << 30, this.onChanged, this.width = 150});

  @override
  State<CtNumberInput> createState() => _CtNumberInputState();
}

class _CtNumberInputState extends State<CtNumberInput> {
  late final ctl = TextEditingController(text: '${widget.value}');
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _commit(ctl.text);
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant CtNumberInput old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && ctl.text != '${widget.value}') ctl.text = '${widget.value}';
  }

  @override
  void dispose() {
    ctl.dispose();
    focus.dispose();
    super.dispose();
  }

  void _commit(String s) {
    var v = int.tryParse(s.trim()) ?? widget.value;
    v = v.clamp(widget.min, widget.max);
    ctl.text = '$v';
    if (v != widget.value) widget.onChanged?.call(v);
  }

  void _step(int d) {
    final v = (widget.value + d).clamp(widget.min, widget.max);
    ctl.text = '$v';
    widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final enabled = widget.onChanged != null;
    Widget stepper(IconData i, int d, bool top) => Expanded(
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
              onTap: enabled ? () => _step(d) : null,
              child: Container(
                width: 32,
                decoration: BoxDecoration(
                  color: c.surface2,
                  border: Border(left: BorderSide(color: c.borderStrong), bottom: top ? BorderSide(color: c.borderStrong) : BorderSide.none),
                ),
                child: Icon(i, size: 12, color: c.text2),
              ),
            ),
          ),
        );
    return Container(
      width: widget.width,
      height: 32,
      decoration: BoxDecoration(
        color: enabled ? c.surface2 : c.surfaceHover,
        border: Border.all(color: focus.hasFocus ? c.primary : c.borderStrong),
        borderRadius: BorderRadius.circular(ctRadiusSm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ctRadiusSm - 1),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: ctl,
              focusNode: focus,
              enabled: enabled,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.text),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
              onSubmitted: _commit,
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 7)),
            ),
          ),
          Column(children: [stepper(Icons.keyboard_arrow_up, 1, true), stepper(Icons.keyboard_arrow_down, -1, false)]),
        ]),
      ),
    );
  }
}

/// el-progress as a plain bar.
class CtBar extends StatelessWidget {
  final double fraction;
  final double height;
  final Color? color;
  const CtBar({super.key, required this.fraction, this.height = 8, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: c.surfaceHover,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.isNaN ? 0 : fraction.clamp(0, 1),
          child: Container(decoration: BoxDecoration(color: color ?? c.success, borderRadius: BorderRadius.circular(height))),
        ),
      ),
    );
  }
}

/// el-tabs, line style.
class CtTabs<V> extends StatelessWidget {
  final V value;
  final List<(V, String)> tabs;
  final ValueChanged<V> onChanged;
  const CtTabs({super.key, required this.value, required this.tabs, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 2))),
      child: Wrap(children: [
        for (final t in tabs)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged(t.$1),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.$1 == value ? c.primary : Colors.transparent, width: 2)),
                ),
                transform: Matrix4.translationValues(0, 2, 0),
                child: Text(t.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: t.$1 == value ? c.primary : c.text2)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// el-collapse with one item.
class CtCollapse extends StatefulWidget {
  final Widget title;
  final Widget child;
  final bool initiallyOpen;
  const CtCollapse({super.key, required this.title, required this.child, this.initiallyOpen = false});

  @override
  State<CtCollapse> createState() => _CtCollapseState();
}

class _CtCollapseState extends State<CtCollapse> {
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border), bottom: BorderSide(color: c.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => open = !open),
            child: Container(
              height: 48,
              color: Colors.transparent,
              child: Row(children: [
                Expanded(child: DefaultTextStyle.merge(style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.text), child: widget.title)),
                AnimatedRotation(turns: open ? 0.25 : 0, duration: const Duration(milliseconds: 150), child: Icon(Icons.chevron_right, size: 16, color: c.muted)),
              ]),
            ),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.only(bottom: 20), child: widget.child),
      ]),
    );
  }
}

/// Grey text used for help lines under fields.
class Muted extends StatelessWidget {
  final String text;
  final double size;
  final EdgeInsets padding;
  final Color? color;
  const Muted(this.text, {super.key, this.size = 13, this.padding = EdgeInsets.zero, this.color});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: Text(text, style: TextStyle(fontSize: size, color: color ?? context.ct.muted, height: 1.5)));
}

/// A page heading inside a card, with its help line.
class CardHead extends StatelessWidget {
  final String title;
  final String? help;
  final Widget? trailing;
  final double titleSize;
  const CardHead(this.title, {super.key, this.help, this.trailing, this.titleSize = 20});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w600)),
          if (help != null && help!.isNotEmpty) Muted(help!, padding: const EdgeInsets.only(top: 6)),
        ]),
      ),
      if (trailing != null) Padding(padding: const EdgeInsets.only(left: 16), child: trailing!),
    ]);
  }
}

/// Monospace text in a tinted box, like <code> and <pre>.
class CodeBox extends StatelessWidget {
  final String text;
  final bool block;
  const CodeBox(this.text, {super.key, this.block = false});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return Container(
      width: block ? double.infinity : null,
      padding: block ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.surface2, border: block ? Border.all(color: c.border) : null, borderRadius: BorderRadius.circular(6)),
      child: SelectableText(text, style: TextStyle(fontFamily: 'monospace', fontSize: block ? 12.5 : 13, color: c.text, height: 1.45)),
    );
  }
}

/// A coloured status dot.
class Dot extends StatelessWidget {
  final Color color;
  final double size;
  final bool glow;
  const Dot(this.color, {super.key, this.size = 8, this.glow = false});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: glow ? [BoxShadow(color: color.withOpacity(0.25), spreadRadius: 3)] : null,
        ),
      );
}

/// Loading veil over a card, like v-loading.
class Loading extends StatelessWidget {
  final bool loading;
  final Widget child;
  final double minHeight;
  const Loading({super.key, required this.loading, required this.child, this.minHeight = 0});

  @override
  Widget build(BuildContext context) {
    if (!loading) return child;
    final c = context.ct;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(children: [
        child,
        Positioned.fill(
          child: Container(
            color: c.surface.withOpacity(0.7),
            alignment: Alignment.center,
            child: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
        ),
      ]),
    );
  }
}
