import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatos.dart';
import '../../core/leitura_calculo.dart';
import '../../data/local/banco.dart';
import '../nav/menu_lateral.dart';
import 'leitura_form_page.dart';
import 'nota_tema.dart';

/// Modulo Leitura: lista das fichas de leitura (mais recentes primeiro); o "+" abre uma ficha nova.
class LeituraPage extends ConsumerWidget {
  const LeituraPage({super.key, this.titulo = 'Leitura'});

  /// Nome do modulo como esta no cadastro de modulos.
  final String titulo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: BarraPagina(title: Text(titulo)),
      body: StreamBuilder<List<Leitura>>(
        stream: ref.watch(bancoProvider).observarLeituras(),
        builder: (context, snap) {
          final lista = snap.data ?? const <Leitura>[];
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma ficha de leitura ainda. Toque em + para cadastrar o primeiro livro.',
                    key: Key('leitura_vazia'), textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            itemCount: lista.length,
            itemBuilder: (_, i) => _CartaoLeitura(leitura: lista[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('fab_nova_leitura'),
        tooltip: 'Nova ficha de leitura',
        onPressed: () => abrirFichaLeitura(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CartaoLeitura extends StatelessWidget {
  const _CartaoLeitura({required this.leitura});

  final Leitura leitura;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final l = leitura;
    final datas = [
      if (l.iniciouEm != null) 'Início: ${formatarData(l.iniciouEm!)}',
      if (l.terminouEm != null) 'Fim: ${formatarData(l.terminouEm!)}',
    ].join('  •  ');
    return Card(
      key: Key('leitura_${l.id}'),
      child: InkWell(
        onTap: () => abrirFichaLeitura(context, leitura: l),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 56,
              height: 80,
              color: tema.colorScheme.primaryContainer,
              child: l.capa == null
                  ? Icon(Icons.menu_book_outlined, color: tema.colorScheme.onPrimaryContainer)
                  : Image.memory(l.capa!,
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.titulo, style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if ((l.autor ?? '').isNotEmpty) Text(l.autor!),
                const SizedBox(height: 4),
                Text(
                  '${situacaoDaLeitura(l.iniciouEm, l.terminouEm)} • ${formatosLivro[l.formato] ?? l.formato}'
                  '${datas.isEmpty ? '' : '\n$datas'}',
                  style: tema.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 2, children: [
                  for (final t in temasLeitura)
                    if (notaDoTema(l, t.codigo) > 0) NotaTema(tema: t, nota: notaDoTema(l, t.codigo), tamanho: 14),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
