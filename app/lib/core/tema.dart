import 'package:flutter/material.dart';

import 'aparencia.dart';

/// Tema do app. Escuro: texto claro e cartoes de vidro sobre o degrade colorido (FundoAzul).
/// Claro: texto escuro e cartoes brancos sobre um degrade suave. A cor vem da escolha do usuario.
ThemeData temaApp({Brightness brilho = Brightness.dark, CorSistema? cor}) {
  final c = cor ?? coresSistema.first;
  final escuro = brilho == Brightness.dark;
  final esquema = escuro
      ? ColorScheme.fromSeed(seedColor: c.semente, brightness: Brightness.dark).copyWith(
          primary: c.destaque,
          onPrimary: c.menu.first,
          surface: c.menu.first,
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFFD0D8EC),
          // Cartoes (Card) usam esta cor: branco translucido sobre o fundo colorido.
          surfaceContainerLow: Colors.white.withValues(alpha: 0.08),
          outlineVariant: Colors.white.withValues(alpha: 0.18),
        )
      : ColorScheme.fromSeed(seedColor: c.semente, brightness: Brightness.light).copyWith(
          primary: c.semente,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: const Color(0xFF1B2133),
          onSurfaceVariant: const Color(0xFF50586E),
          surfaceContainerLow: Colors.white.withValues(alpha: 0.92),
          outlineVariant: const Color(0xFFD5DBE8),
        );
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: esquema.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: esquema.surface,
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: escuro ? c.fundo.first : c.semente,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    dividerColor: esquema.outlineVariant,
    iconTheme: const IconThemeData(size: 22),
  );
}
