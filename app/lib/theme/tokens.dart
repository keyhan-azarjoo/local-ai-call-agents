import 'package:flutter/material.dart';

/// LocalAILine palette — "telephone exchange": navy switchboard, amber line
/// lamps, off-hook green.
class LL {
  static const navy = Color(0xFF10233A);
  static const navy2 = Color(0xFF183150);
  static const navy3 = Color(0xFF22406A);
  static const amber = Color(0xFFF2A93B);
  static const green = Color(0xFF2BB673);
  static const red = Color(0xFFE5484D);
  static const blue = Color(0xFF3A7BD5);
  static const navMuted = Color(0xFF6F86A3);
  static const navText = Color(0xFFC9D6E6);

  static const display = 'Bricolage';
  static const body = 'Plex';
  static const mono = 'PlexMono';

  static const r = 10.0;
  static const rSm = 6.0;
}

/// Surface colours that change with light / dark.
@immutable
class LLColors extends ThemeExtension<LLColors> {
  const LLColors({
    required this.canvas,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.amberSoft,
    required this.greenSoft,
    required this.redSoft,
    required this.blueSoft,
    required this.amberInk,
    required this.greenInk,
    required this.redInk,
    required this.blueInk,
    required this.shell,
  });

  final Color canvas, panel, ink, muted, line;
  final Color amberSoft, greenSoft, redSoft, blueSoft;
  final Color amberInk, greenInk, redInk, blueInk;
  final Color shell;

  static const light = LLColors(
    canvas: Color(0xFFF3F5F8),
    panel: Colors.white,
    ink: Color(0xFF14202E),
    muted: Color(0xFF5D6B7C),
    line: Color(0xFFDFE4EB),
    amberSoft: Color(0xFFFDF1DC),
    greenSoft: Color(0xFFE3F6EC),
    redSoft: Color(0xFFFDE8E8),
    blueSoft: Color(0xFFE5EEFB),
    amberInk: Color(0xFF9A5F00),
    greenInk: Color(0xFF13804D),
    redInk: Color(0xFFB42318),
    blueInk: Color(0xFF1F5BB0),
    shell: LL.navy,
  );

  static const dark = LLColors(
    canvas: Color(0xFF0C1826),
    panel: Color(0xFF13233A),
    ink: Color(0xFFE6EDF5),
    muted: Color(0xFF8FA1B5),
    line: Color(0xFF22385A),
    amberSoft: Color(0xFF3A2C14),
    greenSoft: Color(0xFF12342A),
    redSoft: Color(0xFF3B1A1D),
    blueSoft: Color(0xFF15294A),
    amberInk: Color(0xFFF5C06F),
    greenInk: Color(0xFF5FD69C),
    redInk: Color(0xFFF58B8E),
    blueInk: Color(0xFF8FB6EF),
    shell: Color(0xFF081320),
  );

  @override
  LLColors copyWith() => this;

  @override
  LLColors lerp(ThemeExtension<LLColors>? other, double t) =>
      t < .5 ? this : (other as LLColors? ?? this);
}

extension LLContext on BuildContext {
  LLColors get c => Theme.of(this).extension<LLColors>()!;
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? LLColors.dark : LLColors.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: LL.body,
    colorScheme: ColorScheme.fromSeed(
      seedColor: LL.navy3,
      brightness: b,
      primary: b == Brightness.dark ? LL.amber : LL.navy,
      surface: c.panel,
    ),
    scaffoldBackgroundColor: c.canvas,
    extensions: [c],
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(LL.rSm),
    borderSide: BorderSide(color: c.line),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    dividerColor: c.line,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: LL.navy3, width: 1.5)),
      hintStyle: TextStyle(color: c.muted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? LL.green : const Color(0xFFC3CCD7)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: LL.navy,
      behavior: SnackBarBehavior.floating,
      width: 460,
    ),
  );
}
