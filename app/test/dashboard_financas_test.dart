import 'package:controle_pessoal/core/dashboard.dart';
import 'package:controle_pessoal/core/formatos.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/financas/dashboard_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'util_testes.dart';

final hoje = DateTime(2026, 10, 15);

/// Cenario: duas contas (Itau e um cartao), duas categorias, setembro e outubro.
Future<void> popular(Banco b) async {
  final itau = await b.inserirConta(nome: 'Itaú', saldoInicialCentavos: 100000);
  final cartao = await b.inserirConta(nome: 'Cartão', tipo: 'cartao');
  final mercado = await b.inserirCategoria(nome: 'Mercado', cor: '#FB8C00');
  final moradia = await b.inserirCategoria(nome: 'Moradia');

  Future<void> l(String d, int v, String tipo, DateTime dia,
          {bool pago = true, String? conta, String? cat, String? rec, int? parcelas}) =>
      b.inserirLancamento(
        descricao: d,
        valorCentavos: v,
        tipo: tipo,
        pago: pago,
        dia: dia,
        contaId: conta ?? itau,
        categoriaId: cat,
        recorrencia: rec,
        parcelaTotal: parcelas,
      );

  await l('Mercado setembro', 10000, 'despesa', DateTime(2026, 9, 10));
  await l('Salário', 300000, 'receita', DateTime(2026, 10, 5));
  await l('Mercado', 20000, 'despesa', DateTime(2026, 10, 6), cat: mercado);
  await l('Aluguel', 60000, 'despesa', DateTime(2026, 10, 20), pago: false, cat: moradia);
  await l('Compra no cartão', 30000, 'despesa', DateTime(2026, 10, 8), conta: cartao, cat: mercado);
  await l('TV (1/3)', 10000, 'despesa', DateTime(2026, 10, 25), pago: false, parcelas: 3);
  await l('Streaming', 5000, 'despesa', DateTime(2026, 10, 10), rec: 'FREQ=MONTHLY');
  await l('Transferência', 99999, 'transferencia', DateTime(2026, 10, 12));
  await b.definirOrcamento(categoriaId: mercado, mes: DateTime(2026, 10, 20), valorLimiteCentavos: 40000);
  await b.definirOrcamento(categoriaId: moradia, mes: DateTime(2026, 10, 1), valorLimiteCentavos: 120000);
}

Future<DadosDashboard> calcular(Banco b, DateTime mes) async => calcularDashboard(
      contas: await b.select(b.contas).get(),
      categorias: await b.select(b.categorias).get(),
      lancamentos: await b.select(b.lancamentos).get(),
      orcamentos: await b.select(b.orcamentos).get(),
      mes: mes,
      hoje: hoje,
    );

