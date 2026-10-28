import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatos.dart';
import '../../core/lancamento_calculo.dart' show tagsDoTexto;
import '../../core/tarefas_calculo.dart';
import '../../data/local/banco.dart';
import 'tarefa_form_page.dart';

/// Lista das tarefas por dia (prazo), com busca, filtro de prioridade e tag colorida.
class TarefasAba extends ConsumerStatefulWidget {
  const TarefasAba({super.key, this.agora});

  final DateTime? agora; // para testes

  @override
  ConsumerState<TarefasAba> createState() => _TarefasAbaState();
}

class _TarefasAbaState extends ConsumerState<TarefasAba> {
  final _busca = TextEditingController();
  String _filtro = 'todas'; // todas | alta | media | baixa
  bool _concluidas = false;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  String _tituloDia(DateTime? dia, DateTime hoje) {
    if (dia == null) return 'Sem data';
    final diff = dia.difference(DateTime(hoje.year, hoje.month, hoje.day)).inDays;
    final txt = toBeginningOfSentenceCase(DateFormat("EEEE · dd/MM/yyyy", 'pt_BR').format(dia));
    return switch (diff) {
      0 => 'Hoje · ${formatarData(dia)}',
      1 => 'Amanhã · ${formatarData(dia)}',
      < 0 => 'Atrasadas · $txt',
      _ => txt,
    };
  }

  Future<void> _excluir(Banco banco, Tarefa t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir tarefa?'),
        content: Text('"${t.titulo}" será excluída.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('confirmar_exclusao_tarefa'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) await banco.excluirTarefa(t.id);
  }

  Widget _cartao(Banco banco, Tarefa t) {
    final concluida = t.etapa == 'concluida';
    final cor = corDaPrioridade(t.prioridade);
    final tema = Theme.of(context);
    final estimativa = descricaoEstimativa(t.estimativa, t.estimativaUnidade);
    final tags = tagsDoTexto(t.tags);
    final linhas = <String>[
      if ((t.projeto ?? '').isNotEmpty) t.projeto!,
      etapasTarefa[t.etapa] ?? t.etapa,
      if (estimativa != null) estimativa,
      if ((t.responsavel ?? '').isNotEmpty) t.responsavel!,
      if (tags.isNotEmpty) tags.map((x) => '#$x').join(' '),
    ];
    return Card(
      key: Key('tarefa_${t.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Container(
        // tag colorida na lateral: alta = vermelho, media = laranja, baixa = verde
        decoration: BoxDecoration(border: Border(left: BorderSide(color: cor, width: 5))),
        child: ListTile(
          key: Key('tarefa_item_${t.id}'),
          leading: IconButton(
            key: Key('concluir_${t.id}'),
            tooltip: concluida ? 'Reabrir' : 'Concluir',
            icon: Icon(concluida ? Icons.check_circle : Icons.radio_button_unchecked, color: concluida ? Colors.green : null),
            onPressed: () => banco.definirEtapaTarefa(t.id, concluida ? etapaPadraoTarefa : 'concluida'),
          ),
          title: Text(t.titulo,
              style: TextStyle(fontWeight: FontWeight.w600, decoration: concluida ? TextDecoration.lineThrough : null)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((t.descricao ?? '').isNotEmpty) Text(t.descricao!, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(linhas.join('  ·  '), style: tema.textTheme.bodySmall),
            const SizedBox(height: 4),
            Container(
              key: Key('prioridade_${t.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(10)),
              child: Text(prioridadesTarefa[t.prioridade] ?? t.prioridade,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              key: Key('editar_tarefa_${t.id}'),
              tooltip: 'Alterar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => abrirFormularioTarefa(context, tarefa: t),
            ),
            IconButton(
              key: Key('excluir_tarefa_${t.id}'),
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _excluir(banco, t),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final banco = ref.watch(bancoProvider);
    final hoje = widget.agora ?? DateTime.now();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: TextField(
          key: const Key('busca_tarefa'),
          controller: _busca,
          decoration: const InputDecoration(labelText: 'Buscar tarefas', prefixIcon: Icon(Icons.search)),
          onChanged: (_) => setState(() {}),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Wrap(spacing: 6, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final e in {'todas': 'Todas', ...prioridadesTarefa}.entries)
            ChoiceChip(
              key: Key('filtro_${e.key}'),
              label: Text(e.value),
              selected: _filtro == e.key,
              avatar: e.key == 'todas' ? null : Icon(Icons.circle, size: 12, color: corDaPrioridade(e.key)),
              onSelected: (_) => setState(() => _filtro = e.key),
            ),
          FilterChip(
            key: const Key('filtro_concluidas'),
            label: const Text('Concluídas'),
            selected: _concluidas,
            onSelected: (v) => setState(() => _concluidas = v),
          ),
        ]),
      ),
      Expanded(
        child: StreamBuilder<List<Tarefa>>(
          stream: banco.observarTarefas(),
          builder: (context, snap) {
            final busca = _busca.text.trim().toLowerCase();
            final todas = snap.data ?? const <Tarefa>[];
            final itens = todas.where((t) {
              if (!_concluidas && t.etapa == 'concluida') return false;
              if (_filtro != 'todas' && t.prioridade != _filtro) return false;
              if (busca.isEmpty) return true;
              return [t.titulo, t.descricao ?? '', t.projeto ?? '', t.tags, t.responsavel ?? '']
                  .any((x) => x.toLowerCase().contains(busca));
            }).toList();
            if (itens.isEmpty) {
              return Center(child: Text(todas.isEmpty ? 'Nenhuma tarefa ainda. Toque em + para cadastrar.' : 'Nenhuma tarefa com esse filtro.', key: const Key('sem_tarefas')));
            }
            final grupos = agruparTarefasPorDia(itens);
            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              for (final g in grupos) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: Text(_tituloDia(g.dia, hoje),
                      key: Key('dia_tarefas_${g.dia == null ? 'sem' : formatarData(g.dia!)}'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                for (final t in g.itens) _cartao(banco, t),
              ],
            ]);
          },
        ),
      ),
    ]);
  }
}
