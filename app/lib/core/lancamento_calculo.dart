/// Calculos puros do lancamento de despesas/receitas (sem Flutter, faceis de testar).

/// Divide [totalCentavos] em [parcelas] valores inteiros que SOMAM exatamente o total.
/// A sobra (centavos que nao dividem igualmente) vai uma a uma para as primeiras parcelas.
/// Ex.: 100,00 em 3 -> 33,34 + 33,33 + 33,33.
List<int> dividirParcelas(int totalCentavos, int parcelas) {
  if (parcelas < 1) throw ArgumentError('parcelas deve ser >= 1');
  final base = totalCentavos ~/ parcelas;
  final sobra = totalCentavos - base * parcelas;
  return [for (var i = 0; i < parcelas; i++) base + (i < sobra ? 1 : 0)];
}

/// Soma [meses] a [data] mantendo o dia, mas sem estourar o fim do mes
/// (31/01 + 1 mes = 28/02, nao 03/03).
DateTime adicionarMeses(DateTime data, int meses) {
  final total = data.year * 12 + (data.month - 1) + meses;
  final ano = total ~/ 12;
  final mes = total % 12 + 1;
  final ultimoDia = DateTime(ano, mes + 1, 0).day;
  return DateTime(ano, mes, data.day > ultimoDia ? ultimoDia : data.day);
}

const maximoTags = 10;
const maximoCaracteresTag = 30;

/// Normaliza uma tag digitada: sem espacos nas pontas, sem virgulas, minuscula, ate 30 letras.
/// Devolve '' se nao sobrar nada.
String normalizarTag(String texto) {
  var t = texto.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  if (t.startsWith('#')) t = t.substring(1).trim();
  return t.length > maximoCaracteresTag ? t.substring(0, maximoCaracteresTag) : t;
}

/// Tags gravadas no lancamento (texto separado por virgula) -> lista.
List<String> tagsDoTexto(String texto) =>
    texto.split(',').map(normalizarTag).where((t) => t.isNotEmpty).toList();

/// Lista de tags -> texto gravado (sem repetidas, no maximo [maximoTags]).
String tagsParaTexto(Iterable<String> tags) {
  final vistas = <String>{};
  for (final t in tags.map(normalizarTag)) {
    if (t.isNotEmpty && vistas.length < maximoTags) vistas.add(t);
  }
  return vistas.join(',');
}

const maximoAnexos = 10;
const maximoBytesAnexo = 5 * 1024 * 1024; // 5 MB por arquivo

String formatarTamanho(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}
