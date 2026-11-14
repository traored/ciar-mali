import 'package:flutter/material.dart';

class AppCouleurs {
  static const bleuNuit = Color(0xFF0E1B35);
  static const bleu = Color(0xFF1E3A8A);
  static const bleuClair = Color(0xFF3B5BDB);
  static const teal = Color(0xFF0D9488);
  static const ambre = Color(0xFFD97706);
  static const rouge = Color(0xFFDC2626);
  static const vert = Color(0xFF16A34A);
  static const fond = Color(0xFFF4F6FB);
  static const carte = Colors.white;
  static const bordure = Color(0xFFE2E8F0);
  static const texte = Color(0xFF0F172A);
  static const texteDoux = Color(0xFF64748B);
  static const violet = Color(0xFF7C3AED);
}

class AppTheme {
  static ThemeData get clair {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppCouleurs.bleu,
        primary: AppCouleurs.bleu,
        secondary: AppCouleurs.teal,
        surface: Colors.white,
        error: AppCouleurs.rouge,
      ),
      scaffoldBackgroundColor: AppCouleurs.fond,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppCouleurs.texte,
        displayColor: AppCouleurs.texte,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppCouleurs.bordure),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppCouleurs.bordure, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppCouleurs.bordure),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppCouleurs.bordure),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppCouleurs.bleu, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppCouleurs.texteDoux),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppCouleurs.bleu,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppCouleurs.bleu,
          side: const BorderSide(color: AppCouleurs.bordure),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppCouleurs.bleu,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(Color(0xFFF8FAFC)),
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppCouleurs.texteDoux,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
        dataTextStyle: TextStyle(fontSize: 13, color: AppCouleurs.texte),
        dividerThickness: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: AppCouleurs.bordure),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: AppCouleurs.bleuNuit,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    );
  }
}
