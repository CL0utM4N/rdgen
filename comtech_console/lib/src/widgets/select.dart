import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import 'basic.dart';

class Opt<V> {
  final V value;
  final String label;
  final bool disabled;

  /// Optional richer row in the menu; the field still shows [label].
  final Widget? child;
  const Opt(this.value, this.label, {this.disabled = false, this.child});
}

/// el-select for one value.
class CtSelect<V> extends StatelessWidget {
  final V? value;
  final List<Opt<V>> options;
  final ValueChanged<V?>? onChanged;
  final bool clearable;
  final bool filterable;
  final String? placeholder;
  final double? width;
  final bool small;

  const CtSelect({
    super.key,
    required this.value,
    required this.options,
    this.onChanged,
    this.clearable = false,
    this.filterable = false,
    this.placeholder,
    this.width,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final match = options.where((o) => o.value == value);
    return _Dropdown<V>(
      width: width,
      small: small,
      enabled: onChanged != null,
      filterable: filterable,
      options: options,
      placeholder: placeholder ?? T('Select'),
      display: match.isEmpty ? null : Text(match.first.label, overflow: TextOverflow.ellipsis),
      hasValue: match.isNotEmpty,
      onClear: clearable && match.isNotEmpty ? () => onChanged?.call(null) : null,
      isSelected: (v) => v == value,
      onPick: (v, close) {
        close();
        onChanged?.call(v);
      },
    );
  }
}

/// el-select with multiple, showing the choices as tags.
class CtMultiSelect<V> extends StatelessWidget {
  final List<V> values;
  final List<Opt<V>> options;
  final ValueChanged<List<V>>? onChanged;
  final bool filterable;
  final String? placeholder;
  final double? width;

  const CtMultiSelect({
    super.key,
    required this.values,
    required this.options,
    this.onChanged,
    this.filterable = true,
    this.placeholder,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final chosen = options.where((o) => values.contains(o.value)).toList();
    // values without a matching option, such as tags from another address book
    final extra = values.where((v) => !options.any((o) => o.value == v)).map((v) => Opt<V>(v, '$v'));
    final all = [...chosen, ...extra];
    return _Dropdown<V>(
      width: width,
      enabled: onChanged != null,
      filterable: filterable,
      options: options,
      multi: true,
      placeholder: placeholder ?? T('Select'),
      hasValue: all.isNotEmpty,
      display: all.isEmpty
          ? null
          : Wrap(spacing: 4, runSpacing: 4, children: [
              for (final o in all)
                _Chip(o.label, onRemove: onChanged == null ? null : () => onChanged!(values.where((v) => v != o.value).toList())),
            ]),
      isSelected: (v) => values.contains(v),
      onPick: (v, close) {
        final next = values.contains(v) ? values.where((x) => x != v).toList() : [...values, v];
        onChanged?.call(next);
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final VoidCallback? onRemove;
  const _Chip(this.text, {this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return Container(
      height: 22,
      padding: const EdgeInsets.only(left: 7, right: 4),
      decoration: BoxDecoration(color: c.surfaceHover, borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: TextStyle(fontSize: 12, color: c.text2)),
        if (onRemove != null)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onRemove, child: Padding(padding: const EdgeInsets.only(left: 3), child: Icon(Icons.close, size: 12, color: c.muted))),
          ),
      ]),
    );
  }
}

class _Dropdown<V> extends StatefulWidget {
  final double? width;
  final bool small;
  final bool enabled;
  final bool filterable;
  final bool multi;
  final List<Opt<V>> options;
  final String placeholder;
  final Widget? display;
  final bool hasValue;
  final VoidCallback? onClear;
  final bool Function(V) isSelected;
  final void Function(V, VoidCallback close) onPick;

  const _Dropdown({
    super.key,
    this.width,
    this.small = false,
    required this.enabled,
    required this.filterable,
    this.multi = false,
    required this.options,
    required this.placeholder,
    required this.display,
    required this.hasValue,
    this.onClear,
    required this.isSelected,
    required this.onPick,
  });

  @override
  State<_Dropdown<V>> createState() => _DropdownState<V>();
}

class _DropdownState<V> extends State<_Dropdown<V>> {
  final link = LayerLink();
  final portal = OverlayPortalController();
  final filter = TextEditingController();
  final group = Object();
  bool hover = false;
  double fieldWidth = 200;
  bool above = false;

  void _toggle() {
    if (!widget.enabled) return;
    if (portal.isShowing) {
      _close();
    } else {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        fieldWidth = box.size.width;
        final pos = box.localToGlobal(Offset.zero);
        final screen = MediaQuery.of(context).size.height;
        above = pos.dy + box.size.height + 280 > screen && pos.dy > 300;
      }
      filter.clear();
      portal.show();
      setState(() {});
    }
  }

