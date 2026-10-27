import '../data/local/banco.dart';
import 'pagamento.dart';

/// Variacao percentual (arredondada) de [atual] sobre [anterior]; null quando nao ha base de comparacao.
int? variacaoPercentual(int atual, int anterior) {
  if (anterior == 0) return null;
  return ((atual - anterior) / anterior.abs() * 100).round();
}

class ItemRanking {
  const ItemRanking({required this.nome, required this.cor, required this.valorCentavos, required this.percentual});
  final String nome;
  final String? cor; // hexadecimal "#RRGGBB" ou null
  final int valorCentavos;
  final double percentual; // 0..100
}

class LinhaConta {
  const LinhaConta({
    required this.nome,
    required this.tipo,
    required this.receitasCentavos,
    required this.despesasCentavos,
    required this.saldoCentavos,
    required this.previstoCentavos,
  });
  final String nome;
  final String tipo;
  final int receitasCentavos;
  final int despesasCentavos;
  final int saldoCentavos;
  final int previstoCentavos;
}

class ItemOrcamento {
  const ItemOrcamento({
    required this.categoria,
    required this.cor,
    required this.limiteCentavos,
    required this.gastoCentavos,
  });
  final String categoria;
  final String? cor;
  final int limiteCentavos;
  final int gastoCentavos;

  /// Percentual do limite ja gasto (pode passar de 100).
  int get percentual => limiteCentavos <= 0 ? 0 : (gastoCentavos / limiteCentavos * 100).round();
  bool get estourou => gastoCentavos > limiteCentavos;
}

class FatiaRecorrencia {
  const FatiaRecorrencia({required this.nome, required this.valorCentavos, required this.percentual});
  final String nome;
  final int valorCentavos;
  final double percentual;
}

class DadosDashboard {
  const DadosDashboard({
    required this.saldoInicialMesCentavos,
    required this.saldoAtualCentavos,
    required this.previstoCentavos,
    required this.receitasCentavos,
    required this.despesasCentavos,
    required this.faturasCentavos,
    required this.varSaldo,
    required this.varReceitas,
    required this.varDespesas,
    required this.varFaturas,
    required this.ranking,
    required this.contas,
    required this.orcamentos,
    required this.recorrencia,
    required this.progressoDoMes,
  });

  final int saldoInicialMesCentavos;
  final int saldoAtualCentavos;
  final int previstoCentavos;
  final int receitasCentavos;
  final int despesasCentavos;
  final int faturasCentavos;
  final int? varSaldo;
  final int? varReceitas;
  final int? varDespesas;
  final int? varFaturas;
  final List<ItemRanking> ranking;
  final List<LinhaConta> contas;
  final List<ItemOrcamento> orcamentos;
  final List<FatiaRecorrencia> recorrencia;

  /// Fracao do mes ja decorrida (0..1) quando o mes exibido e o atual; null nos outros meses.
  final double? progressoDoMes;

  int get totalRecorrenciaCentavos => recorrencia.fold(0, (s, f) => s + f.valorCentavos);
}

