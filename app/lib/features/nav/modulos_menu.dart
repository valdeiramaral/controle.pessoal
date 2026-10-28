import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';

/// Modulos que ja vem com tela propria no app (o resto abre a tela generica do modulo cadastrado).
/// Sao cadastrados como qualquer outro modulo: so aparecem no menu de quem tem acesso.
const modulosComTela = ['painel', 'financas', 'saude', 'agenda'];

/// Icone e cor de cada modulo com tela propria.
(IconData, MaterialColor)? aparenciaDoModuloNativo(String codigo) => switch (codigo) {
      'painel' => (Icons.today_outlined, Colors.amber),
      'financas' => (Icons.account_balance_wallet_outlined, Colors.lightGreen),
      'saude' => (Icons.favorite_border, Colors.pink),
      'agenda' => (Icons.event_outlined, Colors.lightBlue),
      _ => null,
    };

/// Sem servidor (uso local) ou se a lista nao puder ser carregada, o app abre com estes modulos.
const modulosNativosPadrao = <ModuloMenu>[
  ModuloMenu(codigo: 'painel', nome: 'Agenda do Dia'),
  ModuloMenu(codigo: 'financas', nome: 'Finanças'),
  ModuloMenu(codigo: 'saude', nome: 'Saúde'),
  ModuloMenu(codigo: 'agenda', nome: 'Agenda'),
];

/// Ordem do menu: a Agenda do Dia primeiro (e a tela inicial); depois os modulos com tela propria
/// na ordem de sempre, e os demais na ordem do servidor.
List<ModuloMenu> ordenarModulos(List<ModuloMenu> lista) {
  final resto = [
    for (final c in modulosComTela) ...lista.where((m) => m.codigo == c),
    ...lista.where((m) => !modulosComTela.contains(m.codigo)),
  ];
  return [
    ...resto.where((m) => m.codigo == 'painel'),
    ...resto.where((m) => m.codigo != 'painel'),
  ];
}

/// Modulos do menu do usuario: os que o administrador cadastrou e liberou para ele
/// (por plano ou por usuario; na liberacao por usuario, "fixo no menu" desmarcado oculta o modulo). O SuperUsuario ve todos os ativos.
/// Use `ref.invalidate(modulosMenuProvider)` depois de mudar o cadastro.
final modulosMenuProvider = FutureProvider<List<ModuloMenu>>((ref) async {
  final s = ref.watch(sessaoProvider);
  final token = s.token;
  if (s.fase != FaseSessao.logado || token == null) return modulosNativosPadrao;
  try {
    return ordenarModulos(await ref.watch(clienteApiProvider).meusModulos(token));
  } on ErroApi {
    return modulosNativosPadrao; // servidor indisponivel: nao deixa o app sem menu
  }
});

/// Lista pronta para o menu: carregando = vazia; erro inesperado = modulos padrao.
List<ModuloMenu> modulosDoMenu(AsyncValue<List<ModuloMenu>> a) =>
    a.when(data: (l) => l, loading: () => const [], error: (_, __) => modulosNativosPadrao);
