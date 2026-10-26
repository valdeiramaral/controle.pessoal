import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatos.dart';
import '../../data/local/banco.dart';
import '../auth/conta_sheet.dart';

/// Painel unificado: compromissos do dia, contas a vencer e remedios.
class HojePage extends ConsumerWidget {
  const HojePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    final hoje = DateTime.now();
    final em7dias = hoje.add(const Duration(days: 7));

    return Scaffold(
      appBar: AppBar(
        title: Text('Hoje · ${formatarData(hoje)}'),
        actions: [
          IconButton(
            tooltip: 'Conta',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => mostrarConta(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Secao(
            titulo: 'Compromissos',
            icone: Icons.event,
            filho: StreamBuilder<List<Evento>>(
              stream: banco.observarEventosDoDia(hoje),
              builder: (context, snap) {
                final itens = snap.data ?? const <Evento>[];
                if (itens.isEmpty) return const Text('Nada agendado para hoje.');
                return Column(
                  children: [
                    for (final e in itens)
                      ListTile(
                        dense: true,
                        title: Text(e.titulo),
                        trailing: Text(formatarDataHora(e.inicio).substring(11)),
                      ),
                  ],
                );
              },
            ),
          ),
          _Secao(
            titulo: 'Contas a pagar (7 dias)',
            icone: Icons.receipt_long,
            filho: StreamBuilder<List<Lancamento>>(
              stream: banco.observarContasPendentes(ate: em7dias),
              builder: (context, snap) {
                final itens = (snap.data ?? const <Lancamento>[])
                    .where((l) => l.tipo == 'despesa')
                    .toList();
                if (itens.isEmpty) return const Text('Nenhuma conta pendente.');
                return Column(
                  children: [
                    for (final l in itens)
                      ListTile(
                        dense: true,
                        title: Text(l.descricao),
                        subtitle: Text(formatarData(l.dia)),
                        trailing: Text(formatarCentavos(l.valorCentavos)),
                      ),
                  ],
                );
              },
            ),
          ),
          _Secao(
            titulo: 'Remédios',
            icone: Icons.medication,
            filho: StreamBuilder<List<Medicamento>>(
              stream: banco.observarMedicamentos(),
              builder: (context, snap) {
                final itens = snap.data ?? const <Medicamento>[];
                if (itens.isEmpty) return const Text('Nenhum medicamento cadastrado.');
                return Column(
                  children: [
                    for (final m in itens)
                      ListTile(
                        dense: true,
                        title: Text('${m.nome} · ${m.dose}'),
                        trailing: Text(m.horarios.replaceAll(',', ' ')),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.icone, required this.filho});

  final String titulo;
  final IconData icone;
  final Widget filho;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icone),
              const SizedBox(width: 8),
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            filho,
          ],
        ),
      ),
    );
  }
}
