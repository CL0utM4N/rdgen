import 'package:flutter/material.dart';

import '../console.dart';
import 'basic.dart';
import 'form.dart';
import 'select.dart';
import 'table.dart';

/// The shape of most console pages: a filter bar, a table and paging.
class ListPage extends StatelessWidget {
  final ListCtl ctl;
  final List<Widget> Function() filters;
  final Widget? queryAbove;
  final Widget? queryBelow;
  final List<Col> Function() columns;
  final bool selectable;
  final Widget Function(Row_ row)? expand;
  final List<int> sizes;
  final List<Widget> before;
  final List<Widget> after;

  /// Cards between the filter bar and the table.
  final List<Widget> middle;
  final Widget? tableTop;
  final bool small;

  const ListPage({
    super.key,
    required this.ctl,
    required this.filters,
    required this.columns,
    this.queryAbove,
    this.queryBelow,
    this.selectable = false,
    this.expand,
    this.sizes = const [10, 20, 50, 100],
    this.before = const [],
    this.after = const [],
    this.middle = const [],
    this.tableTop,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => PageColumn([
        ...before,
        QueryBar(above: queryAbove, below: queryBelow, children: filters()),
        ...middle,
        CtCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (tableTop != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: tableTop!),
            CtTable(
              columns: columns(),
              rows: ctl.list,
              loading: ctl.loading,
              small: small,
              selectable: selectable,
              selected: ctl.selected,
              onSelect: ctl.select,
              expand: expand,
            ),
          ]),
        ),
        CtPagination(total: ctl.total, page: ctl.page, pageSize: ctl.pageSize, sizes: sizes, onChange: ctl.setPage),
        ...after,
      ]),
    );
  }
}

/// A text filter bound to a query key; Enter filters.
Widget qText(ListCtl ctl, String key, {double width = 160}) => SizedBox(
      width: width,
      child: CtInput(
        value: '${ctl.query[key] ?? ''}',
        clearable: true,
        onChanged: (v) => ctl.query[key] = v,
        onSubmitted: (_) => ctl.filter(),
      ),
    );

/// A select filter bound to a query key.
Widget qSelect<V>(ListCtl ctl, String key, List<Opt<V>> options, {double width = 160, String? placeholder, ValueChanged<V?>? onChanged, bool filterable = false}) =>
    CtSelect<V>(
      width: width,
      value: ctl.query[key] as V?,
      options: options,
      clearable: true,
      filterable: filterable,
      placeholder: placeholder,
      onChanged: (v) {
        ctl.set(key, v);
        onChanged?.call(v);
      },
    );
