import 'dart:convert';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/auth/login_page.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:controle_pessoal/features/auth/validacoes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _app(MockClientHandler h) => ProviderScope(
      overrides: [
        clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: MockClient(h))),
        armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
      ],
      child: const MaterialApp(home: LoginPage()),
    );

/// Tela alta o bastante para a pagina de login inteira caber sem rolar.
void _telaAlta(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('validacoes', () {
    test('e-mail', () {
      expect(validarEmail(''), isNotNull);
      expect(validarEmail('bia'), isNotNull);
      expect(validarEmail('bia@x'), isNotNull);
      expect(validarEmail(' bia@exemplo.com '), isNull);
    });
    test('senha nova: 8 a 128 caracteres', () {
      expect(validarSenhaNova(''), isNotNull);
      expect(validarSenhaNova('1234567'), isNotNull);
      expect(validarSenhaNova('12345678'), isNull);
      expect(validarSenhaNova('a' * 129), isNotNull);
    });
    test('nome', () {
      expect(validarNome('  '), isNotNull);
      expect(validarNome('Bia'), isNull);
    });
  });

  testWidgets('campos vazios mostram os erros e nao chamam a API', (tester) async {
    _telaAlta(tester);
    var chamadas = 0;
    await tester.pumpWidget(_app((r) async {
      chamadas++;
      return http.Response('{}', 200);
    }));
    await tester.tap(find.byKey(const Key('botao_entrar')));
    await tester.pump();
    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(find.text('Informe sua senha.'), findsOneWidget);
    expect(chamadas, 0);
  });

  testWidgets('senha errada mostra a mensagem da API', (tester) async {
    _telaAlta(tester);
    await tester.pumpWidget(_app((r) async => http.Response.bytes(
        utf8.encode(jsonEncode({'erro': 'credenciais_invalidas'})), 401,
        headers: {'content-type': 'application/json'})));
    await tester.enterText(find.byKey(const Key('campo_email')), 'bia@exemplo.com');
    await tester.enterText(find.byKey(const Key('campo_senha')), 'errada123');
    await tester.tap(find.byKey(const Key('botao_entrar')));
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
  });

  testWidgets('o botao Criar conta abre o cadastro', (tester) async {
    _telaAlta(tester);
    await tester.pumpWidget(_app((r) async => http.Response('{}', 200)));
    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('campo_nome')), findsOneWidget);
    expect(find.byKey(const Key('botao_criar')), findsOneWidget);
  });
}
