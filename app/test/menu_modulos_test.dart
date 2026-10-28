import 'dart:convert';

import 'package:controle_pessoal/app.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:controle_pessoal/features/nav/menu_lateral.dart';
import 'package:controle_pessoal/features/nav/modulos_menu.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'util_testes.dart';

class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

Future<void> _abrir(WidgetTester tester, List<Map<String, String>> liberados) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const usuario = UsuarioApi(id: 'u', nome: 'Maria');
  final banco = Banco.paraTeste(NativeDatabase.memory());
  addTearDown(banco.close);
  final cliente = MockClient((r) async {
    final corpo = r.url.path == '/meus-modulos'
        ? {'itens': [for (final m in liberados) {'codigo': m['codigo'], 'nome': m['nome'], 'descricao': null, 'icone': 'extension'}]}
        : {'total': 0, 'itens': []};
    return http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200, headers: {'content-type': 'application/json'});
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [
      bancoProvider.overrideWithValue(banco),
      clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: cliente)),
      armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
        menuRecolhidoProvider.overrideWith((_) => false), // o app inicia recolhido; aqui os rotulos precisam aparecer
      sessaoProvider.overrideWith(() => _SessaoFalsa(EstadoSessao(
            FaseSessao.logado,
            token: 't',
            usuario: usuario,
            perfil: const PerfilApi(usuario: usuario, permissoes: []),
          ))),
    ],
    child: MaterialApp(theme: temaApp(), home: const Casca()),
  ));
  await tester.pumpAndSettle();
}

Finder _noMenu(String t) => find.descendant(of: find.byType(MenuLateral), matching: find.text(t));

void main() {
  test('ordenarModulos poe os com tela primeiro, na ordem de sempre, e mantem os demais', () {
    final lista = ordenarModulos(const [
      ModuloMenu(codigo: 'academia', nome: 'Academia'),
      ModuloMenu(codigo: 'agenda', nome: 'Agenda'),
      ModuloMenu(codigo: 'painel', nome: 'Agenda do Dia'),
      ModuloMenu(codigo: 'viagens', nome: 'Viagens'),
    ]);
    expect(lista.map((m) => m.codigo), ['painel', 'agenda', 'academia', 'viagens']);
  });

  testWidgets('o menu mostra so os modulos liberados; a Agenda do Dia e a tela inicial', (tester) async {
    await _abrir(tester, [
      {'codigo': 'agenda', 'nome': 'Agenda'},
      {'codigo': 'painel', 'nome': 'Agenda do Dia'},
      {'codigo': 'saude', 'nome': 'Saúde'},
    ]);
    expect(_noMenu('Agenda do Dia'), findsOneWidget);
    expect(_noMenu('Saúde'), findsOneWidget);
    expect(_noMenu('Agenda'), findsOneWidget);
    expect(_noMenu('Finanças'), findsNothing); // nao liberado para este usuario
    expect(find.textContaining('Agenda do Dia ·'), findsOneWidget); // tela principal apos o login
    await encerrar(tester);
  });

  testWidgets('a tela mostra o nome que o modulo tem no cadastro (ex.: o modulo agenda renomeado para Tarefas)', (tester) async {
    await _abrir(tester, [
      {'codigo': 'agenda', 'nome': 'Tarefas'},
    ]);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Tarefas')), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Agenda')), findsNothing);
    await encerrar(tester);
  });

  testWidgets('sem nenhum modulo liberado mostra o aviso', (tester) async {
    await _abrir(tester, const []);
    expect(find.byKey(const Key('sem_modulos')), findsOneWidget);
    expect(_noMenu('Finanças'), findsNothing);
    await encerrar(tester);
  });
}
