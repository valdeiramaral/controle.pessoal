import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/saude_calculo.dart';
import '../../data/local/banco.dart';
import 'medicamento_form_page.dart';

/// Aba Medicacao: doses de hoje (tomei / pular) e a lista dos medicamentos com posologia e estoque.
class MedicacaoAba extends ConsumerWidget {
  const MedicacaoAba({super.key, this.agora});
  final DateTime? agora; // para testes

  static String _chave(String medId, DateTime previsto) => '$medId|${previsto.millisecondsSinceEpoch ~/ 1000}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    final agora = this.agora ?? DateTime.now();
    return StreamBuilder<List<Medicamento>>(
      stream: banco.observarMedicamentos(),
      builder: (context, snapMed) => StreamBuilder<List<RegistroTomada>>(
        stream: banco.observarTomadasDoDia(agora),
        builder: (context, snapTom) {
          final meds = snapMed.data ?? const <Medicamento>[];
          final tomadas = {for (final t in snapTom.data ?? const <RegistroTomada>[]) _chave(t.medicamentoId, t.horarioPrevisto): t};
          final ativos = meds.where((m) => m.ativo).toList();
          final doses = <(Medicamento, DateTime)>[
            for (final m in ativos)
              for (final d in dosesDoDia(m, agora)) (m, d),
          ]..sort((a, b) => a.$2.compareTo(b.$2));
          final avulsos = ativos.where((m) => m.frequencia == 'necessario').toList();
          // Doses avulsas ja tomadas hoje (horario que nao e da programacao).
          final extras = [
            for (final t in snapTom.data ?? const <RegistroTomada>[])
              if (t.status == 'tomou' && !doses.any((d) => _chave(d.$1.id, d.$2) == _chave(t.medicamentoId, t.horarioPrevisto)))
                t,
          ];
          final porId = {for (final m in meds) m.id: m};

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              _titulo(context, 'Hoje · ${DateFormat("EEEE, dd/MM", 'pt_BR').format(agora)}'),
              if (doses.isEmpty && avulsos.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('Nenhuma dose programada para hoje.', key: Key('sem_doses_hoje')),
                ),
              for (final (m, previsto) in doses) _linhaDose(context, ref, m, previsto, tomadas[_chave(m.id, previsto)], agora),
              for (final t in extras)
                if (porId[t.medicamentoId] != null)
                  ListTile(
                    key: Key('dose_extra_${t.id}'),
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text('${porId[t.medicamentoId]!.nome} · dose extra'),
                    subtitle: Text('Tomou às ${DateFormat.Hm().format(t.horarioReal ?? t.horarioPrevisto)}'),
                  ),
              for (final m in avulsos)
                ListTile(
                  key: Key('avulso_${m.id}'),
                  leading: const Icon(Icons.medication_outlined),
                  title: Text('${m.nome} · quando necessário'),
                  subtitle: Text('${m.dose} · ${descricaoQuantidade(m.formato, m.quantidade)}'),
                  trailing: FilledButton.tonal(
                    key: Key('dose_avulsa_${m.id}'),
                    onPressed: () => _tomar(context, ref, m, null),
                    child: const Text('Registrar dose'),
                  ),
                ),
              const Divider(height: 24),
              _titulo(context, 'Meus medicamentos'),
              if (meds.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('Nenhum medicamento cadastrado. Toque em + para adicionar.', key: Key('sem_medicamentos')),
                ),
              for (final m in meds) _tileMedicamento(context, m),
            ],
          );
        },
      ),
    );
  }

  Widget _titulo(BuildContext context, String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _linhaDose(BuildContext context, WidgetRef ref, Medicamento m, DateTime previsto, RegistroTomada? t, DateTime agora) {
    final hora = DateFormat.Hm().format(previsto);
    final id = '${m.id}_${hora.replaceAll(':', '')}';
    final status = t?.status ?? 'pendente';
    final atrasada = status == 'pendente' && previsto.isBefore(agora);
    final subtitulo = '${m.dose} · ${descricaoQuantidade(m.formato, m.quantidade)}';
    if (status == 'tomou' || status == 'pulou') {
      final tomou = status == 'tomou';
      return ListTile(
        key: Key('dose_$id'),
        leading: Icon(tomou ? Icons.check_circle : Icons.remove_circle_outline, color: tomou ? Colors.green : Colors.grey),
        title: Text('$hora · ${m.nome}'),
        subtitle: Text(tomou
            ? '$subtitulo\nTomou às ${DateFormat.Hm().format(t!.horarioReal ?? previsto)}'
            : '$subtitulo\nPulou esta dose'),
        isThreeLine: true,
        trailing: IconButton(
          key: Key('desfazer_$id'),
          tooltip: 'Desfazer',
          icon: const Icon(Icons.undo),
          onPressed: () => ref.read(bancoProvider).registrarTomada(m, previsto, status: 'pendente'),
        ),
      );
    }
    return ListTile(
      key: Key('dose_$id'),
      leading: Icon(atrasada ? Icons.alarm : Icons.schedule, color: atrasada ? Theme.of(context).colorScheme.error : null),
      title: Text('$hora · ${m.nome}'),
      subtitle: Text(atrasada ? '$subtitulo\nAtrasada' : subtitulo),
      isThreeLine: atrasada,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('pular_$id'),
            tooltip: 'Pular',
            icon: const Icon(Icons.skip_next_outlined),
            onPressed: () => ref.read(bancoProvider).registrarTomada(m, previsto, status: 'pulou'),
          ),
          FilledButton(
            key: Key('tomar_$id'),
            onPressed: () => _tomar(context, ref, m, previsto),
            child: const Text('Tomei'),
          ),
        ],
      ),
    );
  }

  Future<void> _tomar(BuildContext context, WidgetRef ref, Medicamento m, DateTime? previsto) async {
    final banco = ref.read(bancoProvider);
    if (previsto == null) {
      await banco.registrarDoseAvulsa(m);
    } else {
      await banco.registrarTomada(m, previsto);
    }
    final atual = await banco.medicamentoPorId(m.id);
    if (atual != null && estoqueBaixo(atual) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        key: const Key('aviso_estoque_baixo'),
        content: Text('Estoque baixo de ${atual.nome}: restam ${atual.estoque}. Hora de reabastecer.'),
      ));
    }
  }

  Widget _tileMedicamento(BuildContext context, Medicamento m) {
    final baixo = estoqueBaixo(m);
    final dias = diasDeEstoque(m);
    final linhas = <String>[
      '${m.dose} · ${formatosMedicamento[m.formato] ?? m.formato}',
      if (m.ativo) resumoFrequencia(m) else 'Não estou tomando',
      if ((m.tratamento ?? '').isNotEmpty) 'Para: ${m.tratamento}',
    ];
    final cor = Theme.of(context).colorScheme;
    return ListTile(
      key: Key('med_${m.id}'),
      isThreeLine: true,
      leading: Icon(m.ativo ? Icons.medication_outlined : Icons.pause_circle_outline, color: m.ativo ? null : Colors.grey),
      title: Text(m.nome),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(linhas.join('\n')),
          if (m.estoque != null)
            Text(
              baixo
                  ? 'Estoque baixo: ${m.estoque} restantes'
                  : 'Estoque: ${m.estoque}${dias != null ? ' (≈ $dias dias)' : ''}',
              key: Key('estoque_${m.id}'),
              style: TextStyle(color: baixo ? cor.error : null, fontWeight: baixo ? FontWeight.w700 : null),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => abrirFormularioMedicamento(context, medicamento: m, hoje: agora),
    );
  }
}
