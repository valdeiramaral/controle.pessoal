import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/arquivos.dart';
import '../../core/formatos.dart';
import '../../core/lancamento_calculo.dart';
import '../../core/pagamento.dart';
import '../../data/local/banco.dart';
import 'contas_page.dart';
import 'lancamento_form_page.dart';

/// Abre os detalhes de um lancamento (dados, anexos, editar, pagar, excluir).
Future<void> abrirDetalheLancamento(BuildContext context, String id) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => LancamentoDetalhePage(lancamentoId: id)));

class LancamentoDetalhePage extends ConsumerWidget {
  const LancamentoDetalhePage({super.key, required this.lancamentoId});
  final String lancamentoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    return StreamBuilder<Lancamento?>(
      stream: banco.observarLancamento(lancamentoId),
      builder: (context, snap) {
        final l = snap.data;
        if (l == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Lançamento')),
            body: Center(child: snap.connectionState == ConnectionState.waiting ? const CircularProgressIndicator() : const Text('Lançamento não encontrado.')),
          );
        }
        return _Corpo(l: l);
      },
    );
  }
}

class _Corpo extends ConsumerWidget {
  const _Corpo({required this.l});
  final Lancamento l;

  Future<void> _excluir(BuildContext context, WidgetRef ref) async {
    final banco = ref.read(bancoProvider);
    final seguintes = await banco.contarSeguintesDaSerie(l);
    if (!context.mounted) return;
    // Escolha: so este / este e os seguintes (se houver) / cancelar.
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
          FilledButton(key: const Key('confirmar_exclusao_lancamento'), onPressed: () => Navigator.pop(ctx, 'este'), child: Text(seguintes > 0 ? 'Só este' : 'Excluir')),
        ],
      ),
    );
    if (r == null) return;
    await banco.excluirLancamentoDaSerie(l, seguintes: r == 'seguintes');
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banco = ref.watch(bancoProvider);
    final t = Theme.of(context).textTheme;
    final receita = l.tipo == 'receita';
    final cor = receita ? Colors.green.shade700 : Colors.red.shade700;
    final tags = tagsDoTexto(l.tags);
    return Scaffold(
      appBar: AppBar(
        title: Text(receita ? 'Receita' : 'Despesa'),
        actions: [
          IconButton(
            key: const Key('botao_editar_lancamento'),
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => abrirFormularioLancamento(context, lancamento: l),
          ),
          IconButton(
            key: const Key('botao_excluir_lancamento'),
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _excluir(context, ref),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(l.descricao, key: const Key('detalhe_descricao'), style: t.headlineSmall),
            const SizedBox(height: 4),
            Text('${receita ? '+' : '-'} ${formatarCentavos(l.valorCentavos)}',
                key: const Key('detalhe_valor'), style: t.headlineMedium?.copyWith(color: cor, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  l.status == 'pago'
                      ? (receita ? 'Recebida' : 'Paga')
                      : (l.tipoPagamento == 'parcial' ? (receita ? 'Recebimento parcial' : 'Pagamento parcial') : (receita ? 'A receber' : 'A pagar')),
                  key: const Key('detalhe_situacao'),
                  style: t.titleMedium,
                ),
              ),
              if (l.status != 'pago')
                FilledButton.tonalIcon(
                  key: const Key('botao_registrar_pagamento'),
                  onPressed: () => abrirFormularioLancamento(context, lancamento: l, registrarPagamento: true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(receita ? 'Registrar recebimento' : 'Registrar pagamento'),
                ),
              if (l.dataPagamento != null)
                TextButton(
                  key: const Key('botao_desfazer_pagamento'),
                  onPressed: () => banco.desfazerPagamento(l),
                  child: Text(receita ? 'Desfazer recebimento' : 'Desfazer pagamento'),
                ),
            ]),
            if (l.dataPagamento != null) ...[
              const SizedBox(height: 8),
              Container(
                key: const Key('detalhe_pagamento'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  _Linha(receita ? 'Data do recebimento' : 'Data do pagamento', formatarData(l.dataPagamento!), chave: 'detalhe_data_pagamento'),
                  _Linha(receita ? 'Forma de recebimento' : 'Forma de pagamento', nomeDaForma(l.formaPagamento), chave: 'detalhe_forma'),
                  FutureBuilder<Conta?>(
                    future: l.contaPagamentoId == null ? Future.value(null) : (banco.select(banco.contas)..where((c) => c.id.equals(l.contaPagamentoId!))).getSingleOrNull(),
                    builder: (_, sn) => _Linha(receita ? 'Banco do recebimento' : 'Banco do pagamento',
                        sn.data == null ? '—' : (tituloDaConta(sn.data!) == sn.data!.nome ? sn.data!.nome : '${tituloDaConta(sn.data!)} · ${sn.data!.nome}'),
                        chave: 'detalhe_banco_pagamento'),
                  ),
                  _Linha(receita ? 'Tipo de recebimento' : 'Tipo de pagamento', tiposPagamento[l.tipoPagamento] ?? '—', chave: 'detalhe_tipo_pagamento'),
                  _Linha(receita ? 'Valor recebido' : 'Valor pago', formatarCentavos(l.valorPagoCentavos ?? l.valorCentavos), chave: 'detalhe_valor_pago'),
                  if ((l.descontoCentavos ?? 0) > 0) _Linha('Desconto', formatarCentavos(l.descontoCentavos!), chave: 'detalhe_desconto'),
                  if (l.status != 'pago') _Linha('Falta ${receita ? 'receber' : 'pagar'}', formatarCentavos(restanteCentavos(l)), chave: 'detalhe_restante'),
                ]),
              ),
            ],
            const Divider(),
            _Linha('Vencimento', formatarData(l.dia), chave: 'detalhe_data'),
            FutureBuilder<Conta?>(
              future: (banco.select(banco.contas)..where((c) => c.id.equals(l.contaId))).getSingleOrNull(),
              builder: (_, s) => _Linha('Conta/cartão', s.data == null ? '—' : tituloDaConta(s.data!) == s.data!.nome ? s.data!.nome : '${tituloDaConta(s.data!)} · ${s.data!.nome}', chave: 'detalhe_conta'),
            ),
            FutureBuilder<Categoria?>(
              future: l.categoriaId == null ? Future.value(null) : (banco.select(banco.categorias)..where((c) => c.id.equals(l.categoriaId!))).getSingleOrNull(),
              builder: (_, s) => _Linha('Categoria', s.data?.nome ?? 'Sem categoria', chave: 'detalhe_categoria'),
            ),
            if (l.parcelaTotal != null)
              _Linha('Parcela', '${l.parcelaNumero} de ${l.parcelaTotal}', chave: 'detalhe_serie')
            else if (l.recorrencia != null)
              _Linha('Repetição', 'Fixa (todo mês)', chave: 'detalhe_serie'),
            if ((l.observacao ?? '').isNotEmpty) _Linha('Observação', l.observacao!, chave: 'detalhe_observacao'),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [for (final tg in tags) Chip(key: Key('detalhe_tag_$tg'), label: Text('#$tg'))]),
            ],
            const SizedBox(height: 16),
            Text('Anexos', style: t.titleMedium),
            StreamBuilder<List<Anexo>>(
              stream: banco.observarAnexos(l.id),
              builder: (context, snap) {
                final lista = snap.data ?? const <Anexo>[];
                if (lista.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhum anexo. Use Editar para anexar comprovantes.'));
                return Column(children: [for (final a in lista) _ItemAnexo(a)]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor, {required this.chave});
  final String rotulo;
  final String valor;
  final String chave;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(rotulo, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Expanded(child: Text(valor, key: Key(chave), style: t.bodyLarge)),
      ]),
    );
  }
}

