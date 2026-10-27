import '../data/local/banco.dart';
import 'pagamento.dart';

/// Saldo atual, em centavos: saldo inicial das contas + lancamentos PAGOS.
///
/// - receita soma, despesa subtrai;
/// - transferencia fica de fora: ela sai de uma conta e entra em outra, entao
///   o total geral nao muda (o esquema ainda nao tem conta de destino);
/// - contas externas (de terceiros) nao entram;
/// - registros excluidos logicamente (excluidoEm) nao entram.
int calcularSaldoCentavos(
  Iterable<Conta> contas,
  Iterable<Lancamento> lancamentos,
) {
  var saldo = 0;
  for (final c in contas) {
    if (c.excluidoEm == null && c.titularidade != 'externa') saldo += c.saldoInicialCentavos;
  }
  for (final l in lancamentos) {
    if (l.excluidoEm != null || l.status != 'pago') continue;
    if (l.tipo == 'receita') {
      saldo += valorEfetivo(l);
    } else if (l.tipo == 'despesa') {
      saldo -= valorEfetivo(l);
    }
  }
  return saldo;
}

/// Saldo de UMA conta, em centavos: saldo inicial + lancamentos pagos dela (receita soma, despesa subtrai).
int calcularSaldoDaContaCentavos(Conta conta, Iterable<Lancamento> lancamentos) {
  var saldo = conta.saldoInicialCentavos;
  for (final l in lancamentos) {
    if (contaEfetiva(l) != conta.id || l.excluidoEm != null || l.status != 'pago') continue;
    if (l.tipo == 'receita') {
      saldo += valorEfetivo(l);
    } else if (l.tipo == 'despesa') {
      saldo -= valorEfetivo(l);
    }
  }
  return saldo;
}
