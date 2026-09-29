import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'basic.dart';

/// el-form-item: a right-aligned label beside its field, with help below.
class FormItem extends StatelessWidget {
  final String? label;
  final Widget child;
  final double labelWidth;
  final bool required;
  final String? help;
  final bool warnHelp;
  final bool top;
  final EdgeInsets margin;

  const FormItem({
    super.key,
    this.label,
    required this.child,
    this.labelWidth = 120,
    this.required = false,
    this.help,
    this.warnHelp = false,
    this.top = false,
    this.margin = const EdgeInsets.only(bottom: 18),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final lbl = label == null
        ? null
        : Text.rich(
            TextSpan(children: [
              if (required) TextSpan(text: '* ', style: TextStyle(color: c.danger)),
              TextSpan(text: label),
            ]),
            textAlign: top ? TextAlign.left : TextAlign.right,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.text2, height: 1.3),
          );
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      child,
      if (help != null && help!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(help!, style: TextStyle(fontSize: 12, height: 1.45, color: warnHelp ? c.warning : c.muted)),
        ),
    ]);
    if (top) {
      return Padding(
        padding: margin,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (lbl != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: lbl),
          body,
        ]),
      );
    }
    return Padding(
      padding: margin,
      child: LayoutBuilder(builder: (context, box) {
        // stack the label over its field when the dialog is narrow
        if (box.maxWidth < labelWidth + 200) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (lbl != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Align(alignment: Alignment.centerLeft, child: lbl)),
            body,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: labelWidth,
            child: Padding(padding: const EdgeInsets.only(right: 12, top: 7), child: lbl ?? const SizedBox()),
          ),
          Expanded(child: body),
        ]);
      }),
    );
  }
}

/// The filter bar at the top of list pages: labelled fields and buttons that
/// wrap onto new lines.
class QueryBar extends StatelessWidget {
  final List<Widget> children;
  final Widget? below;
  final Widget? above;
  const QueryBar({super.key, required this.children, this.below, this.above});

  @override
  Widget build(BuildContext context) {
    return CtCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (above != null) above!,
        Wrap(spacing: 24, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: children),
        if (below != null) Padding(padding: const EdgeInsets.only(top: 12), child: below!),
      ]),
    );
  }
}

/// One labelled field in a [QueryBar].
class QueryField extends StatelessWidget {
  final String label;
  final Widget child;
  final double width;
  const QueryField(this.label, this.child, {super.key, this.width = 160});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: context.ct.text2)),
      const SizedBox(width: 12),
      SizedBox(width: width, child: child),
    ]);
  }
}

/// Buttons side by side.
class Buttons extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final WrapAlignment alignment;
  const Buttons(this.children, {super.key, this.spacing = 12, this.alignment = WrapAlignment.start});

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: spacing, runSpacing: 8, alignment: alignment, crossAxisAlignment: WrapCrossAlignment.center, children: children);
}

/// Cards stacked down a page.
class PageColumn extends StatelessWidget {
  final List<Widget> children;
  const PageColumn(this.children, {super.key});

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[];
    for (final w in children) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 16));
      out.add(w);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}

/// Just enough Markdown for the welcome message and the API reference:
/// headings, paragraphs, lists, code, tables, bold, inline code and links.
class MarkdownView extends StatelessWidget {
  final String text;
  const MarkdownView(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ct;
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final out = <Widget>[];
    var i = 0;
    final para = <String>[];
    void flush() {
      if (para.isEmpty) return;
      out.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: _inline(context, para.join(' '))));
      para.clear();
    }

    while (i < lines.length) {
      final line = lines[i];
      final t = line.trim();
      if (t.startsWith('```')) {
        flush();
        final code = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          code.add(lines[i]);
          i++;
        }
        i++;
        out.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: CodeBox(code.join('\n'), block: true)));
        continue;
      }
      final h = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(t);
      if (h != null) {
        flush();
        final level = h.group(1)!.length;
        out.add(Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 14 : 8, bottom: 8),
          child: _inline(context, h.group(2)!, style: TextStyle(fontSize: const [22.0, 19.0, 16.0, 14.0][level - 1], fontWeight: FontWeight.w600, color: c.text)),
        ));
        i++;
        continue;
      }
      if (t.startsWith('|')) {
        flush();
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final cells = lines[i].trim().replaceAll(RegExp(r'^\||\|$'), '').split(RegExp(r'(?<!\\)\|')).map((s) => s.trim().replaceAll(r'\|', '|')).toList();
          if (!cells.every((s) => RegExp(r'^:?-+:?$').hasMatch(s))) rows.add(cells);
          i++;
        }
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Table(
            border: TableBorder.all(color: c.border),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: BoxDecoration(color: r == 0 ? c.surface2 : null),
                  children: [
                    for (var k = 0; k < rows[0].length; k++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: _inline(context, k < rows[r].length ? rows[r][k] : '',
                            style: TextStyle(fontSize: 13, fontWeight: r == 0 ? FontWeight.w600 : FontWeight.w400, color: c.text2)),
                      ),
                  ],
                ),
            ],
          ),
        ));
        continue;
      }
      final li = RegExp(r'^(\s*)([-*]|\d+\.)\s+(.*)$').firstMatch(line);
      if (li != null) {
        flush();
        final indent = li.group(1)!.length ~/ 2;
        final marker = li.group(2)!;
        out.add(Padding(
          padding: EdgeInsets.only(left: 8.0 + indent * 18, bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text(marker.endsWith('.') ? marker : '•', style: TextStyle(color: c.text2))),
            Expanded(child: _inline(context, li.group(3)!)),
          ]),
        ));
        i++;
        continue;
      }
      if (t.isEmpty) {
        flush();
      } else if (t == '---') {
        flush();
        out.add(Divider(color: c.border, height: 24));
      } else {
        para.add(t);
      }
      i++;
    }
    flush();
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: out));
  }

  Widget _inline(BuildContext context, String s, {TextStyle? style}) {
    final c = context.ct;
    final base = style ?? TextStyle(fontSize: 14, height: 1.55, color: c.text2);
    final spans = <InlineSpan>[];
    final re = RegExp(r'`([^`]+)`|\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)]+)\)');
    var last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: TextStyle(fontFamily: 'monospace', backgroundColor: c.surface2, color: c.text)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: const TextStyle(fontWeight: FontWeight.w600)));
      } else {
        final url = m.group(4)!;
        spans.add(TextSpan(
          text: m.group(3),
          style: TextStyle(color: c.primary),
          recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url)),
        ));
      }
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
