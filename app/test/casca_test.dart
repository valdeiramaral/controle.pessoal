import 'dart:convert';

import 'package:controle_pessoal/app.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
  });
}
