/// Regras puras do modulo Saude (sem Flutter): posologia, estoque e agendamentos periodicos.
import '../data/local/banco.dart';

// ----------------------------- Medicacao -----------------------------

const formatosMedicamento = <String, String>{
  'comprimido': 'Comprimido',
  'capsula': 'Cápsula',
  'liquido': 'Líquido',
  'gotas': 'Gotas',
  'injecao': 'Injeção',
  'pomada': 'Pomada/creme',
  'spray': 'Spray/inalador',
  'adesivo': 'Adesivo',
  'po': 'Pó/sachê',
  'outro': 'Outro',
};

const _unidades = <String, (String, String)>{
  'comprimido': ('comprimido', 'comprimidos'),
  'capsula': ('cápsula', 'cápsulas'),
  'liquido': ('medida', 'medidas'),
  'gotas': ('gota', 'gotas'),
  'injecao': ('aplicação', 'aplicações'),
  'pomada': ('aplicação', 'aplicações'),
  'spray': ('jato', 'jatos'),
  'adesivo': ('adesivo', 'adesivos'),
  'po': ('sachê', 'sachês'),
};

/// "1 comprimido", "2 cápsulas".
String descricaoQuantidade(String formato, int quantidade) {
  final u = _unidades[formato] ?? ('unidade', 'unidades');
  return '$quantidade ${quantidade == 1 ? u.$1 : u.$2}';
}

const frequenciasMedicamento = <String, String>{
  'diaria': 'Todos os dias',
  'dias_semana': 'Dias da semana',
  'intervalo': 'A cada N dias',
  'necessario': 'Somente quando necessário',
};

/// Indice 0 = segunda (weekday 1) ... 6 = domingo (weekday 7).
const nomesDiasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

const maximoHorarios = 12;

/// "08:00, 20:00" -> [(8, 0), (20, 0)]. Ignora itens invalidos, repetidos e ordena.
List<(int, int)> lerHorarios(String texto) {
  final saida = <(int, int)>{};
  for (final parte in texto.split(',')) {
    final p = parte.trim().split(':');
    if (p.length != 2) continue;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) continue;
    saida.add((h, m));
  }
  final lista = saida.toList()..sort((a, b) => (a.$1 * 60 + a.$2).compareTo(b.$1 * 60 + b.$2));
  return lista;
}

String formatarHorario((int, int) h) => '${h.$1.toString().padLeft(2, '0')}:${h.$2.toString().padLeft(2, '0')}';

String horariosParaTexto(List<(int, int)> horarios) => horarios.map(formatarHorario).join(',');

/// "1,3,5" -> [1, 3, 5] (1 = segunda ... 7 = domingo).
List<int> lerDiasSemana(String texto) {
  final dias = <int>{};
  for (final p in texto.split(',')) {
    final d = int.tryParse(p.trim());
    if (d != null && d >= 1 && d <= 7) dias.add(d);
  }
  return dias.toList()..sort();
}

DateTime soDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// O medicamento tem dose programada neste dia?
bool tomaNoDia(Medicamento m, DateTime dia) {
  if (!m.ativo) return false;
  final d = soDia(dia);
  if (d.isBefore(soDia(m.inicio))) return false;
  if (m.fim != null && d.isAfter(soDia(m.fim!))) return false;
  switch (m.frequencia) {
    case 'diaria':
      return true;
    case 'dias_semana':
      return lerDiasSemana(m.diasSemana).contains(d.weekday);
    case 'intervalo':
      final n = m.intervaloDias < 1 ? 1 : m.intervaloDias;
      final dias = DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(m.inicio.year, m.inicio.month, m.inicio.day)).inDays;
      return dias % n == 0;
    default:
      return false; // somente quando necessario
  }
}

/// Horarios previstos do dia (vazio se nao toma neste dia).
List<DateTime> dosesDoDia(Medicamento m, DateTime dia) {
  if (!tomaNoDia(m, dia)) return const [];
  final d = soDia(dia);
  return [for (final h in lerHorarios(m.horarios)) DateTime(d.year, d.month, d.day, h.$1, h.$2)];
}

/// "Todos os dias · 08:00, 20:00".
String resumoFrequencia(Medicamento m) {
  final horas = lerHorarios(m.horarios).map(formatarHorario).join(', ');
  switch (m.frequencia) {
    case 'dias_semana':
      final dias = lerDiasSemana(m.diasSemana).map((d) => nomesDiasSemana[d - 1]).join(', ');
      return '$dias · $horas';
    case 'intervalo':
      final n = m.intervaloDias;
      return '${n == 1 ? 'Todos os dias' : 'A cada $n dias'} · $horas';
    case 'necessario':
      return 'Somente quando necessário';
    default:
      return 'Todos os dias · $horas';
  }
}

/// Dias que o estoque atual ainda dura; null sem estoque informado ou sem consumo programado.
/// Conta em inteiros (sem double) para nao errar por arredondamento.
int? diasDeEstoque(Medicamento m) {
  final e = m.estoque;
  final porDia = lerHorarios(m.horarios).length * m.quantidade;
  if (e == null || porDia <= 0) return null;
  switch (m.frequencia) {
    case 'dias_semana':
      final n = lerDiasSemana(m.diasSemana).length;
      return n == 0 ? null : (e * 7) ~/ (porDia * n);
    case 'intervalo':
      return (e * (m.intervaloDias < 1 ? 1 : m.intervaloDias)) ~/ porDia;
    case 'necessario':
      return null;
    default:
      return e ~/ porDia;
  }
}

