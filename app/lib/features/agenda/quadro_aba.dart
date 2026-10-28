import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatos.dart';
import '../../core/tarefas_calculo.dart';
import '../../data/local/banco.dart';
import 'compromisso_form_page.dart';
import 'concluir_dialogo.dart';
import 'tarefa_form_page.dart';

/// Quadro da semana (segunda a domingo): uma coluna por dia com as tarefas (verde) e os compromissos (azul).
class QuadroAba extends ConsumerStatefulWidget {
  const QuadroAba({super.key, this.agora});

  final DateTime? agora; // para testes

  @override
  ConsumerState<QuadroAba> createState() => _QuadroAbaState();
}

class _QuadroAbaState extends ConsumerState<QuadroAba> {
  late DateTime _semana = inicioDaSemana(widget.agora ?? DateTime.now());

  DateTime get _hoje {
    final a = widget.agora ?? DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  DateTime _dia(int i) => DateTime(_semana.year, _semana.month, _semana.day + i);

  static DateTime _so(DateTime d) => DateTime(d.year, d.month, d.day);

  Widget _legenda(Color cor, String texto) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(texto),
      ]);

  /// Concluir pede observacoes e comentarios; reabrir e direto.
  Future<void> _concluirTarefa(Banco banco, Tarefa t) async {
    if (t.etapa == 'concluida') {
      await banco.definirEtapaTarefa(t.id, etapaPadraoTarefa);
      return;
    }
    final d = await pedirDadosDeConclusao(context, titulo: t.titulo, observacoes: t.observacoes, comentarios: t.comentarios);
    if (d == null) return;
    await banco.concluirTarefa(t.id, observacoes: d.observacoes, comentarios: d.comentarios);
  }

  Future<void> _concluirCompromisso(Banco banco, Evento e) async {
    if (e.status == 'realizado') {
      await banco.reabrirCompromisso(e.id);
      return;
    }
    final d = await pedirDadosDeConclusao(context, titulo: e.titulo, observacoes: e.observacoes, comentarios: e.comentarios);
    if (d == null) return;
    await banco.concluirCompromisso(e.id, observacoes: d.observacoes, comentarios: d.comentarios);
  }

  /// O "+" do dia (ou do botao geral): escolhe entre tarefa e compromisso, ja na data.
  Future<void> _novoNoDia(DateTime dia) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('novo_tarefa'),
            leading: const Icon(Icons.task_alt_outlined, color: corTarefaQuadro),
            title: const Text('Nova tarefa'),
            onTap: () => Navigator.pop(ctx, 'tarefa'),
          ),
          ListTile(
            key: const Key('novo_compromisso'),
            leading: const Icon(Icons.event_outlined, color: corCompromissoQuadro),
            title: const Text('Novo compromisso'),
            onTap: () => Navigator.pop(ctx, 'compromisso'),
          ),
        ]),
      ),
    );
    if (!mounted || r == null) return;
    if (r == 'tarefa') {
      await abrirFormularioTarefa(context, prazoInicial: dia, hoje: widget.agora);
    } else {
      await abrirFormularioCompromisso(context, dataInicial: dia, hoje: widget.agora);
    }
  }

  Widget _cartaoTarefa(Banco banco, Tarefa t) {
    final concluida = t.etapa == 'concluida';
    final estimativa = descricaoEstimativa(t.estimativa, t.estimativaUnidade);
    return Card(
      key: Key('quadro_tarefa_${t.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: corTarefaQuadro.withValues(alpha: concluida ? 0.06 : 0.14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => abrirFormularioTarefa(context, tarefa: t),
        child: Container(
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: corTarefaQuadro, width: 5))),
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.titulo,
                    style: TextStyle(fontWeight: FontWeight.w600, decoration: concluida ? TextDecoration.lineThrough : null)),
                Text(
                  [
                    if ((t.projeto ?? '').isNotEmpty) t.projeto!,
                    etapasTarefa[t.etapa] ?? t.etapa,
                    if (estimativa != null) estimativa,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  decoration: BoxDecoration(color: corDaPrioridade(t.prioridade), borderRadius: BorderRadius.circular(8)),
                  child: Text(prioridadesTarefa[t.prioridade] ?? t.prioridade,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            IconButton(
              key: Key('quadro_concluir_${t.id}'),
              visualDensity: VisualDensity.compact,
              tooltip: concluida ? 'Reabrir' : 'Concluir',
              icon: Icon(concluida ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: corTarefaQuadro),
              onPressed: () => _concluirTarefa(banco, t),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cartaoCompromisso(Banco banco, Evento e) {
    final realizado = e.status == 'realizado';
    return Card(
      key: Key('quadro_evento_${e.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: corCompromissoQuadro.withValues(alpha: realizado ? 0.06 : 0.14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => abrirFormularioCompromisso(context, evento: e, hoje: widget.agora),
        child: Container(
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: corCompromissoQuadro, width: 5))),
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.titulo,
                    style: TextStyle(fontWeight: FontWeight.w600, decoration: realizado ? TextDecoration.lineThrough : null)),
                Text(
                  [
                    e.diaInteiro ? 'Dia inteiro' : DateFormat('HH:mm').format(e.inicio),
                    if ((e.local ?? '').isNotEmpty) e.local!,
                    if ((e.projeto ?? '').isNotEmpty) e.projeto!,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  decoration: BoxDecoration(color: corDaPrioridade(e.prioridade), borderRadius: BorderRadius.circular(8)),
                  child: Text(prioridadesTarefa[e.prioridade] ?? e.prioridade,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            IconButton(
              key: Key('quadro_concluir_evento_${e.id}'),
              visualDensity: VisualDensity.compact,
              tooltip: realizado ? 'Reabrir' : 'Concluir',
              icon: Icon(realizado ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: corCompromissoQuadro),
              onPressed: () => _concluirCompromisso(banco, e),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _coluna(int i, List<Tarefa> tarefas, List<Evento> eventos) {
    final dia = _dia(i);
    final hoje = dia == _hoje;
    final tema = Theme.of(context);
    final nome = toBeginningOfSentenceCase(DateFormat('EEEE', 'pt_BR').format(dia));
    final tarefasDoDia = tarefas.where((t) => t.prazo != null && _so(t.prazo!) == dia).toList();
    final ordenadas = [...agruparTarefasPorDia(tarefasDoDia).expand((g) => g.itens)];
    final eventosDoDia = eventos.where((e) => _so(e.inicio) == dia).toList();
    final banco = ref.read(bancoProvider);
    return Container(
      key: Key('quadro_dia_$i'),
      width: 230,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: hoje ? tema.colorScheme.primary.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(nome,
                key: Key('quadro_titulo_dia_$i'),
                style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: hoje ? tema.colorScheme.primary : null)),
          ),
          IconButton(
            key: Key('quadro_novo_$i'),
            visualDensity: VisualDensity.compact,
            tooltip: 'Nova tarefa ou compromisso neste dia',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _novoNoDia(dia),
          ),
        ]),
        Text(formatarData(dia), style: tema.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final e in eventosDoDia) _cartaoCompromisso(banco, e),
        for (final t in ordenadas) _cartaoTarefa(banco, t),
        if (eventosDoDia.isEmpty && ordenadas.isEmpty)
          Text('Nada neste dia', style: tema.textTheme.bodySmall?.copyWith(color: tema.hintColor)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final banco = ref.watch(bancoProvider);
    final fim = _dia(6);
    final tema = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(children: [
          IconButton(
            key: const Key('quadro_anterior'),
            tooltip: 'Semana anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _semana = _dia(-7)),
          ),
          Expanded(
            child: Text('${formatarData(_semana)} a ${formatarData(fim)}',
                key: const Key('quadro_periodo'), textAlign: TextAlign.center, style: tema.textTheme.titleSmall),
          ),
          IconButton(
            key: const Key('quadro_proxima'),
            tooltip: 'Próxima semana',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _semana = _dia(7)),
          ),
          TextButton(
            key: const Key('quadro_hoje'),
            onPressed: () => setState(() => _semana = inicioDaSemana(widget.agora ?? DateTime.now())),
            child: const Text('Hoje'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(spacing: 16, children: [
          _legenda(corTarefaQuadro, 'Tarefas'),
          _legenda(corCompromissoQuadro, 'Compromissos'),
        ]),
      ),
      Expanded(
        child: StreamBuilder<List<Tarefa>>(
          stream: banco.observarTarefas(),
          builder: (context, snapTarefas) => StreamBuilder<List<Evento>>(
            stream: banco.observarEventosEntre(_semana, fim),
            builder: (context, snapEventos) {
              final tarefas = snapTarefas.data ?? const <Tarefa>[];
              final eventos = snapEventos.data ?? const <Evento>[];
              return SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var i = 0; i < 7; i++) _coluna(i, tarefas, eventos),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
