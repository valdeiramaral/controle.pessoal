import 'package:controle_pessoal/core/lancamento_calculo.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:controle_pessoal/features/financas/financas_page.dart';
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

Future<void> _lancar(Banco b, String desc, int valor, String tipo, DateTime dia) =>
    b.lancar(descricao: desc, valorCentavos: valor, tipo: tipo, vencimento: dia, contaId: contaPadraoId);

void main() {
  test('agruparPorMes: meses e datas em ordem crescente, com totais de receitas e despesas', () async {
    final b = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(b.close);
    await _lancar(b, 'Luz', 20000, 'despesa', DateTime(2026, 11, 20));
    await _lancar(b, 'Salário', 500000, 'receita', DateTime(2026, 10, 5));
    await _lancar(b, 'Aluguel', 150000, 'despesa', DateTime(2026, 11, 5));
    await _lancar(b, 'Mercado', 30050, 'despesa', DateTime(2026, 10, 12));
    await _lancar(b, 'Freela', 80000, 'receita', DateTime(2026, 11, 8));
    await _lancar(b, 'Seguro', 10000, 'despesa', DateTime(2027, 1, 2));

    final g = agruparPorMes(await b.observarLancamentos().first);
    expect([for (final x in g) (x.ano, x.mes)], [(2026, 10), (2026, 11), (2027, 1)]);
    expect(g[0].itens.map((l) => l.descricao), ['Salário', 'Mercado']);
    expect(g[1].itens.map((l) => l.descricao), ['Aluguel', 'Freela', 'Luz']);
    expect([g[0].receitasCentavos, g[0].despesasCentavos, g[0].saldoCentavos], [500000, 30050, 469950]);
    expect([g[1].receitasCentavos, g[1].despesasCentavos, g[1].saldoCentavos], [80000, 170000, -90000]);
    expect([g[2].receitasCentavos, g[2].despesasCentavos], [0, 10000]);
    expect(agruparPorMes(const []), isEmpty);
  });

  testWidgets('aba Lancamentos: meses em ordem crescente, recolhidos (menos o atual), com totais; expande ao tocar', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, 15);
    await _lancar(banco, 'Receita antiga', 100000, 'receita', DateTime(2020, 3, 10));
    await _lancar(banco, 'Despesa antiga', 25000, 'despesa', DateTime(2020, 3, 12));
    await _lancar(banco, 'Conta deste mes', 7000, 'despesa', hoje);
    final antigo = '${2020}_${3}';
    final atual = '${hoje.year}_${hoje.month}';

    const u = UsuarioApi(id: 'u', nome: 'Bia');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
        sessaoProvider.overrideWith(() => _SessaoFalsa(
            const EstadoSessao(FaseSessao.logado, token: 't', usuario: u, perfil: PerfilApi(usuario: u)))),
      ],
      child: MaterialApp(theme: temaApp(), home: const FinancasPage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aba_lancamentos')));
    await tester.pumpAndSettle();

    // Março de 2020 vem antes do mes atual
    expect(find.text('Março de 2020'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(Key('mes_$antigo'))).dy, lessThan(tester.getTopLeft(find.byKey(Key('mes_$atual'))).dy));
    // totais do mes
    expect(tester.widget<Text>(find.byKey(Key('receitas_$antigo'))).data, contains('1.000,00'));
    expect(tester.widget<Text>(find.byKey(Key('despesas_$antigo'))).data, contains('250,00'));
    // o mes atual vem aberto e o antigo, recolhido
    expect(find.text('Conta deste mes'), findsOneWidget);
    expect(find.text('Despesa antiga'), findsNothing);
    await tester.tap(find.byKey(Key('mes_$antigo')));
    await tester.pumpAndSettle();
    expect(find.text('Despesa antiga'), findsOneWidget);
    expect(find.text('Receita antiga'), findsOneWidget);

    // tocar no nome nao abre nada; alterar e excluir ficam nos icones
    await tester.tap(find.text('Despesa antiga'));
    await tester.pumpAndSettle();
    expect(find.text('Despesa antiga'), findsOneWidget);
    expect(find.byType(FinancasPage), findsOneWidget);
    final todos = await banco.select(banco.lancamentos).get();
    final antiga = todos.firstWhere((l) => l.descricao == 'Despesa antiga');
    expect(find.byKey(Key('editar_${antiga.id}')), findsOneWidget);
    await tester.tap(find.byKey(Key('excluir_${antiga.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Excluir lançamento?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmar_exclusao_lancamento')));
    await tester.pumpAndSettle();
    expect(find.text('Despesa antiga'), findsNothing);
    expect(find.text('Receita antiga'), findsOneWidget);
    await encerrar(tester);
  });
}
