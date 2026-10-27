import '../data/local/banco.dart';

/// Formas de pagamento/recebimento (codigo gravado -> nome na tela).
const formasPagamento = <String, String>{
  'dinheiro': 'Dinheiro',
  'pix': 'PIX',
  'transferencia': 'Transferência (TED/DOC)',
  'boleto': 'Boleto',
  'debito': 'Cartão de débito',
  'credito': 'Cartão de crédito',
  'debito_automatico': 'Débito automático',
  'cheque': 'Cheque',
  'outro': 'Outro',
};

String nomeDaForma(String? codigo) => formasPagamento[codigo] ?? (codigo ?? '—');

/// Tipo do pagamento: total quita o lancamento; parcial registra uma parte e ele continua em aberto.
const tiposPagamento = <String, String>{'total': 'Total', 'parcial': 'Parcial'};

/// Dados de um pagamento (despesa) ou recebimento (receita) a registrar.
class DadosPagamento {
  const DadosPagamento({
    required this.data,
    required this.forma,
    required this.contaId,
    required this.tipo,
    required this.valorPagoCentavos,
    this.descontoCentavos = 0,
  });
  final DateTime data;
  final String forma;
  final String contaId;
  final String tipo; // total | parcial
  final int valorPagoCentavos;
  final int descontoCentavos;

  bool get quita => tipo == 'total';
}

/// Valor que realmente moveu o caixa: o valor pago, se foi registrado; senao o valor do lancamento.
/// So vale para lancamentos pagos; os demais usam o valor previsto.
int valorEfetivo(Lancamento l) => l.status == 'pago' ? (l.valorPagoCentavos ?? l.valorCentavos) : l.valorCentavos;

/// Conta de onde saiu/entrou o dinheiro: a conta do pagamento, se informada (so quando pago).
String contaEfetiva(Lancamento l) => l.status == 'pago' ? (l.contaPagamentoId ?? l.contaId) : l.contaId;

/// Quanto ainda falta pagar/receber de um lancamento em aberto com pagamento parcial.
int restanteCentavos(Lancamento l) {
  if (l.status == 'pago') return 0;
  return (l.valorCentavos - (l.valorPagoCentavos ?? 0) - (l.descontoCentavos ?? 0)).clamp(0, l.valorCentavos);
}
