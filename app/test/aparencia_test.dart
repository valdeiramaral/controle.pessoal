import 'dart:convert';

import 'package:controle_pessoal/app.dart';
import 'package:controle_pessoal/core/aparencia.dart';
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
import 'util_testes.dart';

class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

void main() {
  test('Aparencia.deJson aceita {} e ignora valores invalidos', () {
    expect(Aparencia.deJson(<String, dynamic>{}), Aparencia.padrao);
    expect(Aparencia.deJson(null), Aparencia.padrao);
    final a = Aparencia.deJson({'modo': 'claro', 'escala': 1.15, 'cor': 'verde'});
    expect(a.modo, ModoAparencia.claro);
    expect(a.escala, 1.15);
    expect(a.cor, 'verde');
    expect(Aparencia.deJson({'modo': 'x', 'escala': 9, 'cor': 'marrom'}), Aparencia.padrao);
    expect(Aparencia.deJson(a.paraJson()), a);
  });

  testWidgets('tela Aparencia: troca tema, letra e cor, guarda na conta e restaura o padrao', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const u = UsuarioApi(id: 'u', nome: 'Bia');
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final salvos = <Map<String, dynamic>>[];
    final cliente = MockClient((r) async {
      if (r.url.path == '/me/preferencias' && r.method == 'PUT') {
        salvos.add(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return http.Response.bytes(utf8.encode('{}'), 200, headers: {'content-type': 'application/json'});
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: cliente)),
        armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
        sessaoProvider.overrideWith(() => _SessaoFalsa(
            const EstadoSessao(FaseSessao.logado, token: 't', usuario: u, perfil: PerfilApi(usuario: u)))),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('menu_aparencia')));
    await tester.pumpAndSettle();
    expect(find.text('Cor do sistema'), findsOneWidget);

    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(salvos.last['modo'], 'claro');
    expect(Theme.of(tester.element(find.text('Cor do sistema'))).brightness, Brightness.light);

    await tester.tap(find.byKey(const Key('letra_Grande')));
    await tester.pumpAndSettle();
    expect(salvos.last['escala'], 1.15);
    expect(MediaQuery.of(tester.element(find.text('Cor do sistema'))).textScaler.scale(10), closeTo(11.5, .01));

    await tester.tap(find.byKey(const Key('cor_verde')));
    await tester.pumpAndSettle();
    expect(salvos.last['cor'], 'verde');

    await tester.tap(find.byKey(const Key('restaurar_aparencia')));
    await tester.pumpAndSettle();
    expect(salvos.last, {'modo': 'escuro', 'escala': 1.0, 'cor': 'azul'});
    expect(Theme.of(tester.element(find.text('Cor do sistema'))).brightness, Brightness.dark);
    await encerrar(tester);
  });
}