  void _close() {
    if (portal.isShowing) portal.hide();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final open = portal.isShowing;
    final h = widget.small ? 24.0 : 32.0;
    final field = MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          width: widget.width,
          constraints: BoxConstraints(minHeight: h),
          padding: EdgeInsets.symmetric(horizontal: 11, vertical: widget.multi && widget.hasValue ? 4 : 0),
          decoration: BoxDecoration(
            color: widget.enabled ? c.surface2 : c.surfaceHover,
            border: Border.all(color: open ? c.primary : (hover && widget.enabled ? c.muted : c.borderStrong)),
            borderRadius: BorderRadius.circular(ctRadiusSm),
          ),
          child: Row(children: [
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: widget.small ? 12 : 14, color: widget.enabled ? c.text : c.muted),
                child: widget.display ?? Text(widget.placeholder, style: TextStyle(color: c.muted), overflow: TextOverflow.ellipsis),
              ),
            ),
            if (widget.onClear != null && hover)
              GestureDetector(onTap: widget.onClear, child: Icon(Icons.cancel_outlined, size: 14, color: c.muted))
            else
              AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: Icon(Icons.keyboard_arrow_down, size: 16, color: c.muted)),
          ]),
        ),
      ),
    );
    return TapRegion(
      groupId: group,
      onTapOutside: (_) => _close(),
      child: CompositedTransformTarget(
        link: link,
        child: OverlayPortal(
          controller: portal,
          overlayChildBuilder: (ctx) => Theme(
            data: Theme.of(context),
            child: CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              targetAnchor: above ? Alignment.topLeft : Alignment.bottomLeft,
              followerAnchor: above ? Alignment.bottomLeft : Alignment.topLeft,
              offset: Offset(0, above ? -4 : 4),
              child: Align(
                alignment: above ? Alignment.bottomLeft : Alignment.topLeft,
                child: TapRegion(groupId: group, child: _panel(c)),
              ),
            ),
          ),
          child: field,
        ),
      ),
    );
  }

  Widget _panel(CtColors c) {
    return StatefulBuilder(builder: (context, setPanel) {
      final q = filter.text.trim().toLowerCase();
      final shown = q.isEmpty ? widget.options : widget.options.where((o) => o.label.toLowerCase().contains(q)).toList();
      return Material(
        color: c.surface,
        elevation: 8,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ctRadiusSm), side: BorderSide(color: c.border)),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: fieldWidth, maxWidth: fieldWidth < 260 ? 360 : fieldWidth, maxHeight: 300),
          child: IntrinsicWidth(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.filterable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: CtInput(controller: filter, placeholder: T('Filter'), autofocus: true, height: 28, onChanged: (_) => setPanel(() {})),
                ),
              Flexible(
                child: shown.isEmpty
                    ? Padding(padding: const EdgeInsets.all(14), child: Muted(T('NoData'), size: 13))
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shrinkWrap: true,
                        children: [
                          for (final o in shown)
                            _OptionRow(
                              label: o.label,
                              child: o.child,
                              disabled: o.disabled,
                              selected: widget.isSelected(o.value),
                              multi: widget.multi,
                              onTap: () {
                                widget.onPick(o.value, _close);
                                if (widget.multi) setPanel(() {});
                              },
                            ),
                        ],
                      ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

class _OptionRow extends StatefulWidget {
  final String label;
  final Widget? child;
  final bool disabled;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;
  const _OptionRow({required this.label, this.child, required this.disabled, required this.selected, required this.multi, required this.onTap});

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return MouseRegion(
      cursor: widget.disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          color: hover && !widget.disabled ? c.surfaceHover : Colors.transparent,
          child: Row(children: [
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 14,
                  color: widget.disabled ? c.muted : (widget.selected ? c.primary : c.text2),
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                ),
                child: widget.child ?? Text(widget.label),
              ),
            ),
            if (widget.multi && widget.selected) Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.check, size: 14, color: c.primary)),
          ]),
        ),
      ),
    );
  }
}

/// el-dropdown: a button that opens a short menu of actions.
class CtMenuButton extends StatelessWidget {
  final Widget button;
  final List<MenuAction> actions;
  const CtMenuButton({super.key, required this.button, required this.actions});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(ctRadiusSm))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      menuChildren: [
        for (final a in actions) ...[
          if (a.divided) Divider(height: 9, thickness: 1, color: c.border),
          MenuItemButton(
            onPressed: a.onTap,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(140, 34)),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
              overlayColor: WidgetStatePropertyAll(c.surfaceHover),
            ),
            child: Text(a.label, style: TextStyle(fontSize: 14, color: a.danger ? c.danger : c.text2)),
          ),
        ],
      ],
      builder: (context, ctl, _) => GestureDetector(
        onTap: () => ctl.isOpen ? ctl.close() : ctl.open(),
        child: AbsorbPointer(child: button),
      ),
    );
  }
}

class MenuAction {
  final String label;
  final VoidCallback onTap;
  final bool divided;
  final bool danger;
  const MenuAction(this.label, this.onTap, {this.divided = false, this.danger = false});
}
