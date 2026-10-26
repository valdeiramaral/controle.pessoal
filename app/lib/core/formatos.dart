import 'package:intl/intl.dart';

final _moeda = NumberFormat.simpleCurrency(locale: 'pt_BR');
final _dataHora = DateFormat("dd/MM/yyyy HH:mm", 'pt_BR');
final _data = DateFormat('dd/MM/yyyy', 'pt_BR');

/// Valores em centavos (inteiro) evitam erro de arredondamento.
String formatarCentavos(int centavos) => _moeda.format(centavos / 100);
String formatarDataHora(DateTime d) => _dataHora.format(d);
String formatarData(DateTime d) => _data.format(d);

/// Converte texto digitado em centavos. Retorna null se invalido.
///
/// Aceita "12,50", "1.234,50", "12.50", "1.234", "R$ 5" e "0,5".
/// Regra do ponto sem virgula: se o texto for grupos de 3 digitos depois do
/// ponto ("1.234", "12.345.678") o ponto e separador de milhar (padrao
/// brasileiro: 1.234 = mil duzentos e trinta e quatro reais); caso contrario
/// ("12.50", "0.5") o ponto e decimal. Mais de 2 casas decimais = invalido.
/// Usa so inteiros (sem double), entao nao ha erro de arredondamento.
int? centavosDeTexto(String texto) {
  var t = texto.replaceAll('R\$', '').replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return null;
  String inteira;
  String decimal = '';
  if (t.contains(',')) {
    final partes = t.split(',');
    if (partes.length != 2) return null;
    inteira = partes[0].replaceAll('.', '');
    decimal = partes[1];
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    inteira = t.replaceAll('.', '');
  } else if (t.contains('.')) {
    final partes = t.split('.');
    if (partes.length != 2) return null;
    inteira = partes[0];
    decimal = partes[1];
  } else {
    inteira = t;
  }
  if (inteira.isEmpty && decimal.isEmpty) return null;
  if (inteira.isEmpty) inteira = '0';
  if (!RegExp(r'^\d+$').hasMatch(inteira)) return null;
  if (decimal.length > 2 || (decimal.isNotEmpty && !RegExp(r'^\d+$').hasMatch(decimal))) {
    return null;
  }
  final reais = int.tryParse(inteira);
  if (reais == null) return null;
  return reais * 100 + int.parse(decimal.padRight(2, '0'));
}
