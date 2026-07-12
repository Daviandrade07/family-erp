import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Family ERP Design System.
///
/// Identidade "Viva Casa": calma, humana e precisa. A marca usa índigo para
/// confiança, coral para ação e laguna para informação; verde fica reservado
/// apenas para progresso financeiro real.
class AppColors {
  // ==== Tokens semânticos "Casa Viva" — UM papel por cor ====
  // Cada papel tem uma cor única. Os nomes legados abaixo são APELIDOS
  // documentados que apontam para o papel correto (evita renomear ~80 usos);
  // nunca duas semânticas diferentes na mesma cor por acidente.
  static const mint = Color(0xFF5CC8B3); // AÇÃO + POSITIVO
  static const mintDeep = Color(0xFF3E9C88);
  static const coral = Color(0xFFF19A78); // SECUNDÁRIO
  static const indigo = Color(0xFF8174E8); // SONHO / METAS
  static const amber = Color(0xFFE7B967); // ALERTA / ATENÇÃO
  static const lagoon = Color(0xFF46AFC3); // INFO / ASSISTENTE
  static const red = Color(0xFFE8796F); // URGÊNCIA / ERRO

  // Apelidos legados → papel correto (sem migração destrutiva de call sites).
  static const successSage = mint; // positivo
  static const successSageDark = mintDeep;
  static const neonGreen = mint; // positivo
  static const neonGreenDark = mintDeep;
  static const techBlue = lagoon; // info/assistente (era == mint: colisão desfeita)
  static const violet = indigo; // sonho (consolidado com o antigo brandIndigo)
  static const brandCoral = coral; // secundário
  static const brandLagoon = lagoon; // info/assistente

  // Dark surfaces (Casa Viva: ink + superfícies elevadas, borda hairline)
  static const darkBg = Color(0xFF10131A); // ink (fundo/aurora)
  static const darkSurface = Color(0xFF171C25); // nav e sheets
  static const darkCard = Color(0xFF1A1F29); // cards
  static const darkBorder = Color(0x17FFFFFF); // branco 9% (hairline)
  static const darkTextPrimary = Color(0xFFF5F7FB);
  static const darkTextSecondary = Color(0xFFAEB7C5);

  // Aurora do fundo (dois brilhos radiais sobre o ink)
  static const auroraTeal = Color(0xFF1E3040);
  static const auroraPlum = Color(0xFF2A203E);

  // Light surfaces
  static const lightBg = Color(0xFFF6F3EE);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE7E7EC);
  static const lightTextPrimary = Color(0xFF17171C);
  static const lightTextSecondary = Color(0xFF62626E);

  // ---- Paleta categórica fixa (Casa Viva) ----
  // Cada categoria tem SEMPRE a mesma cor — nada de confete por hashCode.
  // Reharmonizada para o tema dark+aurora: um pouco mais claras e saturadas
  // que a versão antiga (que apagava sobre o ink), mantendo a família Casa
  // Viva. Índigo fica fora (exclusivo do sonho); vermelho fora (urgência).
  static const catBlue = Color(0xFF6EA8E8);
  static const catTeal = Color(0xFF46C3AE);
  static const catGreen = Color(0xFF7FC98A);
  static const catOlive = Color(0xFFBCB36A);
  static const catAmber = Color(0xFFE3B45F);
  static const catBrown = Color(0xFFC79A78);
  static const catCoral = Color(0xFFEC9A82);
  static const catSlate = Color(0xFF94A7C0);
  static const catCyan = Color(0xFF5FC4D6);
  static const catSand = Color(0xFFD4C08A);
  static const catGray = Color(0xFF9AA6B4);

  static const Map<String, Color> _categoryColors = {
    // Despesas
    'Alimentação': catOlive,
    'Mercado': catAmber,
    'Moradia': catSlate,
    'Transporte': catTeal,
    'Saúde': catGreen,
    'Educação': catBlue,
    'Lazer': catCyan,
    'Vestuário': catCoral,
    'Assinaturas': catBrown,
    'Pets': catSand,
    'Outros': catGray,
    // Receitas
    'Salário': catGreen,
    'Freelance': catTeal,
    'Investimentos': catBlue,
    'Aluguel': catSlate,
    // Contas da casa
    'Água': catCyan,
    'Energia': catAmber,
    'Internet': catBlue,
    'Telefone': catBlue,
    'Combustível': catTeal,
    'Farmácia': catGreen,
    'Financiamentos': catSlate,
    'Cartão': catSlate,
    'Empréstimos': catBrown,
  };

  /// Cor fixa e previsível da categoria; desconhecidas ficam neutras.
  static Color categoryColor(String category) =>
      _categoryColors[category] ?? catGray;

  /// Tokens de cor escolhíveis para CATEGORIAS (customizadas usam um destes;
  /// os padrões são semeados com o mesmo conjunto). Chave = valor salvo em
  /// `categories.color_token`. Nada de hex solto — só token.
  static const Map<String, Color> categoryTokens = {
    'catBlue': catBlue,
    'catTeal': catTeal,
    'catGreen': catGreen,
    'catOlive': catOlive,
    'catAmber': catAmber,
    'catBrown': catBrown,
    'catCoral': catCoral,
    'catSlate': catSlate,
    'catCyan': catCyan,
    'catSand': catSand,
    'catGray': catGray,
  };

  /// Resolve um token de cor de categoria; desconhecido cai no neutro.
  static Color tokenColor(String? token) => categoryTokens[token] ?? catGray;
}

