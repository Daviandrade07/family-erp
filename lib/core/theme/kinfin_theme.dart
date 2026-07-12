import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidade **KinFin** — escuro-premium. Nasce como tema SEPARADO do Casa
/// Viva (não altera `AppColors`/`AppTheme`), para conviver com as telas antigas
/// durante a migração faseada. O acento é função do MODO:
/// Solo = roxo/índigo, Compartilhado = verde; fundo near-black.
class KinFinColors {
  // Superfícies dark-premium
  static const bg = Color(0xFF0B0C12); // near-black (fundo/opaco)
  static const card = Color(0xFF161B26); // superfície dos cards (mais legível)
  static const surface = Color(0xFF14161F); // chips e afins
  static const surfaceHigh = Color(0xFF1C1F2B); // nav e sheets
  static const line = Color(0x1FFFFFFF); // branco ~12% (hairline)
  static const textPrimary = Color(0xFFF4F5F8);
  static const textMuted = Color(0xFF9AA0B0);

  // Acentos por modo
  static const solo = Color(0xFF7B61FF); // Solo — roxo/índigo
  static const soloDeep = Color(0xFF5B44D6);
  static const shared = Color(0xFF34D399); // Compartilhado — verde
  static const sharedDeep = Color(0xFF1FA97A);

  // Semânticos (papéis herdados da Fase 0, valores novos)
  static const positive = Color(0xFF34D399);
  static const attention = Color(0xFFF5B84B);
  static const danger = Color(0xFFF16A6A);
  static const info = Color(0xFF5B8DEF);

  /// Acento primário conforme o modo (Solo=roxo, Compartilhado=verde).
  static Color accent(bool isSolo) => isSolo ? solo : shared;

  /// Brilho sutil do fundo, tingido pelo modo.
  static Color glow(bool isSolo) =>
      (isSolo ? solo : shared).withValues(alpha: 0.10);
}

class KinFinTheme {
  /// Tema KinFin para o modo (isSolo). O `scaffoldBackgroundColor` é
  /// **transparente**: o fundo OPACO (que cobre a aurora do Casa Viva) é
  /// pintado pelo `KinFinScope`. É essa opacidade que garante a convivência
  /// das duas caras sem vazamento visual.
  static ThemeData build({required bool isSolo}) {
    final accent = KinFinColors.accent(isSolo);
    // Texto sobre o acento: escuro no verde (claro), branco no roxo (escuro).
    final onAccent = accent.computeLuminance() > 0.45
        ? const Color(0xFF07100C)
        : Colors.white;

    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: onAccent,
      secondary: KinFinColors.info,
      onSecondary: Colors.white,
      error: KinFinColors.danger,
      onError: Colors.white,
      surface: KinFinColors.surfaceHigh,
      onSurface: KinFinColors.textPrimary,
      surfaceContainerHighest: KinFinColors.surface,
      outline: KinFinColors.line,
    );

    final baseText = GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
        .apply(
            bodyColor: KinFinColors.textPrimary,
            displayColor: KinFinColors.textPrimary);
    const tabular = [FontFeature.tabularFigures()];
    final textTheme = baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
          fontFeatures: tabular, letterSpacing: -1.0, fontWeight: FontWeight.w800),
      displayMedium: baseText.displayMedium?.copyWith(
          fontFeatures: tabular, letterSpacing: -1.0, fontWeight: FontWeight.w800),
      displaySmall: baseText.displaySmall?.copyWith(
          fontFeatures: tabular, letterSpacing: -0.8, fontWeight: FontWeight.w800),
      headlineMedium: baseText.headlineMedium?.copyWith(
          fontFeatures: tabular, letterSpacing: -0.6, fontWeight: FontWeight.w800),
      headlineSmall: baseText.headlineSmall?.copyWith(
          fontFeatures: tabular, letterSpacing: -0.6, fontWeight: FontWeight.w800),
      titleLarge: baseText.titleLarge
          ?.copyWith(fontFeatures: tabular, letterSpacing: -0.4),
      titleMedium: baseText.titleMedium?.copyWith(fontFeatures: tabular),
      titleSmall: baseText.titleSmall?.copyWith(fontFeatures: tabular),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800, fontSize: 23, letterSpacing: -0.6),
        iconTheme: const IconThemeData(color: KinFinColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: KinFinColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: KinFinColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          minimumSize: const Size.fromHeight(52),
          textStyle:
              textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: KinFinColors.textPrimary,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: KinFinColors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KinFinColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: KinFinColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: KinFinColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: KinFinColors.textMuted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: KinFinColors.surfaceHigh,
        indicatorColor: accent.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : KinFinColors.textMuted,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: KinFinColors.surface,
        selectedColor: accent.withValues(alpha: 0.14),
        side: const BorderSide(color: KinFinColors.line),
        labelStyle: textTheme.labelMedium!,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(color: KinFinColors.line, thickness: 1),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: KinFinColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: KinFinColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