void main() {
  late Banco banco;
  setUp(() => banco = Banco.paraTeste(NativeDatabase.memory()));
  tearDown(() => banco.close());

  test('variacao percentual', () {
    expect(variacaoPercentual(150, 100), 50);
    expect(variacaoPercentual(50, 100), -50);
    expect(variacaoPercentual(10, 0), isNull);
  });

  test('saldos: inicial do mes, atual e previsto', () async {
    await popular(banco);
    final d = await calcular(banco, DateTime(2026, 10, 1));
    expect(d.saldoInicialMesCentavos, 90000); // 1.000,00 - 100,00 de setembro
    expect(d.saldoAtualCentavos, 335000); // so pagos; transferencia nao conta
    expect(d.previstoCentavos, 265000); // menos aluguel e parcela pendentes
  });

  test('visao geral e variacao contra o mes anterior', () async {
    await popular(banco);
    final d = await calcular(banco, DateTime(2026, 10, 15));
    expect(d.receitasCentavos, 300000);
    expect(d.despesasCentavos, 125000);
    expect(d.faturasCentavos, 30000);
    expect(d.varReceitas, isNull); // setembro sem receita
    expect(d.varDespesas, 1150); // (125.000 - 10.000) / 10.000
    expect(d.varSaldo, 272);
  });

  test('ranking de categorias ordenado, com percentual e sem categoria', () async {
    await popular(banco);
    final r = (await calcular(banco, DateTime(2026, 10, 1))).ranking;
    expect(r.map((e) => e.nome), ['Moradia', 'Mercado', 'Sem categoria']);
    expect(r.map((e) => e.valorCentavos), [60000, 50000, 15000]);
    expect(r.first.percentual, closeTo(48, 0.01));
  });

  test('tabela de contas', () async {
    await popular(banco);
    final c = (await calcular(banco, DateTime(2026, 10, 1))).contas;
    final itau = c.firstWhere((x) => x.nome == 'Itaú');
    expect(itau.receitasCentavos, 300000);
    expect(itau.despesasCentavos, 95000);
    expect(itau.saldoCentavos, 365000);
    expect(itau.previstoCentavos, 295000);
    final cartao = c.firstWhere((x) => x.nome == 'Cartão');
    expect(cartao.despesasCentavos, 30000);
    expect(cartao.saldoCentavos, -30000);
  });

  test('orcamentos: gasto, percentual, estouro e marcador de hoje', () async {
    await popular(banco);
    final d = await calcular(banco, DateTime(2026, 10, 1));
    expect(d.orcamentos.length, 2);
    final mercado = d.orcamentos.first; // mais consumido primeiro
    expect(mercado.categoria, 'Mercado');
    expect(mercado.gastoCentavos, 50000);
    expect(mercado.percentual, 125);
    expect(mercado.estourou, isTrue);
    expect(d.orcamentos.last.percentual, 50);
    expect(d.progressoDoMes, closeTo(15 / 31, 0.001));
    expect((await calcular(banco, DateTime(2026, 9, 1))).progressoDoMes, isNull);
  });

  test('definir orcamento da mesma categoria no mesmo mes troca o limite', () async {
    final cat = await banco.inserirCategoria(nome: 'Lazer');
    await banco.definirOrcamento(categoriaId: cat, mes: DateTime(2026, 10, 9), valorLimiteCentavos: 1000);
    await banco.definirOrcamento(categoriaId: cat, mes: DateTime(2026, 10, 1), valorLimiteCentavos: 2500);
    final todos = await banco.select(banco.orcamentos).get();
    expect(todos.length, 1);
    expect(todos.single.valorLimiteCentavos, 2500);
  });

  test('recorrencia: fixas, parceladas e variaveis', () async {
    await popular(banco);
    final r = (await calcular(banco, DateTime(2026, 10, 1))).recorrencia;
    expect(r.map((f) => f.valorCentavos), [5000, 10000, 110000]);
    expect(r.fold<double>(0, (s, f) => s + f.percentual), closeTo(100, 0.001));
  });

  test('inserirParcelado cria uma parcela por mes', () async {
    await banco.inserirParcelado(
        descricao: 'Geladeira', valorParcelaCentavos: 20000, tipo: 'despesa', parcelas: 3, primeiroDia: DateTime(2026, 11, 30));
    final ls = await banco.select(banco.lancamentos).get();
    expect(ls.length, 3);
    expect(ls.every((x) => x.parcelaTotal == 3 && x.grupoParcelas != null && x.status == 'pendente'), isTrue);
    expect(ls.map((x) => x.parcelaNumero).toSet(), {1, 2, 3});
  });

  testWidgets('dashboard mostra os cartoes e navega entre meses', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await popular(banco);

    await tester.pumpWidget(ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco)],
      child: MaterialApp(theme: temaApp(), home: Scaffold(body: DashboardFinancas(hoje: hoje))),
    ));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('mes_titulo'))).data, 'outubro de 2026');
    expect(tester.widget<Text>(find.byKey(const Key('saldo_inicial'))).data, formatarCentavos(90000));
    expect(tester.widget<Text>(find.byKey(const Key('saldo_atual'))).data, formatarCentavos(335000));
    expect(tester.widget<Text>(find.byKey(const Key('saldo_previsto'))).data, formatarCentavos(265000));
    expect(tester.widget<Text>(find.byKey(const Key('ind_recebido'))).data, formatarCentavos(300000));
    expect(tester.widget<Text>(find.byKey(const Key('ind_gasto'))).data, formatarCentavos(125000));
    expect(tester.widget<Text>(find.byKey(const Key('rosca_total'))).data, formatarCentavos(125000));
    for (final t in ['Ranking categorias', 'Visão geral', 'Contas', 'Orçamentos de despesas', 'Despesas por recorrência', 'Itaú', 'Hoje']) {
      expect(find.text(t), findsWidgets, reason: t);
    }

    await tester.tap(find.byKey(const Key('mes_anterior')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('mes_titulo'))).data, 'setembro de 2026');
    expect(tester.widget<Text>(find.byKey(const Key('ind_gasto'))).data, formatarCentavos(10000));
    expect(find.text('Hoje'), findsNothing); // marcador so no mes atual
    expect(tester.takeException(), isNull);
    await encerrar(tester);
  });

  testWidgets('dashboard vazio nao quebra e orienta o usuario', (tester) async {
    tester.view.physicalSize = const Size(500, 2400); // tela estreita: cartoes empilhados
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco)],
      child: MaterialApp(theme: temaApp(), home: Scaffold(body: DashboardFinancas(hoje: hoje))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sem despesas neste mês.'), findsOneWidget);
    expect(find.textContaining('Nenhum orçamento neste mês'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('saldo_atual'))).data, formatarCentavos(0));
    expect(tester.takeException(), isNull);
    await encerrar(tester);
  });
}
