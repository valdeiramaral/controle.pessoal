import 'package:flutter/material.dart';

/// Preferencias de aparencia de um usuario: modo (claro/escuro/sistema), tamanho da letra e cor.
/// Ficam guardadas na conta (PUT /me/preferencias), entao acompanham o usuario em qualquer aparelho.

enum ModoAparencia {
  claro('Claro', Icons.light_mode_outlined),
  escuro('Escuro', Icons.dark_mode_outlined),
  sistema('Sistema', Icons.settings_suggest_outlined);

  const ModoAparencia(this.nome, this.icone);
  final String nome;
  final IconData icone;

  ThemeMode get themeMode => switch (this) {
        ModoAparencia.claro => ThemeMode.light,
        ModoAparencia.escuro => ThemeMode.dark,
        ModoAparencia.sistema => ThemeMode.system,
      };
}

/// Opcoes de tamanho da letra: nome e escala aplicada ao texto de todo o app.
const escalasLetra = <(String, double)>[
  ('Pequena', 0.9),
  ('Normal', 1.0),
  ('Grande', 1.15),
  ('Muito grande', 1.3),
];

/// Cor do sistema: define o degrade do fundo, o menu e o destaque dos botoes.
class CorSistema {
  const CorSistema({
    required this.codigo,
    required this.nome,
    required this.semente,
    required this.fundo,
    required this.menu,
    required this.destaque,
    required this.fundoClaro,
  });

  /// O que a API guarda.
  final String codigo;
  final String nome;

  /// Cor "de marca" (botoes e destaques no tema claro).
  final Color semente;

  /// Degrade do fundo no tema escuro.
  final List<Color> fundo;

  /// Degrade do menu lateral (sempre escuro).
  final List<Color> menu;

  /// Cor de destaque no tema escuro.
  final Color destaque;

  /// Degrade do fundo no tema claro.
  final List<Color> fundoClaro;
}

const coresSistema = <CorSistema>[
  CorSistema(
    codigo: 'azul',
    nome: 'Azul',
    semente: Color(0xFF0052CC),
    fundo: [Color(0xFF1B54D9), Color(0xFF2B48B8), Color(0xFF3B3AA4)],
    menu: [Color(0xFF0F2A63), Color(0xFF33307F)],
    destaque: Color(0xFF8DB8FF),
    fundoClaro: [Color(0xFFE6EEFF), Color(0xFFF6F8FF)],
  ),
  CorSistema(
    codigo: 'verde',
    nome: 'Verde',
    semente: Color(0xFF0E8A5F),
    fundo: [Color(0xFF0E8A5F), Color(0xFF0F7A6E), Color(0xFF1A6A7A)],
    menu: [Color(0xFF08402F), Color(0xFF0F4A5A)],
    destaque: Color(0xFF7DE0B2),
    fundoClaro: [Color(0xFFE2F6EC), Color(0xFFF4FBF8)],
  ),
  CorSistema(
    codigo: 'roxo',
    nome: 'Roxo',
    semente: Color(0xFF6A3BE0),
    fundo: [Color(0xFF6A3BE0), Color(0xFF5A36C0), Color(0xFF4A2FA0)],
    menu: [Color(0xFF2C1A66), Color(0xFF45237F)],
    destaque: Color(0xFFC3A8FF),
    fundoClaro: [Color(0xFFEEE7FF), Color(0xFFF8F5FF)],
  ),
  CorSistema(
    codigo: 'laranja',
    nome: 'Laranja',
    semente: Color(0xFFE8671A),
    fundo: [Color(0xFFE8671A), Color(0xFFD4541F), Color(0xFFB5452C)],
    menu: [Color(0xFF5A2A0B), Color(0xFF7A2E1C)],
    destaque: Color(0xFFFFB27A),
    fundoClaro: [Color(0xFFFFEEDF), Color(0xFFFFF8F2)],
  ),
  CorSistema(
    codigo: 'rosa',
    nome: 'Rosa',
    semente: Color(0xFFD6336C),
    fundo: [Color(0xFFD6336C), Color(0xFFB52F6E), Color(0xFF8F2C7A)],
    menu: [Color(0xFF5A1236), Color(0xFF6E1F5C)],
    destaque: Color(0xFFFFA8C8),
    fundoClaro: [Color(0xFFFFE7F0), Color(0xFFFFF6F9)],
  ),
  CorSistema(
    codigo: 'turquesa',
    nome: 'Turquesa',
    semente: Color(0xFF0A8E9E),
    fundo: [Color(0xFF0AA5B7), Color(0xFF0E86B0), Color(0xFF1B66A8)],
    menu: [Color(0xFF06424D), Color(0xFF0F3F6B)],
    destaque: Color(0xFF7FE3EE),
    fundoClaro: [Color(0xFFDFF6F9), Color(0xFFF3FCFD)],
  ),
];

CorSistema corSistemaPorCodigo(String? codigo) =>
    coresSistema.firstWhere((c) => c.codigo == codigo, orElse: () => coresSistema.first);

class Aparencia {
  const Aparencia({this.modo = ModoAparencia.escuro, this.escala = 1.0, this.cor = 'azul'});

  static const padrao = Aparencia();

  final ModoAparencia modo;
  final double escala;
  final String cor;

  CorSistema get corSistema => corSistemaPorCodigo(cor);

  Aparencia copiarCom({ModoAparencia? modo, double? escala, String? cor}) =>
      Aparencia(modo: modo ?? this.modo, escala: escala ?? this.escala, cor: cor ?? this.cor);

  Map<String, dynamic> paraJson() => {'modo': modo.name, 'escala': escala, 'cor': cor};

  /// Aceita o {} de quem nunca escolheu (volta ao padrao) e ignora valores desconhecidos.
  factory Aparencia.deJson(Object? j) {
    if (j is! Map) return padrao;
    final modo = ModoAparencia.values.where((m) => m.name == j['modo']).firstOrNull ?? padrao.modo;
    final e = (j['escala'] as num?)?.toDouble();
    final cor = coresSistema.any((c) => c.codigo == j['cor']) ? j['cor'] as String : padrao.cor;
    return Aparencia(modo: modo, escala: (e == null || e < 0.8 || e > 1.6) ? 1.0 : e, cor: cor);
  }

  @override
  bool operator ==(Object o) => o is Aparencia && o.modo == modo && o.escala == escala && o.cor == cor;

  @override
  int get hashCode => Object.hash(modo, escala, cor);
}

/// Cor de icone legivel no tema atual: tom claro sobre fundo escuro, tom forte sobre fundo claro.
Color corIcone(BuildContext context, MaterialColor cor) =>
    Theme.of(context).brightness == Brightness.dark ? cor.shade300 : cor.shade700;
