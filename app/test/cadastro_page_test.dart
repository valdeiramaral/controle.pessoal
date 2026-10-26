import 'dart:convert';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/auth/cadastro_page.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object corpo) => http.Response.bytes(
    utf8.encode(jsonEncode(corpo)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

void _telaAlta(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(MockClientHandler h) => ProviderScope(
      overrides: [
        clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: MockClient(h))),
        armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
      ],
      child: const MaterialApp(home: CadastroPage()),
    );

Future<void> _preencher(WidgetTester tester, {String cpf = '52998224725', String telefone = '11987654321'}) async {
  await tester.enterText(find.byKey(const Key('campo_nome')), 'Bia Souza');
  await tester.enterText(find.byKey(const Key('campo_email')), 'bia@exemplo.com');
  await tester.enterText(find.byKey(const Key('campo_cpf')), cpf);
  await tester.enterText(find.byKey(const Key('campo_telefone')), telefone);
  await tester.enterText(find.byKey(const Key('campo_senha')), 'segredo123');
  await tester.enterText(find.byKey(const Key('campo_confirma')), 'segredo123');
}

void main() {
  testWidgets('mostra CPF e telefone e aplica as mascaras ao digitar', (tester) async {
    _telaAlta(tester);
    await tester.pumpWidget(_app((r) async => _json(200, {})));
    await _preencher(tester);
    expect(find.text('529.982.247-25'), findsOneWidget);
    expect(find.text('(11) 98765-4321'), findsOneWidget);
  });

  testWidgets('CPF invalido e telefone vazio sao recusados sem chamar a API', (tester) async {
    _telaAlta(tester);
    var chamadas = 0;
    await tester.pumpWidget(_app((r) async {
      chamadas++;
      return _json(200, {});
    }));
    await _preencher(tester, cpf: '11111111111', telefone: '');
    await tester.tap(find.byKey(const Key('botao_criar')));
    await tester.pump();
    expect(find.text('CPF inválido.'), findsOneWidget);
    expect(find.text('Informe o telefone.'), findsOneWidget);
    expect(chamadas, 0);
  });

  testWidgets('envia CPF e telefone so com digitos, junto com o endereco preenchido', (tester) async {
    _telaAlta(tester);
    Map<String, dynamic>? corpo;
    await tester.pumpWidget(_app((r) async {
      if (r.url.path == '/cadastro') {
        corpo = jsonDecode(r.body) as Map<String, dynamic>;
        return _json(201, {'id': 'u1'});
      }
      return _json(200, {
        'token': 'tok',
        'expira_em_segundos': 3600,
        'usuario': {'id': 'u1', 'nome': 'Bia Souza', 'email': 'bia@exemplo.com'},
      });
    }));
    await _preencher(tester);
    // abre a secao opcional e preenche cidade/UF e nascimento
    await tester.tap(find.byKey(const Key('secao_endereco')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_cidade')), 'Sao Paulo');
    await tester.enterText(find.byKey(const Key('campo_uf')), 'sp');
    await tester.enterText(find.byKey(const Key('campo_nascimento')), '17051990');
    await tester.tap(find.byKey(const Key('botao_criar')));
    await tester.pumpAndSettle();
    expect(corpo, isNotNull);
    expect(corpo!['cpf'], '52998224725');
    expect(corpo!['telefone'], '11987654321');
    expect(corpo!['nascimento'], '1990-05-17');
    expect((corpo!['endereco'] as Map)['cidade'], 'Sao Paulo');
    expect((corpo!['endereco'] as Map)['uf'], 'SP');
    expect((corpo!['endereco'] as Map).containsKey('cep'), isFalse);
  });

  testWidgets('CPF repetido mostra a mensagem do servidor', (tester) async {
    _telaAlta(tester);
    await tester.pumpWidget(_app((r) async => _json(409, {'erro': 'cpf_ja_cadastrado'})));
    await _preencher(tester);
    await tester.tap(find.byKey(const Key('botao_criar')));
    await tester.pumpAndSettle();
    expect(find.text('Já existe uma conta com este CPF.'), findsOneWidget);
  });
}
