import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nav/menu_lateral.dart';

import '../../core/calculos.dart';
import '../../core/formatos.dart';
import '../../data/local/banco.dart';

class FinancasPage extends ConsumerWidget {
  const FinancasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    return Scaffold(
      appBar: const BarraPagina(title: Text('Finanças')),
      body: StreamBuilder<List<Lancamento>>(
        stream: banco.observarLancamentos(),
        builder: (context, snap) {
          final itens = snap.data ?? const <Lancamento>[];
          if (itens.isEmpty) {
            return const Center(child: Text('Nenhum lançamento ainda.'));
          }
          return Column(
            children: [
              StreamBuilder<List<Conta>>(
                stream: banco.observarContas(),
                builder: (context, snapContas) {
                  final saldo = calcularSaldoCentavos(
                      snapContas.data ?? const <Conta>[], itens);
                  return ListTile(
                    title: const Text('Saldo (contas + lançamentos pagos)'),
                    trailing: Text(formatarCentavos(saldo),
                        style: Theme.of(context).textTheme.titleLarge),
                  );
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: itens.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final l = itens[i];
                    final receita = l.tipo == 'receita';
                    return Dismissible(
                      key: ValueKey(l.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      onDismissed: (_) => banco.excluirLancamento(l.id),
                      child: ListTile(
                        leading: Checkbox(
                          value: l.status == 'pago',
                          onChanged: (_) => banco.alternarPagamento(l),
                        ),
                        title: Text(l.descricao),
                        subtitle: Text(formatarData(l.dia)),
                        trailing: Text(
                          '${receita ? '+' : '-'} ${formatarCentavos(l.valorCentavos)}',
                          style: TextStyle(
                              color: receita ? Colors.green : Colors.red),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _novoLancamento(context, banco),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _novoLancamento(BuildContext context, Banco banco) async {
    final descricao = TextEditingController();
    final valor = TextEditingController();
    var tipo = 'despesa';
    var pago = true;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Novo lançamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descricao,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              TextField(
                controller: valor,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor (R\$)'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'despesa', label: Text('Despesa')),
                  ButtonSegment(value: 'receita', label: Text('Receita')),
                ],
                selected: {tipo},
                onSelectionChanged: (s) => setState(() => tipo = s.first),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Já pago/recebido'),
                value: pago,
                onChanged: (v) => setState(() => pago = v ?? true),
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
                final centavos = centavosDeTexto(valor.text);
                if (descricao.text.trim().isEmpty || centavos == null) return;
                await banco.inserirLancamento(
                  descricao: descricao.text.trim(),
                  valorCentavos: centavos,
                  tipo: tipo,
                  pago: pago,
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
