import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatos.dart';
import '../../core/saude_calculo.dart';
import '../../data/local/banco.dart';
import 'agendamento_detalhe_page.dart';

/// Aba Consultas e exames: proximos agendamentos e historico, com filtro por tipo.
class AgendamentosAba extends ConsumerStatefulWidget {
  const AgendamentosAba({super.key, this.agora});
  final DateTime? agora; // para testes

  @override
  ConsumerState<AgendamentosAba> createState() => _AgendamentosAbaState();
}

class _AgendamentosAbaState extends ConsumerState<AgendamentosAba> {
  String _filtro = 'todos'; // todos | consultas | exames | outros

  static const _filtros = {
    'todos': 'Todos',
    'consultas': 'Consultas',
    'exames': 'Exames',
    'outros': 'Vacinas e outros',
  };

  bool _casa(AgendamentoSaude a) => switch (_filtro) {
        'consultas' => a.tipo == 'consulta' || a.tipo == 'retorno',
        'exames' => a.tipo == 'exame',
        'outros' => a.tipo == 'vacina' || a.tipo == 'outro',
        _ => true,
      };

  static IconData _icone(String tipo) => switch (tipo) {
        'exame' => Icons.biotech_outlined,
        'vacina' => Icons.vaccines_outlined,
        'retorno' => Icons.replay,
        'outro' => Icons.event_note_outlined,
        _ => Icons.medical_services_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final banco = ref.watch(bancoProvider);
    final agora = widget.agora ?? DateTime.now();
    final hoje = soDia(agora);
    return StreamBuilder<List<AgendamentoSaude>>(
      stream: banco.observarAgendamentos(),
      builder: (context, snap) {
        final todos = (snap.data ?? const <AgendamentoSaude>[]).where(_casa).toList();
        final proximos = todos.where((a) => a.status == 'agendado' && !a.dataHora.isBefore(hoje)).toList();
        final historico = todos.where((a) => !(a.status == 'agendado' && !a.dataHora.isBefore(hoje))).toList()
          ..sort((a, b) => b.dataHora.compareTo(a.dataHora));
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final e in _filtros.entries)
                    ChoiceChip(
                      key: Key('filtro_ag_${e.key}'),
                      label: Text(e.value),
                      selected: _filtro == e.key,
                      onSelected: (_) => setState(() => _filtro = e.key),
                    ),
                ],
              ),
            ),
            _titulo(context, 'Próximos (${proximos.length})'),
            if (proximos.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text('Nenhum agendamento à frente. Toque em + para marcar uma consulta ou exame.', key: Key('sem_agendamentos')),
              ),
            for (final a in proximos) _tile(context, a, agora),
            if (historico.isNotEmpty) ...[
              _titulo(context, 'Histórico (${historico.length})'),
              for (final a in historico) _tile(context, a, agora),
            ],
          ],
        );
      },
    );
  }

  Widget _titulo(BuildContext context, String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _tile(BuildContext context, AgendamentoSaude a, DateTime agora) {
    final quando = '${DateFormat("EEE, dd/MM/yyyy HH:mm", 'pt_BR').format(a.dataHora)}';
    final detalhes = [
      if ((a.especialidade ?? '').isNotEmpty) a.especialidade!,
      if ((a.profissional ?? '').isNotEmpty) a.profissional!,
      if ((a.local ?? '').isNotEmpty) a.local!,
    ];
    final semBaixa = a.status == 'agendado' && a.dataHora.isBefore(soDia(agora));
    final cor = Theme.of(context).colorScheme;
    return ListTile(
      key: Key('agendamento_${a.id}'),
      isThreeLine: detalhes.isNotEmpty,
      leading: Icon(_icone(a.tipo)),
      title: Text(a.titulo),
      subtitle: Text([quando, if (detalhes.isNotEmpty) detalhes.join(' · ')].join('\n')),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (a.serieNumero != null)
            Text('${a.serieNumero}/${a.serieTotal}', key: Key('serie_${a.id}'), style: Theme.of(context).textTheme.labelSmall),
          if (a.status != 'agendado')
            Text(statusAgendamento[a.status] ?? a.status, style: Theme.of(context).textTheme.labelSmall)
          else if (semBaixa)
            Text('Sem baixa', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cor.error)),
        ],
      ),
      onTap: () => abrirDetalheAgendamento(context, a.id),
    );
  }
}