class _ItemAnexo extends ConsumerWidget {
  const _ItemAnexo(this.a);
  final Anexo a;

  bool get _imagem => (a.tipoMime ?? '').startsWith('image/') && a.tipoMime != 'image/heic';
  bool get _texto => a.tipoMime == 'text/plain';

  Future<void> _baixar(BuildContext context, WidgetRef ref, Uint8List bytes) async {
    await ref.read(baixadorArquivosProvider)(a.nomeArquivo, bytes, a.tipoMime);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${a.nomeArquivo}" baixado.')));
    }
  }

  Future<void> _abrir(BuildContext context, WidgetRef ref) async {
    final bytes = await ref.read(bancoProvider).conteudoDoAnexo(a.id);
    if (bytes == null || !context.mounted) return;
    if (!_imagem && !_texto) {
      await _baixar(context, ref, bytes); // PDF e outros: o aparelho abre no leitor proprio
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(a.nomeArquivo, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatarTamanho(a.tamanhoBytes)),
              trailing: IconButton(key: const Key('fechar_anexo'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ),
            Flexible(
              child: _imagem
                  ? InteractiveViewer(child: Image.memory(bytes, key: const Key('previa_imagem'), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(24), child: Text('Não foi possível mostrar a imagem. Use Baixar.'))))
                  : SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(utf8.decode(bytes, allowMalformed: true), key: const Key('previa_texto'))),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('baixar_anexo_dialogo'),
                  onPressed: () => _baixar(context, ref, bytes),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Baixar'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: Key('anexo_${a.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(_imagem ? Icons.image_outlined : (a.tipoMime == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.description_outlined)),
      title: Text(a.nomeArquivo, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatarTamanho(a.tamanhoBytes)),
      trailing: IconButton(
        key: Key('baixar_anexo_${a.id}'),
        tooltip: 'Baixar',
        icon: const Icon(Icons.download_outlined),
        onPressed: () async {
          final bytes = await ref.read(bancoProvider).conteudoDoAnexo(a.id);
          if (bytes != null && context.mounted) await _baixar(context, ref, bytes);
        },
      ),
      onTap: () => _abrir(context, ref),
    );
  }
}
