import 'dart:math' as math;
import 'dart:math' show max, min;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import 'basic.dart';
import 'select.dart';

typedef Row_ = Map<String, dynamic>;

/// One el-table-column. [width] is fixed; otherwise the column takes at
/// least [minWidth] and shares any spare room.
class Col {
  final String label;
  final double? width;
  final double minWidth;
  final bool center;
  final bool right;

  /// Shows a field as text; ignored when [cell] is set.
  final String? prop;
  final Widget Function(Row_ row, int index)? cell;

  /// One line with an ellipsis and the full text on hover.
  final bool ellipsis;

  const Col(this.label,
      {this.width, this.minWidth = 80, this.center = true, this.right = false, this.prop, this.cell, this.ellipsis = false});
}

/// Reads "peer.version" style paths.
dynamic pick(Row_ row, String path) {
  dynamic v = row;
  for (final part in path.split('.')) {
    if (v is Map) {
      v = v[part];
    } else {
      return null;
    }
  }
  return v;
}

String show(dynamic v) {
  if (v == null) return '';
  if (v is List) return v.join(', ');
  return '$v';
}

/// el-table with borders, optional selection, expandable rows and an empty
/// state. It scrolls sideways when the columns don't fit.
class CtTable extends StatefulWidget {
  final List<Col> columns;
  final List<Row_> rows;
  final bool loading;
  final bool selectable;
  final Set<int>? selected;
  final ValueChanged<Set<int>>? onSelect;
  final Widget Function(Row_ row)? expand;
  final bool small;
  final bool border;
  final String? empty;
  final double? maxHeight;

  const CtTable({
    super.key,
    required this.columns,
    required this.rows,
    this.loading = false,
    this.selectable = false,
    this.selected,
    this.onSelect,
    this.expand,
    this.small = false,
    this.border = true,
    this.empty,
    this.maxHeight,
  });

  @override
  State<CtTable> createState() => _CtTableState();
}

class _CtTableState extends State<CtTable> {
  final expanded = <int>{};
  final hScroll = ScrollController();
  final vScroll = ScrollController();
  int? hover;

  @override
  void didUpdateWidget(covariant CtTable old) {
    super.didUpdateWidget(old);
    if (!identical(old.rows, widget.rows)) expanded.clear();
  }

  @override
  void dispose() {
    hScroll.dispose();
    vScroll.dispose();
    super.dispose();
  }

