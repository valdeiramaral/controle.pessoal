/// Calculos puros do lancamento de despesas/receitas (sem Flutter, faceis de testar).
import '../data/local/banco.dart';

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

/// Lancamentos de um mes (aba Lancamentos): em ordem crescente de data, com os totais de receitas e despesas.
class GrupoMes {
  const GrupoMes(this.ano, this.mes, this.itens, this.receitasCentavos, this.despesasCentavos);
  final int ano;
  final int mes;
  final List<Lancamento> itens;
  final int receitasCentavos;
  final int despesasCentavos;

  /// Receitas menos despesas do mes.
  int get saldoCentavos => receitasCentavos - despesasCentavos;
}

/// Agrupa por mes da data do lancamento, do mais antigo para o mais recente; dentro do mes, por data crescente.
List<GrupoMes> agruparPorMes(List<Lancamento> lancamentos) {
  final ordenados = [...lancamentos]..sort((a, b) {
      final c = a.dia.compareTo(b.dia);
      return c != 0 ? c : a.descricao.toLowerCase().compareTo(b.descricao.toLowerCase());
    });
  final grupos = <GrupoMes>[];
  var atual = <Lancamento>[];
  void fechar() {
    if (atual.isEmpty) return;
    var rec = 0, desp = 0;
    for (final l in atual) {
      if (l.tipo == 'receita') {
        rec += l.valorCentavos;
      } else {
        desp += l.valorCentavos;
      }
    }
    grupos.add(GrupoMes(atual.first.dia.year, atual.first.dia.month, atual, rec, desp));
    atual = <Lancamento>[];
  }

  for (final l in ordenados) {
    if (atual.isNotEmpty && (atual.first.dia.year != l.dia.year || atual.first.dia.month != l.dia.month)) fechar();
    atual.add(l);
  }
  fechar();
  return grupos;
}