/// Calcula todos os numeros do dashboard de [mes] (qualquer dia do mes). Tudo em centavos.
///
/// - so entram registros ativos (excluidoEm nulo); transferencias nao contam como receita nem despesa;
/// - saldo inicial do mes = saldo inicial das contas + lancamentos pagos antes do mes;
/// - saldo atual = saldo inicial das contas + pagos ate o fim do mes;
/// - previsto = saldo inicial das contas + todos (pagos e pendentes) ate o fim do mes;
/// - recebido/gasto = lancamentos de data dentro do mes (pagos ou nao);
/// - faturas = despesas do mes em contas do tipo cartao;
/// - variacao = comparacao com o mes anterior.
DadosDashboard calcularDashboard({
  required Iterable<Conta> contas,
  required Iterable<Categoria> categorias,
  required Iterable<Lancamento> lancamentos,
  required Iterable<Orcamento> orcamentos,
  required DateTime mes,
  required DateTime hoje,
}) {
  // Contas externas (de terceiros) so existem no cadastro: nao entram nos saldos.
  final cs = contas.where((c) => c.excluidoEm == null && c.titularidade != 'externa').toList();
  final ls = lancamentos.where((l) => l.excluidoEm == null && (l.tipo == 'receita' || l.tipo == 'despesa')).toList();
  final cats = {for (final c in categorias.where((c) => c.excluidoEm == null)) c.id: c};
  final cartoes = {for (final c in cs.where((c) => c.tipo == 'cartao')) c.id};

  final ini = DateTime(mes.year, mes.month, 1);
  final fim = DateTime(mes.year, mes.month + 1, 1);
  final iniAnt = DateTime(mes.year, mes.month - 1, 1);

  int sinal(Lancamento l) => l.tipo == 'receita' ? valorEfetivo(l) : -valorEfetivo(l);
  bool noMes(Lancamento l, DateTime de, DateTime ate) => !l.dia.isBefore(de) && l.dia.isBefore(ate);

  final base = cs.fold<int>(0, (s, c) => s + c.saldoInicialCentavos);
  int saldoAte(DateTime limite, {required bool soPagos}) =>
      base +
      ls
          .where((l) => l.dia.isBefore(limite) && (!soPagos || l.status == 'pago'))
          .fold<int>(0, (s, l) => s + sinal(l));

  int somaMes(String tipo, DateTime de, DateTime ate, {bool soCartao = false}) => ls
      .where((l) => l.tipo == tipo && noMes(l, de, ate) && (!soCartao || cartoes.contains(l.contaId)))
      .fold<int>(0, (s, l) => s + l.valorCentavos);

  final saldoIni = saldoAte(ini, soPagos: true);
  final saldoAtual = saldoAte(fim, soPagos: true);
  final previsto = saldoAte(fim, soPagos: false);
  final receitas = somaMes('receita', ini, fim);
  final despesas = somaMes('despesa', ini, fim);
  final faturas = somaMes('despesa', ini, fim, soCartao: true);

  final despesasDoMes = ls.where((l) => l.tipo == 'despesa' && noMes(l, ini, fim)).toList();

  // Ranking de categorias.
  final porCategoria = <String?, int>{};
  for (final l in despesasDoMes) {
    final k = cats.containsKey(l.categoriaId) ? l.categoriaId : null;
    porCategoria[k] = (porCategoria[k] ?? 0) + l.valorCentavos;
  }
  final ranking = porCategoria.entries
      .map((e) => ItemRanking(
            nome: e.key == null ? 'Sem categoria' : cats[e.key]!.nome,
            cor: e.key == null ? null : cats[e.key]!.cor,
            valorCentavos: e.value,
            percentual: despesas == 0 ? 0 : e.value / despesas * 100,
          ))
      .toList()
    ..sort((a, b) => b.valorCentavos.compareTo(a.valorCentavos));

  // Contas.
  final linhas = cs.map((c) {
    final dela = ls.where((l) => contaEfetiva(l) == c.id).toList();
    int soma(Iterable<Lancamento> xs) => xs.fold<int>(0, (s, l) => s + sinal(l));
    return LinhaConta(
      nome: c.nome,
      tipo: c.tipo,
      receitasCentavos:
          dela.where((l) => l.tipo == 'receita' && noMes(l, ini, fim)).fold<int>(0, (s, l) => s + l.valorCentavos),
      despesasCentavos:
          dela.where((l) => l.tipo == 'despesa' && noMes(l, ini, fim)).fold<int>(0, (s, l) => s + l.valorCentavos),
      saldoCentavos:
          c.saldoInicialCentavos + soma(dela.where((l) => l.dia.isBefore(fim) && l.status == 'pago')),
      previstoCentavos: c.saldoInicialCentavos + soma(dela.where((l) => l.dia.isBefore(fim))),
    );
  }).toList();

  // Orcamentos do mes.
  final itensOrc = orcamentos
      .where((o) => o.excluidoEm == null && o.mes.year == ini.year && o.mes.month == ini.month)
      .map((o) {
        final cat = cats[o.categoriaId];
        final gasto = despesasDoMes.where((l) => l.categoriaId == o.categoriaId).fold<int>(0, (s, l) => s + l.valorCentavos);
        return ItemOrcamento(
          categoria: cat?.nome ?? 'Categoria removida',
          cor: cat?.cor,
          limiteCentavos: o.valorLimiteCentavos,
          gastoCentavos: gasto,
        );
      })
      .toList()
    ..sort((a, b) => b.percentual.compareTo(a.percentual));

  // Recorrencia: fixa (tem regra de repeticao), parcelada (tem parcelas) ou variavel.
  var fixas = 0, parceladas = 0, variaveis = 0;
  for (final l in despesasDoMes) {
    if (l.recorrencia != null && l.recorrencia!.isNotEmpty) {
      fixas += l.valorCentavos;
    } else if (l.parcelaTotal != null) {
      parceladas += l.valorCentavos;
    } else {
      variaveis += l.valorCentavos;
    }
  }
  FatiaRecorrencia fatia(String nome, int v) =>
      FatiaRecorrencia(nome: nome, valorCentavos: v, percentual: despesas == 0 ? 0 : v / despesas * 100);
  final recorrencia = [fatia('Fixas', fixas), fatia('Parceladas', parceladas), fatia('Variáveis', variaveis)];

  final hojeNoMes = hoje.year == ini.year && hoje.month == ini.month;
  final diasNoMes = fim.difference(ini).inDays;

  return DadosDashboard(
    saldoInicialMesCentavos: saldoIni,
    saldoAtualCentavos: saldoAtual,
    previstoCentavos: previsto,
    receitasCentavos: receitas,
    despesasCentavos: despesas,
    faturasCentavos: faturas,
    varSaldo: variacaoPercentual(saldoAtual, saldoIni),
    varReceitas: variacaoPercentual(receitas, somaMes('receita', iniAnt, ini)),
    varDespesas: variacaoPercentual(despesas, somaMes('despesa', iniAnt, ini)),
    varFaturas: variacaoPercentual(faturas, somaMes('despesa', iniAnt, ini, soCartao: true)),
    ranking: ranking,
    contas: linhas,
    orcamentos: itensOrc,
    recorrencia: recorrencia,
    progressoDoMes: hojeNoMes ? hoje.day / diasNoMes : null,
  );
}
