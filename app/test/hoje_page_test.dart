import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:controle_pessoal/features/hoje/hoje_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

const _u = UsuarioApi(id: 'u', nome: 'Bia');

Override _sessao({required bool superusuario}) => sessaoProvider.overrideWith(() => _SessaoFalsa(EstadoSessao(
      FaseSessao.logado,
      token: 't',
      usuario: _u,
      perfil: PerfilApi(usuario: _u, superusuario: superusuario),
    )));

void main() {
  test('atalhos de periodo', () {
    final quarta = DateTime(2026, 10, 28);
    final semana = periodoRapido('Esta semana', quarta);
    expect(semana.start, DateTime(2026, 10, 26));
    expect(semana.end, DateTime(2026, 11, 1));
    final mes = periodoRapido('Mês passado', quarta);
    expect(mes.start, DateTime(2026, 9, 1));
    expect(mes.end, DateTime(2026, 9, 30));
    expect(periodoRapido('Hoje', quarta).start, periodoRapido('Hoje', quarta).end);
  });

  testWidgets('painel com filtros, indicadores e abas; contas em aberto e atrasadas', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    await banco.inserirEvento(titulo: 'Dentista', inicio: DateTime.now().add(const Duration(hours: 1)));
    await banco.inserirLancamento(
        descricao: 'Aluguel', valorCentavos: 100000, tipo: 'despesa', dia: DateTime.now().subtract(const Duration(days: 3)));
    await banco.inserirLancamento(descricao: 'Luz', valorCentavos: 20000, tipo: 'despesa', dia: DateTime.now());

    await tester.pumpWidget(ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco), armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()), _sessao(superusuario: true)],
      child: MaterialApp(theme: temaApp(), home: const HojePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('campo_de')), findsOneWidget);
    expect(find.byKey(const Key('botao_consultar')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('kpi_atrasadas'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const Key('kpi_abertas'))).data, '2');

    expect(find.text('Dentista'), findsOneWidget); // aba Agenda
    await tester.tap(find.byKey(const Key('aba_1')));
    await tester.pumpAndSettle();
    expect(find.text('Aluguel'), findsOneWidget); // em aberto fora do periodo
    expect(find.text('ATRASADA'), findsOneWidget);
    await tester.tap(find.byKey(const Key('status_Atrasadas')));
    await tester.pumpAndSettle();
    expect(find.text('Luz'), findsNothing);

    await tester.tap(find.byKey(const Key('aba_3')));
    await tester.pumpAndSettle();
    expect(find.text('Resumo do período'), findsOneWidget);
  });

  testWidgets('usuario comum nao ve lancamentos: sem abas de contas e resumo nem indicadores financeiros', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    await banco.inserirLancamento(descricao: 'Aluguel', valorCentavos: 100000, tipo: 'despesa');

    await tester.pumpWidget(ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco), armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()), _sessao(superusuario: false)],
      child: MaterialApp(theme: temaApp(), home: const HojePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('aba_0')), findsOneWidget);
    expect(find.byKey(const Key('aba_2')), findsOneWidget);
    expect(find.byKey(const Key('aba_1')), findsNothing);
    expect(find.byKey(const Key('aba_3')), findsNothing);
    expect(find.byKey(const Key('kpi_atrasadas')), findsNothing);
    expect(find.byKey(const Key('kpi_a_pagar')), findsNothing);
    expect(find.byKey(const Key('incluir_abertas')), findsNothing);
    expect(find.text('Aluguel'), findsNothing);
  });
}
