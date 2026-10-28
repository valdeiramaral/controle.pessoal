import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/banco.dart';
import '../nav/menu_lateral.dart';
import 'biblioteca_form_page.dart';

/// Modulo Biblioteca: acervo de obras (tombo mais alto primeiro), com busca por titulo, autor... no cadastro.
/// O "+" abre o cadastro de uma obra nova.
class BibliotecaPage extends ConsumerStatefulWidget {
  const BibliotecaPage({super.key, this.titulo = 'Biblioteca'});

  /// Nome do modulo como esta no cadastro de modulos.
  final String titulo;

  @override
  ConsumerState<BibliotecaPage> createState() => _BibliotecaPageState();
}

class _BibliotecaPageState extends ConsumerState<BibliotecaPage> {
  String _busca = '';

  bool _confere(Obra o) {
    if (_busca.isEmpty) return true;
    final q = _busca.toLowerCase();
    return o.titulo.toLowerCase().contains(q) ||
        (o.subtitulo ?? '').toLowerCase().contains(q) ||
        (o.isbn ?? '').toLowerCase().contains(q) ||
        '${o.tombo}'.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BarraPagina(title: Text(widget.titulo)),
      body: StreamBuilder<List<Obra>>(
        stream: ref.watch(bancoProvider).observarObras(),
        builder: (context, snap) {
          final todas = snap.data ?? const <Obra>[];
          final lista = todas.where(_confere).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                key: const Key('busca_obra'),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por título, ISBN ou tombo'),
                onChanged: (v) => setState(() => _busca = v.trim()),
              ),
            ),
            Expanded(
              child: lista.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                            todas.isEmpty
                                ? 'Nenhuma obra cadastrada ainda. Toque em + para incluir a primeira.'
                                : 'Nenhuma obra encontrada.',
                            key: const Key('biblioteca_vazia'),
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                      itemCount: lista.length,
                      itemBuilder: (_, i) => _CartaoObra(obra: lista[i]),
                    ),
            ),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('fab_nova_obra'),
        tooltip: 'Nova obra',
        onPressed: () => abrirCadastroObra(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CartaoObra extends StatelessWidget {
  const _CartaoObra({required this.obra});

  final Obra obra;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final o = obra;
    final detalhes = [
      if ((o.editoraDescricao ?? '').isNotEmpty) o.editoraDescricao!,
      if (o.ano != null) '${o.ano}',
      if ((o.localizacaoDescricao ?? '').isNotEmpty) o.localizacaoDescricao!,
      if ((o.situacaoDescricao ?? '').isNotEmpty) o.situacaoDescricao!,
    ].join(' • ');
    return Card(
      key: Key('obra_${o.id}'),
      child: ListTile(
        onTap: () => abrirCadastroObra(context, obra: o),
        leading: Container(
          width: 44,
          height: 60,
          color: tema.colorScheme.primaryContainer,
          child: o.capa == null
              ? Icon(Icons.local_library_outlined, color: tema.colorScheme.onPrimaryContainer)
              : Image.memory(o.capa!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
        ),
        title: Text(o.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Tombo ${o.tombo}${(o.isbn ?? '').isEmpty ? '' : ' • ISBN ${o.isbn}'}${detalhes.isEmpty ? '' : '\n$detalhes'}'),
        isThreeLine: detalhes.isNotEmpty,
        trailing: Text(o.noAcervo ? 'NO ACERVO' : 'FORA',
            style: TextStyle(fontWeight: FontWeight.w700, color: o.noAcervo ? Colors.green.shade800 : tema.colorScheme.error)),
      ),
    );
  }
}
