import '../data/local/banco.dart';

/// Saldo atual, em centavos: saldo inicial das contas + lancamentos PAGOS.
///
/// - receita soma, despesa subtrai;
/// - transferencia fica de fora: ela sai de uma conta e entra em outra, entao
///   o total geral nao muda (o esquema ainda nao tem conta de destino);
/// - registros excluidos logicamente (excluidoEm) nao entram.
int calcularSaldoCentavos(
  Iterable<Conta> contas,
  Iterable<Lancamento> lancamentos,
) {
  var saldo = 0;
  for (final c in contas) {
    if (c.excluidoEm == null) saldo += c.saldoInicialCentavos;
  }
  for (final l in lancamentos) {
    if (l.excluidoEm != null || l.status != 'pago') continue;
    if (l.tipo == 'receita') {
      saldo += l.valorCentavos;
    } else if (l.tipo == 'despesa') {
      saldo -= l.valorCentavos;
    }
  }
  return saldo;
}
