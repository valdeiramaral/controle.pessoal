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
import 'util_testes.dart';

class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

void main() {
  testWidgets('nome, e-mail e Sair aparecem no topo de todas as telas, tambem ao trocar de modulo', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    const u = UsuarioApi(id: 'u', nome: 'Bia Souza', email: 'bia@exemplo.com');
    final container = ProviderContainer(overrides: [
      bancoProvider.overrideWithValue(banco),
      armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
      sessaoProvider.overrideWith(() => _SessaoFalsa(
          const EstadoSessao(FaseSessao.logado, token: 't', usuario: u, perfil: PerfilApi(usuario: u)))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: temaApp(), home: const Casca()),
    ));
    await tester.pumpAndSettle();

    for (final modulo in ['Hoje', 'Finanças', 'Saúde', 'Agenda']) {
      await tester.tap(find.descendant(of: find.byType(MenuLateral), matching: find.text(modulo)));
      await tester.pumpAndSettle();
      expect(find.text('Bia Souza'), findsOneWidget, reason: modulo);
      expect(find.text('bia@exemplo.com'), findsOneWidget, reason: modulo);
      expect(find.byKey(const Key('botao_sair_topo')), findsOneWidget, reason: modulo);
    }

    await tester.tap(find.byKey(const Key('botao_sair_topo')));
    await tester.pumpAndSettle();
    expect(container.read(sessaoProvider).fase, FaseSessao.deslogado);
    await encerrar(tester);
  });
}