  List<double> _widths(double available) {
    final cols = widget.columns;
    final double fixed = (widget.selectable ? 50.0 : 0.0) + (widget.expand != null ? 48.0 : 0.0);
    // timestamps read badly when wrapped, so they keep room for one line
    double pref(Col c) => c.width ?? (c.prop == 'created_at' || c.prop == 'updated_at' ? max(c.minWidth, 150.0) : c.minWidth);
    final base = cols.map(pref).toList();
    final total = base.fold<double>(fixed, (a, b) => a + b);
    final flex = [for (var i = 0; i < cols.length; i++) if (cols[i].width == null) i];
    if (total >= available) {
      // squeeze the flexible columns before scrolling sideways, as el-table does
      double room(int i) => cols[i].prop == 'created_at' || cols[i].prop == 'updated_at' ? 0 : max(0, base[i] - 90);
      final give = flex.fold<double>(0, (a, i) => a + room(i));
      if (give <= 0) return base;
      final cut = min(total - available, give);
      return [for (var i = 0; i < cols.length; i++) cols[i].width == null ? base[i] - room(i) * cut / give : base[i]];
    }
    final spare = available - total;
    if (flex.isEmpty) {
      // stretch every column, like a table with only fixed widths
      final scale = (available - fixed) / (total - fixed);
      return base.map((w) => w * scale).toList();
    }
    final flexTotal = flex.fold<double>(0, (a, i) => a + base[i]);
    return [for (var i = 0; i < cols.length; i++) cols[i].width == null ? base[i] + spare * base[i] / flexTotal : base[i]];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    return LayoutBuilder(builder: (context, box) {
      final available = box.maxWidth.isFinite ? box.maxWidth - 2 : 1000.0;
      final widths = _widths(available);
      final tableWidth = math.max<double>(available, widths.fold<double>(0, (a, b) => a + b) + (widget.selectable ? 50 : 0) + (widget.expand != null ? 48 : 0));
      final sel = widget.selected ?? <int>{};
      final allSel = widget.rows.isNotEmpty && widget.rows.asMap().keys.every(sel.contains);

      Widget cellBox(double w, Widget child, {bool header = false, bool center = true, bool right = false, bool last = false}) => Container(
            width: w,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: header ? 9 : (widget.small ? 6 : 9)),
            decoration: BoxDecoration(
              border: Border(right: widget.border && !last ? BorderSide(color: c.border) : BorderSide.none),
            ),
            alignment: right ? Alignment.centerRight : (center ? Alignment.center : Alignment.centerLeft),
            child: child,
          );

      final header = Container(
        color: c.surface2,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.expand != null) cellBox(48, const SizedBox(), header: true),
            if (widget.selectable)
              cellBox(
                50,
                CtCheckbox(
                  value: allSel,
                  onChanged: widget.rows.isEmpty
                      ? null
                      : (v) => widget.onSelect?.call(v ? widget.rows.asMap().keys.toSet() : <int>{}),
                ),
                header: true,
              ),
            for (var i = 0; i < widget.columns.length; i++)
              cellBox(
                widths[i],
                Text(widget.columns[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.muted)),
                header: true,
                center: widget.columns[i].center,
                right: widget.columns[i].right,
                last: i == widget.columns.length - 1,
              ),
          ]),
        ),
      );

      final rows = <Widget>[];
      for (var r = 0; r < widget.rows.length; r++) {
        final row = widget.rows[r];
        final open = expanded.contains(r);
        rows.add(MouseRegion(
          onEnter: (_) => setState(() => hover = r),
          onExit: (_) => setState(() => hover = hover == r ? null : hover),
          child: Container(
            decoration: BoxDecoration(
              color: hover == r ? c.surfaceHover : c.surface,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (widget.expand != null)
                  cellBox(
                    48,
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => open ? expanded.remove(r) : expanded.add(r)),
                        child: AnimatedRotation(
                          turns: open ? 0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(Icons.chevron_right, size: 16, color: c.muted),
                        ),
                      ),
                    ),
                  ),
                if (widget.selectable)
                  cellBox(
                    50,
                    CtCheckbox(
                      value: sel.contains(r),
                      onChanged: (v) {
                        final next = {...sel};
                        v ? next.add(r) : next.remove(r);
                        widget.onSelect?.call(next);
                      },
                    ),
                  ),
                for (var i = 0; i < widget.columns.length; i++)
                  cellBox(
                    widths[i],
                    _cell(widget.columns[i], row, r, c),
                    center: widget.columns[i].center,
                    right: widget.columns[i].right,
                    last: i == widget.columns.length - 1,
                  ),
              ]),
            ),
          ),
        ));
        if (open) {
          rows.add(Container(
            width: tableWidth,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
            child: widget.expand!(row),
          ));
        }
      }
      if (widget.rows.isEmpty) {
        rows.add(Container(
          width: tableWidth,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
          child: Text(widget.loading ? '' : (widget.empty ?? T('NoData')), style: TextStyle(color: c.muted, fontSize: 13)),
        ));
      }

      Widget body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
      if (widget.maxHeight != null) {
        body = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight!),
          child: Scrollbar(controller: vScroll, child: SingleChildScrollView(controller: vScroll, child: body)),
        );
      }
      final table = SizedBox(
        width: tableWidth,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: widget.small ? 12.5 : 13, color: c.text2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [header, body]),
        ),
      );
      return Loading(
        loading: widget.loading,
        minHeight: 100,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(ctRadiusSm),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ctRadiusSm - 1),
            child: tableWidth > available + 2
                ? Scrollbar(
                    controller: hScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(controller: hScroll, scrollDirection: Axis.horizontal, child: table),
                  )
                : table,
          ),
        ),
      );
    });
  }

  Widget _cell(Col col, Row_ row, int index, CtColors c) {
    if (col.cell != null) return col.cell!(row, index);
    final text = show(pick(row, col.prop ?? ''));
    if (col.ellipsis) {
      return Tooltip(
        message: text,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: col.center ? TextAlign.center : TextAlign.start),
      );
    }
    return Text(text, textAlign: col.center ? TextAlign.center : TextAlign.start);
  }
}

