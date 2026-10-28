import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nav/menu_lateral.dart';

import '../../core/tarefas_calculo.dart';
import 'compromisso_form_page.dart';
import 'quadro_aba.dart';
import 'tarefa_form_page.dart';

/// Modulo de tarefas e compromissos: so o quadro da semana (tarefas em verde, compromissos em azul).
/// O "+" de cada dia e o botao geral cadastram tarefa ou compromisso.
class AgendaPage extends ConsumerWidget {
  const AgendaPage({super.key, this.titulo = 'Agenda'});

  /// Nome do modulo como esta no cadastro de modulos.
  final String titulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: BarraPagina(title: Text(titulo)),
      body: const QuadroAba(),
      floatingActionButton: FloatingActionButton(
        key: const Key('fab_novo_quadro'),
        tooltip: 'Nova tarefa ou compromisso',
        onPressed: () async {
          final r = await showModalBottomSheet<String>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  key: const Key('fab_nova_tarefa'),
                  leading: const Icon(Icons.task_alt_outlined, color: corTarefaQuadro),
                  title: const Text('Nova tarefa'),
                  onTap: () => Navigator.pop(ctx, 'tarefa'),
                ),
                ListTile(
                  key: const Key('fab_novo_compromisso'),
                  leading: const Icon(Icons.event_outlined, color: corCompromissoQuadro),
                  title: const Text('Novo compromisso'),
                  onTap: () => Navigator.pop(ctx, 'compromisso'),
                ),
              ]),
            ),
          );
          if (!context.mounted || r == null) return;
          if (r == 'tarefa') {
            await abrirFormularioTarefa(context);
          } else {
            await abrirFormularioCompromisso(context);
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
