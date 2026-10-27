import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bancos.dart';
import '../../core/calculos.dart';
import '../../core/formatos.dart';
import '../../data/local/banco.dart';
import 'conta_detalhe_page.dart';
import 'conta_form_page.dart';

/// Nome de exibicao da conta: nome do banco (ou o nome da conta, se nao for bancaria).
String tituloDaConta(Conta c) => c.banco == null || c.banco == codigoOutroBanco ? c.nome : bancoPorCodigo(c.banco).nome;

String nomeDoTipoConta(String tipo) => switch (tipo) {
      'corrente' => 'Conta corrente',
      'poupanca' => 'Poupança',
      'cartao' => 'Cartão de crédito',
      'dinheiro' => 'Dinheiro',
      _ => tipo,
    };

/// Aba "Contas" de Financas: contas proprias (com saldo) e contas externas (so cadastro).
class ContasPage extends ConsumerWidget {
  const ContasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    return StreamBuilder<List<Conta>>(
      stream: banco.observarContas(),
      builder: (context, sc) => StreamBuilder<List<Lancamento>>(
        stream: banco.observarLancamentos(),
        builder: (context, sl) {
          final contas = sc.data ?? const <Conta>[];
          final ls = sl.data ?? const <Lancamento>[];
          final proprias = contas.where((c) => c.titularidade != 'externa').toList();
          final externas = contas.where((c) => c.titularidade == 'externa').toList();
          return SingleChildScrollView(
            key: const Key('lista_contas'),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                child: FilledButton.icon(
                  key: const Key('botao_adicionar_conta'),
                  onPressed: () => abrirFormularioConta(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar conta'),
                ),
              ),
              const SizedBox(height: 16),
              _Secao(
                titulo: 'Minhas contas',
                vazio: 'Nenhuma conta sua cadastrada.',
                chave: 'secao_proprias',
                contas: proprias,
                lancamentos: ls,
              ),
              const SizedBox(height: 16),
              _Secao(
                titulo: 'Contas externas',
                vazio: 'Nenhuma conta externa cadastrada.',
                chave: 'secao_externas',
                contas: externas,
                lancamentos: ls,
              ),
            ]),
          );
        },
      ),
    );
  }
}

Future<void> abrirFormularioConta(BuildContext context, {Conta? conta}) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ContaFormPage(conta: conta)));

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.vazio, required this.chave, required this.contas, required this.lancamentos});

  final String titulo;
  final String vazio;
  final String chave;
  final List<Conta> contas;
  final List<Lancamento> lancamentos;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key(chave),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (contas.isEmpty)
            Text(vazio)
          else
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final c in contas) _CartaoConta(conta: c, lancamentos: lancamentos),
            ]),
        ]),
      ),
    );
  }
}

class _CartaoConta extends StatelessWidget {
  const _CartaoConta({required this.conta, required this.lancamentos});

  final Conta conta;
  final List<Lancamento> lancamentos;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final propria = conta.titularidade != 'externa';
    final saldo = calcularSaldoDaContaCentavos(conta, lancamentos);
    return SizedBox(
      width: 220,
      child: Card(
        key: Key('conta_${conta.id}'),
        margin: EdgeInsets.zero,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context)
              .push<void>(MaterialPageRoute(builder: (_) => ContaDetalhePage(contaId: conta.id))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (conta.banco != null)
                  SeloBanco(conta.banco)
                else
                  const CircleAvatar(radius: 18, child: Icon(Icons.account_balance_wallet_outlined, size: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tituloDaConta(conta),
                      overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 8),
              if (conta.apelido != null && conta.apelido!.isNotEmpty) Text(conta.apelido!, style: t.bodySmall),
              if (conta.agencia != null || conta.numeroConta != null)
                Row(children: [
                  Expanded(child: _Dado('Agência', conta.agencia ?? '—')),
                  Expanded(child: _Dado('Conta', conta.numeroConta ?? '—')),
                ])
              else
                Text(nomeDoTipoConta(conta.tipo), style: t.bodySmall),
              if (propria) ...[
                const SizedBox(height: 6),
                _Dado('Saldo', formatarCentavos(saldo), chave: Key('saldo_${conta.id}')),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Dado extends StatelessWidget {
  const _Dado(this.rotulo, this.valor, {this.chave});
  final String rotulo;
  final String valor;
  final Key? chave;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(rotulo, style: t.labelSmall),
      Text(valor, key: chave, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}