class AppTheme {
  /// [accent] é a cor primária escolhida pelo usuário (default: menta da
  /// identidade Casa Viva). Recolore só o elemento primário.
  static ThemeData dark({Color accent = AppColors.mint}) =>
      _build(Brightness.dark, accent);
  static ThemeData light({Color accent = AppColors.mint}) =>
      _build(Brightness.light, accent);

  static ThemeData _build(Brightness brightness, Color accent) {
    final isDark = brightness == Brightness.dark;

    // Texto sobre a cor primária: escuro em acentos claros (menta/âmbar),
    // branco em acentos escuros (índigo). Contraste sempre legível.
    final onAccent = accent.computeLuminance() > 0.45
        ? const Color(0xFF0C1714)
        : Colors.white;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: AppColors.brandCoral,
      onSecondary: const Color(0xFF3A1611),
      error: AppColors.red,
      onError: Colors.white,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      onSurface:
          isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      surfaceContainerHighest:
          isDark ? AppColors.darkCard : AppColors.lightCard,
      outline: isDark ? AppColors.darkBorder : AppColors.lightBorder,
    );

    final baseText = GoogleFonts.interTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    // Casa Viva usa UMA fonte (Inter) com tracking apertado nos títulos — nada
    // de serifada. Números tabulares para alinhar valores. Títulos "apertados"
    // (letter-spacing negativo) dão o ar contemporâneo do protótipo.
    const tabular = [FontFeature.tabularFigures()];
    final textTheme = baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
          fontFeatures: tabular, letterSpacing: -1.0, fontWeight: FontWeight.w800),
      displayMedium: baseText.displayMedium?.copyWith(
          fontFeatures: tabular, letterSpacing: -1.0, fontWeight: FontWeight.w800),
      displaySmall: baseText.displaySmall?.copyWith(
          fontFeatures: tabular, letterSpacing: -0.8, fontWeight: FontWeight.w800),
      headlineLarge: baseText.headlineLarge?.copyWith(
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
      brightness: brightness,
      colorScheme: scheme,
      // Transparente: o fundo (ink + aurora) é pintado por AuroraBackground
      // atrás de todas as telas (ver main.dart).
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
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outline),
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
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: scheme.outline),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: TextStyle(
          color: isDark
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        indicatorColor: accent.withValues(alpha: 0.14),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? accent
                : (isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.lightBg,
        selectedColor: accent.withValues(alpha: 0.12),
        side: BorderSide(color: scheme.outline),
        labelStyle: textTheme.labelMedium!,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppColors.darkCard : AppColors.lightTextPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
