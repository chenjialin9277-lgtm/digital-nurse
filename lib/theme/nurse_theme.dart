import 'package:flutter/material.dart';

enum NurseVisualStyle {
  techBlue,
  clinicalLight,
  jadeTcm,
  warmCare;

  String get label => switch (this) {
    NurseVisualStyle.techBlue => '深海科技',
    NurseVisualStyle.clinicalLight => '医疗清雅',
    NurseVisualStyle.jadeTcm => '岭南青玉',
    NurseVisualStyle.warmCare => '温馨关怀',
  };

  String get description => switch (this) {
    NurseVisualStyle.techBlue => '深色科技感（推荐）',
    NurseVisualStyle.clinicalLight => '明亮简洁医疗风',
    NurseVisualStyle.jadeTcm => '中医药青玉配色',
    NurseVisualStyle.warmCare => '柔和温暖陪伴感',
  };

  static NurseVisualStyle fromStored(Object? value) => values.firstWhere(
    (style) => style.name == value?.toString(),
    orElse: () => NurseVisualStyle.techBlue,
  );
}

class NursePalette extends ThemeExtension<NursePalette> {
  const NursePalette({
    required this.brightness,
    required this.backgroundStart,
    required this.backgroundEnd,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.primary,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.shadow,
  });

  final Brightness brightness;
  final Color backgroundStart;
  final Color backgroundEnd;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color primary;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  static NursePalette forStyle(NurseVisualStyle style) => switch (style) {
    NurseVisualStyle.techBlue => const NursePalette(
      brightness: Brightness.dark,
      backgroundStart: Color(0xFF050D18),
      backgroundEnd: Color(0xFF0B3041),
      surface: Color(0xEE0D2234),
      surfaceAlt: Color(0xFF112E44),
      border: Color(0xFF24566A),
      primary: Color(0xFF15C9D8),
      accent: Color(0xFF708BFF),
      textPrimary: Color(0xFFF0FAFF),
      textSecondary: Color(0xFFA7C5D0),
      shadow: Color(0x88000A12),
    ),
    NurseVisualStyle.clinicalLight => const NursePalette(
      brightness: Brightness.light,
      backgroundStart: Color(0xFFF7FCFC),
      backgroundEnd: Color(0xFFE7F5F3),
      surface: Color(0xF2FFFFFF),
      surfaceAlt: Color(0xFFF2F9F8),
      border: Color(0xFFD5E9E7),
      primary: Color(0xFF087F8C),
      accent: Color(0xFF6475D8),
      textPrimary: Color(0xFF183F44),
      textSecondary: Color(0xFF607579),
      shadow: Color(0x160B6A72),
    ),
    NurseVisualStyle.jadeTcm => const NursePalette(
      brightness: Brightness.light,
      backgroundStart: Color(0xFFF3FAF5),
      backgroundEnd: Color(0xFFD9EDE3),
      surface: Color(0xF5FFFFFF),
      surfaceAlt: Color(0xFFE8F4ED),
      border: Color(0xFFBED8CB),
      primary: Color(0xFF187866),
      accent: Color(0xFFB78B49),
      textPrimary: Color(0xFF183B32),
      textSecondary: Color(0xFF577269),
      shadow: Color(0x18305848),
    ),
    NurseVisualStyle.warmCare => const NursePalette(
      brightness: Brightness.light,
      backgroundStart: Color(0xFFFFFBF6),
      backgroundEnd: Color(0xFFF3E5D8),
      surface: Color(0xF7FFFEFC),
      surfaceAlt: Color(0xFFFFF3E9),
      border: Color(0xFFE7D3C2),
      primary: Color(0xFFA96549),
      accent: Color(0xFFD58B6C),
      textPrimary: Color(0xFF4B342B),
      textSecondary: Color(0xFF7A645A),
      shadow: Color(0x1C6D4938),
    ),
  };

  ThemeData createTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        primary: primary,
        secondary: accent,
        surface: surface,
      ),
      scaffoldBackgroundColor: backgroundStart,
      fontFamilyFallback: const ['Noto Sans CJK SC', 'sans-serif'],
      extensions: [this],
    );
  }

  static NursePalette of(BuildContext context) =>
      Theme.of(context).extension<NursePalette>()!;

  @override
  NursePalette copyWith({
    Brightness? brightness,
    Color? backgroundStart,
    Color? backgroundEnd,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? primary,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? shadow,
  }) => NursePalette(
    brightness: brightness ?? this.brightness,
    backgroundStart: backgroundStart ?? this.backgroundStart,
    backgroundEnd: backgroundEnd ?? this.backgroundEnd,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    border: border ?? this.border,
    primary: primary ?? this.primary,
    accent: accent ?? this.accent,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    shadow: shadow ?? this.shadow,
  );

  @override
  NursePalette lerp(covariant NursePalette? other, double t) {
    if (other == null) return this;
    return NursePalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      backgroundStart: Color.lerp(backgroundStart, other.backgroundStart, t)!,
      backgroundEnd: Color.lerp(backgroundEnd, other.backgroundEnd, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}
