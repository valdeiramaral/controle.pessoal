/// Regras puras das tarefas (sem Flutter): prioridades, etapas, estimativa e agrupamento por dia.
import 'package:flutter/painting.dart' show Color;

import '../data/local/banco.dart';

/// Prioridade: o sistema usa "media" por padrao; cada uma tem uma tag colorida.
const prioridadesTarefa = <String, String>{'alta': 'Alta', 'media': 'Média', 'baixa': 'Baixa'};
const prioridadePadraoTarefa = 'media';

/// Alta = vermelho, media = laranja, baixa = verde.
Color corDaPrioridade(String prioridade) => switch (prioridade) {
      'alta' => const Color(0xFFD32F2F),
      'baixa' => const Color(0xFF388E3C),
      _ => const Color(0xFFF57C00),
    };

const etapasTarefa = <String, String>{
  'a_fazer': 'A fazer',
  'em_andamento': 'Em andamento',
  'aguardando': 'Aguardando',
  'concluida': 'Concluída',
};
const etapaPadraoTarefa = 'a_fazer';

const unidadesEstimativa = <String, String>{'minutos': 'minutos', 'horas': 'horas', 'dias': 'dias'};

/// "30 min", "2 h", "1 dia", "3 dias"; sem estimativa = null.
String? descricaoEstimativa(int? n, String unidade) {
  if (n == null || n < 1) return null;
  return switch (unidade) {
    'horas' => '$n h',
    'dias' => '$n ${n == 1 ? 'dia' : 'dias'}',
    _ => '$n min',
  };
}

/// Tarefas de um mesmo dia de prazo (dia null = sem data), em ordem crescente.
class GrupoDiaTarefas {
  const GrupoDiaTarefas(this.dia, this.itens);
  final DateTime? dia;
  final List<Tarefa> itens;
}

const _pesoPrioridade = {'alta': 0, 'media': 1, 'baixa': 2};

/// Agrupa por dia do prazo (do mais antigo ao mais novo; "sem data" por ultimo). No dia: prioridade alta primeiro, depois o nome.
List<GrupoDiaTarefas> agruparTarefasPorDia(List<Tarefa> tarefas) {
  DateTime? soDia(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day);
  final mapa = <DateTime?, List<Tarefa>>{};
  for (final t in tarefas) {
    mapa.putIfAbsent(soDia(t.prazo), () => []).add(t);
  }
  final dias = mapa.keys.toList()
    ..sort((a, b) => a == null ? (b == null ? 0 : 1) : (b == null ? -1 : a.compareTo(b)));
  return [
    for (final d in dias)
      GrupoDiaTarefas(
          d,
          mapa[d]!
            ..sort((a, b) {
              final p = (_pesoPrioridade[a.prioridade] ?? 1).compareTo(_pesoPrioridade[b.prioridade] ?? 1);
              return p != 0 ? p : a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
            })),
  ];
}

/// Segunda-feira da semana de [d] (a semana do quadro vai de segunda a domingo).
DateTime inicioDaSemana(DateTime d) {
  final dia = DateTime(d.year, d.month, d.day);
  return DateTime(dia.year, dia.month, dia.day - (dia.weekday - DateTime.monday));
}

/// Cores do quadro: tarefas em verde e compromissos em azul.
const corTarefaQuadro = Color(0xFF2E9E5B);
const corCompromissoQuadro = Color(0xFF2F6FDE);

/// Lembrete do compromisso: minutos antes do inicio (0 = sem lembrete).
const lembretesCompromisso = <int, String>{
  0: 'Sem lembrete',
  5: '5 minutos antes',
  15: '15 minutos antes',
  30: '30 minutos antes',
  60: '1 hora antes',
  1440: '1 dia antes',
};
