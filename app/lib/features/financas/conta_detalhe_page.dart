import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bancos.dart';
import '../../core/calculos.dart';
import '../../core/documentos.dart';
import '../../core/formatos.dart';
import '../../data/local/banco.dart';
import '../nav/acoes_usuario.dart';
import 'contas_page.dart';

/// Gerenciar conta: dados cadastrados, edicao e exclusao.
class ContaDetalhePage extends ConsumerWidget {
  const ContaDetalhePage({super.key, required this.contaId});

  final String contaId;

  Future<void> _excluir(BuildContext context, Banco banco, Conta c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir conta?'),
        content: Text('A conta "${tituloDaConta(c)}" será removida do cadastro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('confirmar_exclusao'), onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    final motivo = await banco.excluirConta(c.id);
    if (!context.mounted) return;
    if (motivo != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(motivo)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conta excluída.')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    return StreamBuilder<Conta?>(
      stream: banco.observarConta(contaId),
      builder: (context, snap) {
        final c = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Gerenciar conta'),
            actions: [
              if (c != null)
                IconButton(
                  key: const Key('botao_excluir_conta'),
                  tooltip: 'Excluir conta',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _excluir(context, banco, c),
                ),
              const AcoesUsuario(),
            ],
          ),
          body: c == null
              ? Center(child: Text(snap.connectionState == ConnectionState.waiting ? '' : 'Conta não encontrada.'))
              : _Corpo(conta: c),
        );
      },
    );
  }
}

class _Corpo extends ConsumerWidget {
  const _Corpo({required this.conta});
  final Conta conta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    final t = Theme.of(context).textTheme;
    Widget dado(String rotulo, String valor, {Key? chave}) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: t.bodySmall),
            Text(valor, key: chave, style: t.titleMedium),
          ]),
        );
    final doc = soDigitos(conta.documento);
    final propria = conta.titularidade != 'externa';
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Row(children: [
            if (conta.banco != null) SeloBanco(conta.banco, raio: 22),
            if (conta.banco != null) const SizedBox(width: 12),
            Expanded(child: dado('Banco', tituloDaConta(conta).toUpperCase(), chave: const Key('detalhe_banco'))),
          ]),
          if (conta.apelido != null && conta.apelido!.isNotEmpty) dado('Apelido', conta.apelido!),
          if (conta.banco != null)
            Row(children: [
              Expanded(child: dado('Agência', conta.agencia ?? '—', chave: const Key('detalhe_agencia'))),
              Expanded(child: dado('Conta', conta.numeroConta ?? '—', chave: const Key('detalhe_conta'))),
            ]),
          dado('Tipo', nomeDoTipoConta(conta.tipo)),
          dado('Titularidade', propria ? 'Minha conta' : 'Conta externa'),
          if (conta.banco != null) ...[
            dado('CPF/CNPJ', doc.isEmpty ? 'Não informado' : formatarCpfOuCnpj(doc), chave: const Key('detalhe_documento')),
            dado('Chave PIX', (conta.chavePix ?? '').isEmpty ? 'Não vinculada' : conta.chavePix!, chave: const Key('detalhe_pix')),
          ],
          if (propria)
            StreamBuilder<List<Lancamento>>(
              stream: banco.observarLancamentos(),
              builder: (context, sl) => dado(
                  'Saldo atual', formatarCentavos(calcularSaldoDaContaCentavos(conta, sl.data ?? const <Lancamento>[])),
                  chave: const Key('detalhe_saldo')),
            ),
          const SizedBox(height: 8),
          Center(
            child: FilledButton.tonalIcon(
              key: const Key('botao_editar'),
              onPressed: () => abrirFormularioConta(context, conta: conta),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
          ),
        ]),
      ),
    );
  }
}
