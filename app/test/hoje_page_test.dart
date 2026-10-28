import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/features/hoje/hoje_page.dart';
import 'package:controle_pessoal/features/nav/modulos_menu.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'util_testes.dart';

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
      overrides: [bancoProvider.overrideWithValue(banco)],
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

    // o Resumo faz parte da mesma aba do modulo Financas
    expect(find.text('Resumo do período'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await encerrar(tester);
  });
  testWidgets('abas e indicadores so aparecem para os modulos liberados ao usuario', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);

    const nomes = {'painel': 'Agenda do Dia', 'agenda': 'Tarefas', 'financas': 'Minhas Finanças', 'saude': 'Saúde'};

    Future<void> abrir(List<String> codigos) async {
      await tester.pumpWidget(const SizedBox.shrink()); // zera o cache dos providers entre os casos
      await tester.pumpWidget(ProviderScope(
        overrides: [
          bancoProvider.overrideWithValue(banco),
          modulosMenuProvider.overrideWith((ref) async => [for (final c in codigos) ModuloMenu(codigo: c, nome: nomes[c]!)]),
        ],
        child: MaterialApp(theme: temaApp(), home: const HojePage()),
      ));
      await tester.pumpAndSettle();
    }

    String nomeAba(int i) =>
        tester.widget<Text>(find.descendant(of: find.byKey(Key('aba_$i')), matching: find.byType(Text))).data!;

    // so Saude liberada: so a aba com o nome do modulo e o indicador de remedios
    await abrir(['painel', 'saude']);
    expect(nomeAba(0), 'Saúde');
    expect(find.byKey(const Key('aba_1')), findsNothing);
    expect(find.text('Resumo do período'), findsNothing);
    expect(find.byKey(const Key('kpi_remedios')), findsOneWidget);
    expect(find.byKey(const Key('kpi_compromissos')), findsNothing);
    expect(find.byKey(const Key('kpi_abertas')), findsNothing);

    // Agenda e Financas: uma aba para cada, com o nome cadastrado do modulo; sem Remedios
    await abrir(['painel', 'agenda', 'financas']);
    expect(nomeAba(0), 'Tarefas');
    expect(nomeAba(1), 'Minhas Finanças');
    expect(find.byKey(const Key('aba_2')), findsNothing);
    expect(find.byKey(const Key('kpi_remedios')), findsNothing);
    expect(find.byKey(const Key('kpi_compromissos')), findsOneWidget);

    // nenhum modulo com painel
    await abrir(['painel']);
    expect(find.byKey(const Key('sem_abas')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await encerrar(tester);
  });

  testWidgets('abas dos demais modulos ativos: Leitura, Biblioteca e Senha (sem segredos) e tarefas na Agenda', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final hoje = DateTime.now();
    await banco.inserirLeitura(titulo: 'Dom Casmurro', autor: 'Machado', iniciouEm: hoje.subtract(const Duration(days: 40)));
    await banco.inserirLeitura(titulo: 'Livro Antigo Lido', terminouEm: hoje.subtract(const Duration(days: 300)));
    await banco.inserirObra(ObrasCompanion(tombo: const Value(40102), titulo: const Value('Memórias Póstumas')));
    await banco.inserirCredencial(CredenciaisCompanion(
        titulo: const Value('Gmail'), senhaAtual: const Value('v1:cifrado-que-nao-deve-aparecer')));
    await banco.inserirTarefa(titulo: 'Pagar IPTU', prazo: hoje);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        modulosMenuProvider.overrideWith((ref) async => [
              const ModuloMenu(codigo: 'painel', nome: 'Agenda do Dia'),
              const ModuloMenu(codigo: 'agenda', nome: 'Tarefas'),
              const ModuloMenu(codigo: 'leitura', nome: 'Leitura'),
              const ModuloMenu(codigo: 'biblioteca', nome: 'Biblioteca'),
              const ModuloMenu(codigo: 'senha', nome: 'Senha'),
            ]),
      ],
      child: MaterialApp(theme: temaApp(), home: const HojePage()),
    ));
    await tester.pumpAndSettle();

    // uma aba por modulo, com o nome do modulo: Tarefas, Leitura, Biblioteca, Senha
    String nomeAba(int i) =>
        tester.widget<Text>(find.descendant(of: find.byKey(Key('aba_$i')), matching: find.byType(Text))).data!;
    expect([for (var i = 0; i < 4; i++) nomeAba(i)], ['Tarefas', 'Leitura', 'Biblioteca', 'Senha']);
    expect(find.byKey(const Key('aba_3')), findsOneWidget);
    expect(find.byKey(const Key('aba_4')), findsNothing);

    // Agenda: compromissos + tarefas com prazo no periodo
    expect(find.text('Pagar IPTU'), findsOneWidget);

    await tester.tap(find.byKey(const Key('aba_1')));
    await tester.pumpAndSettle();
    expect(find.text('Dom Casmurro'), findsOneWidget); // em leitura (iniciada fora do periodo)
    expect(find.text('Livro Antigo Lido'), findsNothing);

    await tester.tap(find.byKey(const Key('aba_2')));
    await tester.pumpAndSettle();
    expect(find.text('Memórias Póstumas'), findsOneWidget);
    expect(find.byKey(const Key('resumo_biblioteca')), findsOneWidget);

    await tester.tap(find.byKey(const Key('aba_3')));
    await tester.pumpAndSettle();
    expect(find.text('Gmail'), findsOneWidget);
    expect(find.textContaining('cifrado'), findsNothing);
    await encerrar(tester);
  });
}
