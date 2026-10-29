import 'dart:convert';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/auth/alterar_senha_page.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object corpo) => http.Response.bytes(
    utf8.encode(jsonEncode(corpo)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

const _usuario = {'id': 'u1', 'nome': 'Bia', 'email': 'a@b.com'};

/// Sessao ja logada; [aoTrocar] responde ao PATCH /me/senha e recebe o corpo enviado.
Future<(ProviderContainer, ArmazenamentoMemoria)> _logar(
    http.Response Function(Map<String, dynamic> corpo) aoTrocar,
    {List<Map<String, dynamic>>? recebidos}) async {
  final guarda = ArmazenamentoMemoria();
  final c = ProviderContainer(overrides: [
    clienteApiProvider.overrideWithValue(ClienteApi(
        baseUrl: 'http://api.teste',
        cliente: MockClient((r) async {
          if (r.url.path == '/login') {
            return _json(200, {'token': 'tok', 'expira_em_segundos': 3600, 'usuario': _usuario});
          }
          if (r.url.path == '/me/senha' && r.method == 'PATCH') {
            expect(r.headers['authorization'], 'Bearer tok');
            final corpo = jsonDecode(r.body) as Map<String, dynamic>;
            recebidos?.add(corpo);
            return aoTrocar(corpo);
          }
          return _json(404, {});
        }))),
    armazenamentoSessaoProvider.overrideWithValue(guarda),
  ]);
  addTearDown(c.dispose);
  await c.read(sessaoProvider.notifier).entrar('a@b.com', 'antiga123');
  return (c, guarda);
}

/// Pagina empilhada sobre outra (ela faz Navigator.pop ao salvar).
Widget _app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('abrir'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const AlterarSenhaPage())),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

Future<void> _abrir(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(c));
  await tester.tap(find.byKey(const Key('abrir')));
  await tester.pumpAndSettle();
}

Future<void> _preencher(WidgetTester tester, {String atual = 'antiga123', String nova = 'nova12345', String? confirma}) async {
  await tester.enterText(find.byKey(const Key('campo_senha_atual')), atual);
  await tester.enterText(find.byKey(const Key('campo_senha_nova')), nova);
  await tester.enterText(find.byKey(const Key('campo_senha_confirma')), confirma ?? nova);
}

void main() {
  testWidgets('campos vazios ou fora da regra mostram erros e nao chamam a API', (tester) async {
    final recebidos = <Map<String, dynamic>>[];
    final (c, _) = await _logar((_) => _json(204, {}), recebidos: recebidos);
    await _abrir(tester, c);

    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pump();
    expect(find.text('Informe a senha atual.'), findsOneWidget);
    expect(find.text('Use pelo menos 8 caracteres.'), findsOneWidget);

    await _preencher(tester, nova: 'curta');
    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pump();
    expect(find.text('Use pelo menos 8 caracteres.'), findsOneWidget);

    await _preencher(tester, nova: 'antiga123');
    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pump();
    expect(find.text('A nova senha deve ser diferente da atual.'), findsOneWidget);

    await _preencher(tester, nova: 'nova12345', confirma: 'outra12345');
    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pump();
    expect(find.text('As senhas não são iguais.'), findsOneWidget);
    expect(recebidos, isEmpty);
  });

  testWidgets('senha atual errada mostra a mensagem e continua na tela', (tester) async {
    final (c, _) = await _logar((_) => _json(400, {'erro': 'senha_atual_incorreta'}));
    await _abrir(tester, c);
    await _preencher(tester, atual: 'errada123');
    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();
    expect(find.text('A senha atual está incorreta.'), findsOneWidget);
    expect(find.byType(AlterarSenhaPage), findsOneWidget);
  });

  testWidgets('troca a senha, avisa e volta; a sessao continua logada', (tester) async {
    final recebidos = <Map<String, dynamic>>[];
    final (c, _) = await _logar((_) => http.Response('', 204), recebidos: recebidos);
    await _abrir(tester, c);
    await _preencher(tester);
    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();
    expect(recebidos, [
      {'senha_atual': 'antiga123', 'senha_nova': 'nova12345'}
    ]);
    expect(find.byType(AlterarSenhaPage), findsNothing);
    expect(find.text('Senha alterada.'), findsOneWidget);
    expect(c.read(sessaoProvider).fase, FaseSessao.logado);
  });

  test('se o aparelho lembra a senha, guarda a nova no lugar da antiga', () async {
    final (c, guarda) = await _logar((_) => http.Response('', 204));
    await guarda.gravar(const SessaoSalva(token: 'tok', emailLembrado: 'a@b.com', senhaLembrada: 'antiga123'));
    await c.read(sessaoProvider.notifier).alterarSenha('antiga123', 'nova12345');
    expect(guarda.valor?.senhaLembrada, 'nova12345');
    expect(guarda.valor?.emailLembrado, 'a@b.com');
  });
}
