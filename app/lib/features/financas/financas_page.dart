import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nav/menu_lateral.dart';

import '../../core/calculos.dart';
import '../../core/formatos.dart';
import '../../data/local/banco.dart';
import 'contas_page.dart';
import 'dashboard_page.dart';

class FinancasPage extends ConsumerWidget {
  const FinancasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: const BarraPagina(title: Text('Finanças')),
        body: Column(children: [
          const TabBar(tabs: [
            Tab(key: Key('aba_dashboard'), icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
            Tab(key: Key('aba_lancamentos'), icon: Icon(Icons.receipt_long_outlined), text: 'Lançamentos'),
            Tab(key: Key('aba_contas'), icon: Icon(Icons.account_balance_outlined), text: 'Contas'),
          ]),
          Expanded(
            child: TabBarView(children: [
              const DashboardFinancas(),
              _lista(context, banco),
              const ContasPage(),
            ]),
          ),
        ]),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _novoLancamento(context, banco),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _lista(BuildContext context, Banco banco) {
    return StreamBuilder<List<Lancamento>>(
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
    );
  }

  Future<void> _novoLancamento(BuildContext context, Banco banco) async {
    final descricao = TextEditingController();
    final valor = TextEditingController();
    final parcelas = TextEditingController(text: '2');
    var tipo = 'despesa';
    var pago = true;
    var repeticao = 'variavel'; // variavel | fixa | parcelada
    final contas = (await (banco.select(banco.contas)..where((c) => c.excluidoEm.isNull())).get())
        .where((c) => c.titularidade != 'externa')
        .toList();
    final categorias = await (banco.select(banco.categorias)..where((c) => c.excluidoEm.isNull())).get();
    String? contaId = contas.isEmpty ? null : contas.first.id;
    String? categoriaId;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final cats = categorias.where((c) => c.tipo == tipo).toList();
          if (categoriaId != null && !cats.any((c) => c.id == categoriaId)) categoriaId = null;
          return AlertDialog(
            title: const Text('Novo lançamento'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descricao,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                  ),
                  TextField(
                    controller: valor,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: repeticao == 'parcelada' ? 'Valor de cada parcela (R\$)' : 'Valor (R\$)'),
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
                  if (contas.length > 1)
                    DropdownButtonFormField<String>(
                      value: contaId,
                      decoration: const InputDecoration(labelText: 'Conta'),
                      items: [for (final c in contas) DropdownMenuItem(value: c.id, child: Text(tituloDaConta(c) == c.nome ? c.nome : '${tituloDaConta(c)} · ${c.nome}'))],
                      onChanged: (v) => setState(() => contaId = v),
                    ),
                  if (cats.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      value: categoriaId,
                      decoration: const InputDecoration(labelText: 'Categoria'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Sem categoria')),
                        for (final c in cats) DropdownMenuItem<String?>(value: c.id, child: Text(c.nome)),
                      ],
                      onChanged: (v) => setState(() => categoriaId = v),
                    ),
                  DropdownButtonFormField<String>(
                    value: repeticao,
                    decoration: const InputDecoration(labelText: 'Recorrência'),
                    items: const [
                      DropdownMenuItem(value: 'variavel', child: Text('Variável (única)')),
                      DropdownMenuItem(value: 'fixa', child: Text('Fixa (todo mês)')),
                      DropdownMenuItem(value: 'parcelada', child: Text('Parcelada')),
                    ],
                    onChanged: (v) => setState(() => repeticao = v ?? repeticao),
                  ),
                  if (repeticao == 'parcelada')
                    TextField(
                      controller: parcelas,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Número de parcelas'),
                    ),
                  if (repeticao != 'parcelada')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Já pago/recebido'),
                      value: pago,
                      onChanged: (v) => setState(() => pago = v ?? true),
                    ),
                ],
              ),
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
                  if (repeticao == 'parcelada') {
                    final n = int.tryParse(parcelas.text.trim());
                    if (n == null || n < 2 || n > 120) return;
                    await banco.inserirParcelado(
                      descricao: descricao.text.trim(),
                      valorParcelaCentavos: centavos,
                      tipo: tipo,
                      parcelas: n,
                      primeiroDia: DateTime.now(),
                      contaId: contaId,
                      categoriaId: categoriaId,
                    );
                  } else {
                    await banco.inserirLancamento(
                      descricao: descricao.text.trim(),
                      valorCentavos: centavos,
                      tipo: tipo,
                      pago: pago,
                      contaId: contaId,
                      categoriaId: categoriaId,
                      recorrencia: repeticao == 'fixa' ? 'FREQ=MONTHLY' : null,
                    );
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }
}
