import 'package:flutter/material.dart';

/// The web console's design tokens (styles/theme.scss), light and dark.
@immutable
class CtColors extends ThemeExtension<CtColors> {
  final bool dark;
  final Color bg, surface, surface2, surfaceHover, border, borderStrong;
  final Color text, text2, muted, sidebar, sidebarText, sidebarSection;
  final Color primary, primaryHover, primarySoft, success, warning, danger, info;

  const CtColors({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surfaceHover,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.muted,
    required this.sidebar,
    required this.sidebarText,
    required this.sidebarSection,
    required this.primary,
    required this.primaryHover,
    required this.primarySoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  static const light = CtColors(
    dark: false,
    bg: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F8FB),
    surfaceHover: Color(0xFFEEF1F6),
    border: Color(0xFFE3E7EE),
    borderStrong: Color(0xFFD3D9E3),
    text: Color(0xFF111827),
    text2: Color(0xFF4B5563),
    muted: Color(0xFF6B7280),
    sidebar: Color(0xFFFFFFFF),
    sidebarText: Color(0xFF374151),
    sidebarSection: Color(0xFF9CA3AF),
    primary: Color(0xFF3366EE),
    primaryHover: Color(0xFF2B58D6),
    primarySoft: Color(0x1A3366EE),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    info: Color(0xFF909399),
  );

  static const darkColors = CtColors(
    dark: true,
    bg: Color(0xFF0B111C),
    surface: Color(0xFF111A28),
    surface2: Color(0xFF0E1623),
    surfaceHover: Color(0xFF172335),
    border: Color(0xFF1D2839),
    borderStrong: Color(0xFF2A3850),
    text: Color(0xFFE6E9EF),
    text2: Color(0xFFB4BCCB),
    muted: Color(0xFF7F8AA0),
    sidebar: Color(0xFF0D1420),
    sidebarText: Color(0xFFC9D0DC),
    sidebarSection: Color(0xFF5F6B80),
    primary: Color(0xFF3F73F5),
    primaryHover: Color(0xFF5584F7),
    primarySoft: Color(0x293F73F5),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFF909399),
  );

  /// [c] faded onto the page, like Element Plus's light-8/light-9 tints.
  Color tint(Color c, double amount) => Color.alphaBlend(c.withOpacity(amount), surface);

  Color tone(Tone t) => switch (t) {
        Tone.primary => primary,
        Tone.success => success,
        Tone.warning => warning,
        Tone.danger => danger,
        Tone.info => info,
        Tone.plain => text2,
      };

  @override
  CtColors copyWith() => this;

  @override
  CtColors lerp(CtColors? other, double t) => t < 0.5 || other == null ? this : other;
}

/// The colour a button or tag takes, as in Element Plus.
enum Tone { primary, success, warning, danger, info, plain }

extension CtContext on BuildContext {
  CtColors get ct => Theme.of(this).extension<CtColors>() ?? CtColors.light;
}

const ctRadius = 12.0;
const ctRadiusSm = 8.0;

ThemeData consoleTheme(bool dark) {
  final c = dark ? CtColors.darkColors : CtColors.light;
  final base = dark ? ThemeData.dark(useMaterial3: false) : ThemeData.light(useMaterial3: false);
  final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text);
  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    cardColor: c.surface,
    dividerColor: c.border,
    primaryColor: c.primary,
    hintColor: c.muted,
    colorScheme: base.colorScheme.copyWith(
      primary: c.primary,
      secondary: c.primary,
      surface: c.surface,
      error: c.danger,
      onPrimary: Colors.white,
      onSurface: c.text,
    ),
    textTheme: text.copyWith(
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, color: c.text),
      bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: c.muted),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: dark ? const Color(0xFFE6E9EF) : const Color(0xFF303133), borderRadius: BorderRadius.circular(4)),
      textStyle: TextStyle(color: dark ? const Color(0xFF111827) : Colors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 300),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.borderStrong),
      radius: const Radius.circular(10),
      thickness: const WidgetStatePropertyAll(8),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : Colors.transparent),
      side: BorderSide(color: c.borderStrong, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.borderStrong),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.primary, selectionColor: c.primarySoft),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ctRadiusSm), side: BorderSide(color: c.border)),
      textStyle: TextStyle(color: c.text, fontSize: 14),
    ),
  );
}
