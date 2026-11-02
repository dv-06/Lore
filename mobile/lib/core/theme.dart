import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LORE "Archival Precision" Design System
/// Derived from Stitch project: projects/5808540936924760303
class LoreColors {
  LoreColors._();

  // Surface tones (warm archival paper)
  static const Color surface = Color(0xFFFBF9F5);
  static const Color surfaceBright = Color(0xFFFBF9F5);
  static const Color surfaceDim = Color(0xFFDBDAD6);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF5F3F0);
  static const Color surfaceContainer = Color(0xFFEFEEEA);
  static const Color surfaceContainerHigh = Color(0xFFE9E8E4);
  static const Color surfaceContainerHighest = Color(0xFFE4E2DF);

  // Text / on-surface
  static const Color onSurface = Color(0xFF1B1C1A);
  static const Color onSurfaceVariant = Color(0xFF57423A);

  // Primary (burnt terracotta)
  static const Color primary = Color(0xFF974221);
  static const Color primaryContainer = Color(0xFFB75A36);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFFFFBFF);
  static const Color primaryFixed = Color(0xFFFFDBCF);
  static const Color primaryFixedDim = Color(0xFFFFB59B);

  // Brand accent (from design MD)
  static const Color brandAccent = Color(0xFFE66D3D);

  // Secondary (neutral graphite)
  static const Color secondary = Color(0xFF605E5A);
  static const Color secondaryContainer = Color(0xFFE3DFD9);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF64625E);

  // Tertiary / Privacy (deep teal/forest green)
  static const Color tertiary = Color(0xFF006769);
  static const Color tertiaryContainer = Color(0xFF008285);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color privacyGreen = Color(0xFF2E6B4E);

  // Outline
  static const Color outline = Color(0xFF89726B);
  static const Color outlineVariant = Color(0xFFDCC1B8);

  // Error
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFF93000A);

  // Inverse
  static const Color inverseSurface = Color(0xFF30312E);
  static const Color inverseOnSurface = Color(0xFFF2F1ED);
  static const Color inversePrimary = Color(0xFFFFB59B);

  // Structural lines from design MD
  static const Color structuralLine = Color(0xFFE6E4DC);
  static const Color canvasBase = Color(0xFFF6F5F0);
}

class LoreSpacing {
  LoreSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double gutterMobile = 12;
  static const double marginMobile = 16;
  static const double margin = 24;
}

class LoreRadius {
  LoreRadius._();

  static const double sm = 2;
  static const double base = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;

  static BorderRadius borderSm = BorderRadius.circular(sm);
  static BorderRadius borderBase = BorderRadius.circular(base);
  static BorderRadius borderMd = BorderRadius.circular(md);
  static BorderRadius borderLg = BorderRadius.circular(lg);
  static BorderRadius borderXl = BorderRadius.circular(xl);
  static BorderRadius borderFull = BorderRadius.circular(9999);
}

class LoreTypography {
  LoreTypography._();

  static TextStyle headlineLg = GoogleFonts.plusJakartaSans(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 38 / 30,
    letterSpacing: -0.025 * 30,
  );

  static TextStyle headlineLgMobile = GoogleFonts.plusJakartaSans(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 34 / 26,
    letterSpacing: -0.02 * 26,
  );

  static TextStyle headlineMd = GoogleFonts.plusJakartaSans(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 28 / 22,
    letterSpacing: -0.02 * 22,
  );

  static TextStyle headlineSm = GoogleFonts.plusJakartaSans(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 24 / 18,
    letterSpacing: -0.015 * 18,
  );

  static TextStyle bodyLg = GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    letterSpacing: -0.01 * 16,
  );

  static TextStyle bodyMd = GoogleFonts.plusJakartaSans(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: -0.005 * 14,
  );

  static TextStyle bodySm = GoogleFonts.plusJakartaSans(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
  );

  static TextStyle labelLg = GoogleFonts.jetBrainsMono(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 18 / 13,
    letterSpacing: -0.01 * 13,
  );

  static TextStyle labelMd = GoogleFonts.jetBrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 14 / 11,
    letterSpacing: 0.02 * 11,
  );

  static TextStyle labelSm = GoogleFonts.jetBrainsMono(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 12 / 10,
    letterSpacing: 0.04 * 10,
  );
}