/// Estoque igual ou abaixo do minimo escolhido para o lembrete de reabastecer.
bool estoqueBaixo(Medicamento m) =>
    m.ativo && m.lembreteReabastecer && m.estoque != null && m.estoqueMinimo != null && m.estoque! <= m.estoqueMinimo!;

const tiposMedicamento = <String, String>{
  'referencia': 'Referência',
  'generico': 'Genérico',
  'similar': 'Similar',
};

/// Explicacao curta de cada classificacao (Anvisa).
const explicacaoTipoMedicamento = 'Referência: marca original, a que serviu de base para os demais. '
    'Genérico: mesmo princípio ativo, vendido pelo nome da substância, intercambiável com o de referência. '
    'Similar: mesmo princípio ativo, vendido com nome de marca própria.';

const diasAvisoValidade = 30;

/// 'vencido', 'vence_logo' (ate 30 dias) ou 'ok'; null sem validade informada.
String? situacaoValidade(Medicamento m, DateTime hoje) {
  final v = m.validade;
  if (v == null) return null;
  final dias = diasParaVencer(m, hoje)!;
  if (v.isBefore(soDia(hoje))) return 'vencido';
  return dias <= diasAvisoValidade ? 'vence_logo' : 'ok';
}

/// Dias de hoje ate a validade (negativo se ja venceu); null sem validade. A validade vale ate o fim do dia informado.
int? diasParaVencer(Medicamento m, DateTime hoje) {
  final v = m.validade;
  if (v == null) return null;
  return DateTime.utc(v.year, v.month, v.day).difference(DateTime.utc(hoje.year, hoje.month, hoje.day)).inDays;
}

// ----------------------------- Agendamentos -----------------------------

const tiposAgendamento = <String, String>{
  'consulta': 'Consulta',
  'exame': 'Exame',
  'retorno': 'Retorno',
  'vacina': 'Vacina',
  'outro': 'Outro',
};

const statusAgendamento = <String, String>{
  'agendado': 'Agendado',
  'realizado': 'Realizado',
  'cancelado': 'Cancelado',
  'faltou': 'Faltei',
};

/// Repeticoes prontas: nome -> (unidade, intervalo).
const repeticoesProntas = <String, (String, int)>{
  'semanal': ('semanas', 1),
  'quinzenal': ('semanas', 2),
  'mensal': ('meses', 1),
  'bimestral': ('meses', 2),
  'trimestral': ('meses', 3),
  'semestral': ('meses', 6),
  'anual': ('anos', 1),
};

const unidadesRepeticao = <String, String>{
  'dias': 'dia(s)',
  'semanas': 'semana(s)',
  'meses': 'mês(es)',
  'anos': 'ano(s)',
};

const maximoOcorrencias = 60;

/// Antecedencia do lembrete (minutos) -> texto. null = sem lembrete.
const antecedenciasLembrete = <int, String>{
  15: '15 minutos antes',
  30: '30 minutos antes',
  60: '1 hora antes',
  120: '2 horas antes',
  1440: '1 dia antes',
  2880: '2 dias antes',
};

DateTime _somarMesesComHora(DateTime d, int meses) {
  final total = d.year * 12 + (d.month - 1) + meses;
  final ano = total ~/ 12;
  final mes = total % 12 + 1;
  final ultimo = DateTime(ano, mes + 1, 0).day;
  return DateTime(ano, mes, d.day > ultimo ? ultimo : d.day, d.hour, d.minute);
}

/// [base] + [vezes] periodos de [intervalo] [unidade] (dias, semanas, meses ou anos), mantendo a hora.
/// Meses/anos nao estouram o fim do mes (31/01 + 1 mes = 28/02) e sao sempre contados a partir da data original.
DateTime somarPeriodo(DateTime base, String unidade, int intervalo, int vezes) {
  final n = intervalo * vezes;
  switch (unidade) {
    case 'dias':
      return DateTime(base.year, base.month, base.day + n, base.hour, base.minute);
    case 'semanas':
      return DateTime(base.year, base.month, base.day + 7 * n, base.hour, base.minute);
    case 'meses':
      return _somarMesesComHora(base, n);
    case 'anos':
      return _somarMesesComHora(base, 12 * n);
    default:
      throw ArgumentError('unidade invalida: $unidade');
  }
}

/// As [vezes] datas da serie (a primeira e o proprio [inicio]).
List<DateTime> ocorrenciasAgendamento(DateTime inicio, String unidade, int intervalo, int vezes) =>
    [for (var i = 0; i < vezes; i++) somarPeriodo(inicio, unidade, intervalo, i)];

/// "Mensal", "A cada 3 meses"... a partir de "meses:3" (como fica gravado).
String rotuloRepeticao(String? codigo) {
  if (codigo == null) return '';
  final p = codigo.split(':');
  if (p.length != 2) return '';
  final n = int.tryParse(p[1]) ?? 1;
  for (final e in repeticoesProntas.entries) {
    if (e.value.$1 == p[0] && e.value.$2 == n) return e.key[0].toUpperCase() + e.key.substring(1);
  }
  final un = {'dias': 'dia', 'semanas': 'semana', 'meses': 'mês', 'anos': 'ano'}[p[0]] ?? p[0];
  final plural = {'dias': 'dias', 'semanas': 'semanas', 'meses': 'meses', 'anos': 'anos'}[p[0]] ?? p[0];
  return n == 1 ? 'A cada $un' : 'A cada $n $plural';
}

/// Titulo do evento criado na Agenda: "Consulta: Cardiologista".
String tituloEventoSaude(String tipo, String titulo) => '${tiposAgendamento[tipo] ?? 'Saúde'}: $titulo';
