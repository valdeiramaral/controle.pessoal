import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nav/menu_lateral.dart';

import '../../core/calculos.dart';
import '../../core/formatos.dart';
import '../../core/lancamento_calculo.dart';
import '../../data/local/banco.dart';
import 'contas_page.dart';
import 'dashboard_page.dart';
import 'lancamento_detalhe_page.dart';
import 'lancamento_form_page.dart';

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
          onPressed: () => abrirFormularioLancamento(context),
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
                      onDismissed: (_) => banco.excluirLancamentoDaSerie(l),
                      child: ListTile(
                        key: Key('lancamento_${l.id}'),
                        onTap: () => abrirDetalheLancamento(context, l.id),
                        leading: Checkbox(
                          value: l.status == 'pago',
                          onChanged: (_) => banco.alternarPagamento(l),
                        ),
                        title: Text(l.descricao),
                        subtitle: _SubtituloLancamento(l, banco),
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
}

/// Data, tags e clipe de anexos de um lancamento na listagem.
class _SubtituloLancamento extends StatelessWidget {
  const _SubtituloLancamento(this.l, this.banco);
  final Lancamento l;
  final Banco banco;

  @override
  Widget build(BuildContext context) {
    final tags = tagsDoTexto(l.tags);
    return StreamBuilder<Map<String, int>>(
      stream: banco.observarContagemAnexos(),
      builder: (context, snap) {
        final n = snap.data?[l.id] ?? 0;
        final extras = [
          if (tags.isNotEmpty) tags.map((t) => '#$t').join(' '),
          if (n > 0) '📎 $n',
        ];
        return Text(
          [formatarData(l.dia), ...extras].join('  ·  '),
          key: Key('sub_${l.id}'),
        );
      },
    );
  }
}
