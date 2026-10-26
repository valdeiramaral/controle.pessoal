import 'package:flutter/material.dart';

import '../features/auth/widgets_auth.dart' show azulMarca;

/// Tema do app: texto claro e cartoes de vidro sobre o fundo azul (FundoAzul).
ThemeData temaApp() {
  final esquema = ColorScheme.fromSeed(seedColor: azulMarca, brightness: Brightness.dark).copyWith(
    primary: const Color(0xFF8DB8FF),
    onPrimary: const Color(0xFF06214F),
    surface: const Color(0xFF14234F),
    onSurface: Colors.white,
    onSurfaceVariant: const Color(0xFFC5D0EA),
    // Cartoes (Card) usam esta cor: branco translucido sobre o azul.
    surfaceContainerLow: Colors.white.withValues(alpha: 0.08),
    outlineVariant: Colors.white.withValues(alpha: 0.18),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF14234F),
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF2F6BFF),
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    dividerColor: Colors.white24,
    iconTheme: const IconThemeData(size: 22),
  );
}
