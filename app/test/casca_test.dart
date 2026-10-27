import 'dart:convert';

import 'package:controle_pessoal/app.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:controle_pessoal/features/nav/menu_lateral.dart';
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

void main() {
  testWidgets('tela de cadastro abre ao lado do menu, sem cobri-lo; trocar de modulo volta', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const admin = UsuarioApi(id: 'a', nome: 'Admin');
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final cliente = MockClient((r) async => http.Response.bytes(
          utf8.encode(jsonEncode({'total': 0, 'pagina': 1, 'itens': []})), 200,
          headers: {'content-type': 'application/json'}));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: cliente)),
        armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
        sessaoProvider.overrideWith(() => _SessaoFalsa(EstadoSessao(
              FaseSessao.logado,
              token: 't',
              usuario: admin,
              perfil: PerfilApi(usuario: admin, permissoes: const ['acesso.usuario.ver']),
            ))),
      ],
      child: MaterialApp(theme: temaApp(), home: const Casca()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usuários e acessos'));
    await tester.pumpAndSettle();
    // A lista de usuarios abriu, e o menu continua na tela.
    expect(find.text('Usuários'), findsOneWidget);
    expect(find.text('Finanças'), findsOneWidget);
    expect(find.text('Usuários e acessos'), findsOneWidget);

    // Escolher um modulo no menu fecha a tela de cadastro.
    await tester.tap(find.text('Finanças'));
    await tester.pumpAndSettle();
    expect(find.text('Usuários'), findsNothing);
    await encerrar(tester);
  });

  testWidgets('modulo novo cadastrado aparece no menu na hora e abre a tela dele', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const admin = UsuarioApi(id: 'a', nome: 'Admin');
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final modulos = <Map<String, dynamic>>[];
    Map<String, dynamic>? postado;
    http.Response json(int status, Object corpo) => http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
        headers: {'content-type': 'application/json'});
    final cliente = MockClient((r) async {
      if (r.url.path == '/modulos' && r.method == 'POST') {
        postado = jsonDecode(r.body) as Map<String, dynamic>;
        final novo = {
          'codigo': 'academia', 'nome': postado!['nome'], 'descricao': null, 'ordem': 10, 'ativo': true,
          'liberado_para_todos': true, 'icone': postado!['icone'], 'sistema': false, 'planos': <String>[],
        };
        modulos.add(novo);
        return json(201, novo);
      }
      if (r.url.path == '/usuarios') {
        return json(200, {'total': 1, 'itens': [{'id': 'u1', 'nome': 'Maria', 'email': 'maria@x.com', 'ativo': true}]});
      }
      if (r.url.path == '/modulos') return json(200, {'itens': modulos});
      if (r.url.path == '/meus-modulos') {
        return json(200, {'itens': [for (final m in modulos) {'codigo': m['codigo'], 'nome': m['nome'], 'descricao': null, 'icone': m['icone']}]});
      }
      if (r.url.path == '/catalogo') return json(200, {'planos': [], 'modulos': [], 'perfis': []});
      return json(200, {});
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: cliente)),
        armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
        sessaoProvider.overrideWith(() => _SessaoFalsa(EstadoSessao(
              FaseSessao.logado,
              token: 't',
              usuario: admin,
              perfil: PerfilApi(usuario: admin, permissoes: const ['acesso.usuario.ver', 'administracao.modulo.gerenciar'], superusuario: true),
            ))),
      ],
      child: MaterialApp(theme: temaApp(), home: const Casca()),
    ));
    await tester.pumpAndSettle();
    final noMenu = find.descendant(of: find.byType(MenuLateral), matching: find.text('Academia'));
    expect(noMenu, findsNothing);

    await tester.tap(find.descendant(of: find.byType(MenuLateral), matching: find.text('Módulos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_novo_modulo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_nome_modulo')), 'Academia');
    await tester.tap(find.byKey(const Key('icone_fitness')));
    await tester.pump();
    await tocarRolando(tester, find.byKey(const Key('botao_add_usuario')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('usuario_op_u1')));
    await tester.pumpAndSettle();
    await tocarRolando(tester, find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();

    expect(postado!['nome'], 'Academia');
    expect(postado!['icone'], 'fitness');
    expect(postado!['no_pacote'], false);
    final lib = (postado!['liberacoes'] as List).single as Map<String, dynamic>;
    expect(lib['usuario_id'], 'u1');
    expect(lib['vitalicio'], true);
    expect(lib['ativa'], true);
    expect(noMenu, findsOneWidget); // apareceu no menu

    await tester.tap(noMenu);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modulo_em_breve')), findsOneWidget);
    await encerrar(tester);
  });
}