class LoreTheme {
  LoreTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        surface: LoreColors.surface,
        onSurface: LoreColors.onSurface,
        onSurfaceVariant: LoreColors.onSurfaceVariant,
        primary: LoreColors.primary,
        primaryContainer: LoreColors.primaryContainer,
        onPrimary: LoreColors.onPrimary,
        onPrimaryContainer: LoreColors.onPrimaryContainer,
        secondary: LoreColors.secondary,
        secondaryContainer: LoreColors.secondaryContainer,
        onSecondary: LoreColors.onSecondary,
        onSecondaryContainer: LoreColors.onSecondaryContainer,
        tertiary: LoreColors.tertiary,
        tertiaryContainer: LoreColors.tertiaryContainer,
        onTertiary: LoreColors.onTertiary,
        error: LoreColors.error,
        errorContainer: LoreColors.errorContainer,
        onError: LoreColors.onError,
        onErrorContainer: LoreColors.onErrorContainer,
        inverseSurface: LoreColors.inverseSurface,
        onInverseSurface: LoreColors.inverseOnSurface,
        inversePrimary: LoreColors.inversePrimary,
        outline: LoreColors.outline,
        outlineVariant: LoreColors.outlineVariant,
        surfaceContainerLowest: LoreColors.surfaceContainerLowest,
        surfaceContainerLow: LoreColors.surfaceContainerLow,
        surfaceContainer: LoreColors.surfaceContainer,
        surfaceContainerHigh: LoreColors.surfaceContainerHigh,
        surfaceContainerHighest: LoreColors.surfaceContainerHighest,
      ),
      scaffoldBackgroundColor: LoreColors.surface,
      textTheme: TextTheme(
        headlineLarge: LoreTypography.headlineLg.copyWith(
          color: LoreColors.onSurface,
        ),
        headlineMedium: LoreTypography.headlineMd.copyWith(
          color: LoreColors.onSurface,
        ),
        headlineSmall: LoreTypography.headlineSm.copyWith(
          color: LoreColors.onSurface,
        ),
        bodyLarge: LoreTypography.bodyLg.copyWith(color: LoreColors.onSurface),
        bodyMedium: LoreTypography.bodyMd.copyWith(color: LoreColors.onSurface),
        bodySmall: LoreTypography.bodySm.copyWith(color: LoreColors.onSurface),
        labelLarge: LoreTypography.labelLg.copyWith(
          color: LoreColors.onSurface,
        ),
        labelMedium: LoreTypography.labelMd.copyWith(
          color: LoreColors.onSurface,
        ),
        labelSmall: LoreTypography.labelSm.copyWith(
          color: LoreColors.onSurface,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: LoreColors.surface.withValues(alpha: 0.85),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: LoreTypography.headlineSm.copyWith(
          color: LoreColors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: LoreColors.onSurface, size: 20),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: LoreColors.surface.withValues(alpha: 0.9),
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return LoreTypography.labelSm.copyWith(
              color: LoreColors.primary,
              fontWeight: FontWeight.w600,
            );
          }
          return LoreTypography.labelSm.copyWith(color: LoreColors.secondary);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: LoreColors.primary, size: 22);
          }
          return const IconThemeData(color: LoreColors.secondary, size: 22);
        }),
      ),
      cardTheme: CardThemeData(
        color: LoreColors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: LoreRadius.borderLg,
          side: BorderSide(
            color: LoreColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LoreColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: LoreRadius.borderMd,
          borderSide: BorderSide(color: LoreColors.structuralLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: LoreRadius.borderMd,
          borderSide: BorderSide(color: LoreColors.structuralLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: LoreRadius.borderMd,
          borderSide: const BorderSide(color: LoreColors.onSurface),
        ),
        hintStyle: LoreTypography.bodyMd.copyWith(color: LoreColors.secondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LoreColors.brandAccent,
          foregroundColor: LoreColors.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: LoreRadius.borderMd),
          textStyle: LoreTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LoreColors.onSurface,
          side: const BorderSide(color: LoreColors.structuralLine),
          shape: RoundedRectangleBorder(borderRadius: LoreRadius.borderMd),
          minimumSize: const Size(0, 44),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: LoreColors.surfaceContainerHighest,
        thickness: 1,
        space: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: LoreColors.surfaceContainer,
        side: BorderSide(color: LoreColors.structuralLine),
        shape: RoundedRectangleBorder(borderRadius: LoreRadius.borderSm),
        labelStyle: LoreTypography.labelMd,
      ),
    );
  }
}
