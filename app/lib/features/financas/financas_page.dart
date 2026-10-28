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

  String _tituloMes(int ano, int mes) {
    final t = nomeDoMes(DateTime(ano, mes));
    return t[0].toUpperCase() + t.substring(1);
  }

  /// Pergunta antes de excluir; em serie, pergunta se vale so para este ou tambem para os seguintes.
  Future<void> _excluir(BuildContext context, Banco banco, Lancamento l) async {
    final seguintes = await banco.contarSeguintesDaSerie(l);
    if (!context.mounted) return;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(seguintes > 0
            ? '"${l.descricao}" faz parte de uma série com mais $seguintes lançamento(s) depois dele.'
            : '"${l.descricao}" será excluído, junto com seus anexos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          if (seguintes > 0)
            TextButton(key: const Key('excluir_este_e_seguintes'), onPressed: () => Navigator.pop(ctx, 'seguintes'), child: const Text('Este e os seguintes')),
          FilledButton(
              key: const Key('confirmar_exclusao_lancamento'),
              onPressed: () => Navigator.pop(ctx, 'este'),
              child: Text(seguintes > 0 ? 'Só este' : 'Excluir')),
        ],
      ),
    );
    if (r == null) return;
    await banco.excluirLancamentoDaSerie(l, seguintes: r == 'seguintes');
  }

  Widget _item(BuildContext context, Banco banco, Lancamento l) {
    final receita = l.tipo == 'receita';
    final cor = receita ? Colors.green : Colors.red;
    // Tocar no nome nao faz nada: baixa, edicao e exclusao ficam nos icones.
    return ListTile(
      key: Key('lancamento_${l.id}'),
      leading: l.status == 'pago'
          ? IconButton(
              key: Key('baixa_${l.id}'),
              tooltip: receita ? 'Recebido (ver detalhes)' : 'Pago (ver detalhes)',
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => abrirDetalheLancamento(context, l.id),
            )
          : IconButton(
              key: Key('baixa_${l.id}'),
              tooltip: receita ? 'Lançar recebimento' : 'Lançar baixa',
              icon: Icon(receita ? Icons.attach_money : Icons.price_check, color: cor),
              onPressed: () => abrirFormularioLancamento(context, lancamento: l, registrarPagamento: true),
            ),
      title: Text(l.descricao),
      subtitle: _SubtituloLancamento(l, banco),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${receita ? '+' : '-'} ${formatarCentavos(l.valorCentavos)}', style: TextStyle(color: cor)),
        IconButton(
          key: Key('editar_${l.id}'),
          tooltip: 'Alterar',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => abrirFormularioLancamento(context, lancamento: l),
        ),
        IconButton(
          key: Key('excluir_${l.id}'),
          tooltip: 'Excluir',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _excluir(context, banco, l),
        ),
      ]),
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
                child: ListView(
                  children: [
                    for (final g in agruparPorMes(itens))
                      ExpansionTile(
                        key: PageStorageKey('mes_${g.ano}_${g.mes}'),
                        // o mes atual ja vem aberto; os demais, recolhidos
                        initiallyExpanded: g.ano == DateTime.now().year && g.mes == DateTime.now().month,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(_tituloMes(g.ano, g.mes),
                            key: Key('mes_${g.ano}_${g.mes}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Wrap(spacing: 14, runSpacing: 2, children: [
                          Text('Receitas ${formatarCentavos(g.receitasCentavos)}',
                              key: Key('receitas_${g.ano}_${g.mes}'), style: const TextStyle(color: Colors.green)),
                          Text('Despesas ${formatarCentavos(g.despesasCentavos)}',
                              key: Key('despesas_${g.ano}_${g.mes}'), style: const TextStyle(color: Colors.red)),
                        ]),
                        trailing: Text('${g.saldoCentavos < 0 ? '-' : ''}${formatarCentavos(g.saldoCentavos.abs())}',
                            key: Key('saldo_${g.ano}_${g.mes}'),
                            style: TextStyle(fontWeight: FontWeight.w600, color: g.saldoCentavos < 0 ? Colors.red : Colors.green)),
                        children: [
                          for (final l in g.itens) ...[
                            const Divider(height: 1),
                            _item(context, banco, l),
                          ],
                        ],
                      ),
                  ],
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
