import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notificacoes.dart';
import '../../data/local/banco.dart';

class SaudePage extends ConsumerWidget {
  const SaudePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saúde')),
      body: StreamBuilder<List<Medicamento>>(
        stream: banco.observarMedicamentos(),
        builder: (context, snap) {
          final itens = snap.data ?? const <Medicamento>[];
          if (itens.isEmpty) {
            return const Center(child: Text('Nenhum medicamento cadastrado.'));
          }
          return ListView.separated(
            itemCount: itens.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = itens[i];
              return Dismissible(
                key: ValueKey(m.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  _cancelarLembretes(m);
                  banco.excluirMedicamento(m.id);
                },
                child: ListTile(
                  leading: const Icon(Icons.medication),
                  title: Text('${m.nome} · ${m.dose}'),
                  subtitle: Text('Horários: ${m.horarios.replaceAll(',', ', ')}'),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _novoMedicamento(context, banco),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// "08:00, 20:00" -> [(8, 0), (20, 0)]; ignora itens invalidos.
  static List<(int, int)> _lerHorarios(String texto) {
    final saida = <(int, int)>[];
    for (final parte in texto.split(',')) {
      final p = parte.trim().split(':');
      if (p.length != 2) continue;
      final h = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) continue;
      saida.add((h, m));
    }
    return saida;
  }

  static void _cancelarLembretes(Medicamento m) {
    final horarios = _lerHorarios(m.horarios);
    for (var i = 0; i < horarios.length; i++) {
      ServicoNotificacoes.instancia
          .cancelar(ServicoNotificacoes.idNumerico(m.id, salto: i));
    }
  }

  Future<void> _novoMedicamento(BuildContext context, Banco banco) async {
    final nome = TextEditingController();
    final dose = TextEditingController();
    final horarios = TextEditingController(text: '08:00');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo medicamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nome,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: dose,
              decoration: const InputDecoration(labelText: 'Dose (ex.: 1 comprimido)'),
            ),
            TextField(
              controller: horarios,
              decoration: const InputDecoration(
                labelText: 'Horários (ex.: 08:00, 20:00)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final lista = _lerHorarios(horarios.text);
              if (nome.text.trim().isEmpty ||
                  dose.text.trim().isEmpty ||
                  lista.isEmpty) {
                return;
              }
              final texto = lista
                  .map((h) =>
                      '${h.$1.toString().padLeft(2, '0')}:${h.$2.toString().padLeft(2, '0')}')
                  .join(',');
              final id = await banco.inserirMedicamento(
                nome: nome.text.trim(),
                dose: dose.text.trim(),
                horarios: texto,
              );
              for (var i = 0; i < lista.length; i++) {
                await ServicoNotificacoes.instancia.agendarDiaria(
                  id: ServicoNotificacoes.idNumerico(id, salto: i),
                  titulo: 'Hora do remédio',
                  corpo: '${nome.text.trim()} · ${dose.text.trim()}',
                  hora: lista[i].$1,
                  minuto: lista[i].$2,
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