/// Buttons in a table's actions column, wrapping when they don't fit.
class Actions_ extends StatelessWidget {
  final List<Widget> children;
  const Actions_(this.children, {super.key});

  @override
  Widget build(BuildContext context) =>
      Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: children);
}

/// el-pagination with "prev, pager, next, sizes, jumper".
class CtPagination extends StatefulWidget {
  final int total;
  final int page;
  final int pageSize;
  final List<int> sizes;
  final void Function(int page, int pageSize) onChange;
  const CtPagination({super.key, required this.total, required this.page, required this.pageSize, this.sizes = const [10, 20, 50, 100], required this.onChange});

  @override
  State<CtPagination> createState() => _CtPaginationState();
}

class _CtPaginationState extends State<CtPagination> {
  final jump = TextEditingController();

  @override
  void dispose() {
    jump.dispose();
    super.dispose();
  }

  int get pages => math.max(1, (widget.total / widget.pageSize).ceil());

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    jump.text = '${widget.page}';
    Widget box(Widget child, {bool active = false, VoidCallback? onTap}) => MouseRegion(
          cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 32),
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: active ? c.primary : c.surface2,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                widthFactor: 1,
                child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: active ? Colors.white : (onTap == null ? c.muted : c.text2)),
                  child: child,
                ),
              ),
            ),
          ),
        );
    final p = widget.page;
    final n = pages;
    final nums = <int>[];
    if (n <= 7) {
      for (var i = 1; i <= n; i++) {
        nums.add(i);
      }
    } else {
      nums.add(1);
      final start = math.max(2, math.min(p - 2, n - 5));
      final end = math.min(n - 1, math.max(p + 2, 6));
      if (start > 2) nums.add(-1);
      for (var i = start; i <= end; i++) {
        nums.add(i);
      }
      if (end < n - 1) nums.add(-2);
      nums.add(n);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
        box(const Icon(Icons.chevron_left, size: 16), onTap: p > 1 ? () => widget.onChange(p - 1, widget.pageSize) : null),
        for (final i in nums)
          i < 0
              ? box(const Text('…'), onTap: () => widget.onChange(i == -1 ? math.max(1, p - 5) : math.min(n, p + 5), widget.pageSize))
              : box(Text('$i'), active: i == p, onTap: i == p ? null : () => widget.onChange(i, widget.pageSize)),
        box(const Icon(Icons.chevron_right, size: 16), onTap: p < n ? () => widget.onChange(p + 1, widget.pageSize) : null),
        const SizedBox(width: 12),
        CtSelect<int>(
          width: 120,
          value: widget.pageSize,
          options: [for (final s in widget.sizes) Opt(s, '$s/page')],
          onChanged: (v) => widget.onChange(1, v ?? widget.pageSize),
        ),
        const SizedBox(width: 16),
        Text('Go to', style: TextStyle(fontSize: 14, color: c.text2)),
        const SizedBox(width: 8),
        CtInput(
          controller: jump,
          width: 56,
          onSubmitted: (s) {
            final v = int.tryParse(s);
            if (v != null) widget.onChange(v.clamp(1, n), widget.pageSize);
          },
        ),
      ]),
    );
  }
}
