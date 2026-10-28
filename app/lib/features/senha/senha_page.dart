import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/senha_calculo.dart';
import '../../data/local/banco.dart';
import '../nav/menu_lateral.dart';
import 'gerador_dialogo.dart';
import 'senha_detalhe.dart';
import 'senha_form_page.dart';

/// Largura a partir da qual o painel mostra as tres colunas (categorias | lista | detalhe).
const larguraTresColunas = 900.0;

/// Modulo Senha: painel do cofre. Categorias e etiquetas com a contagem de cada uma, lista com busca
/// e o detalhe do item escolhido. Em tela estreita as categorias viram chips e o detalhe abre em outra tela.
class SenhaPage extends ConsumerStatefulWidget {
  const SenhaPage({super.key, this.titulo = 'Senha', this.agora});

  /// Nome do modulo como esta no cadastro de modulos.
  final String titulo;
  final DateTime? agora; // para testes

  @override
  ConsumerState<SenhaPage> createState() => _SenhaPageState();
}

class _SenhaPageState extends ConsumerState<SenhaPage> {
  String _filtro = filtroTodos;
  String _busca = '';
  String _ordem = 'nome';
  String? _selecionado;

  DateTime get _agora => widget.agora ?? DateTime.now();

  Future<void> _novo() async {
    final id = await abrirCadastroSenha(context);
    if (id != null && mounted) setState(() => _selecionado = id);
  }

  Widget _itemMenu(String filtro, String nome, IconData icone, Map<String, int> cont, {Color? cor}) => ListTile(
        key: Key('filtro_$filtro'),
        dense: true,
        selected: _filtro == filtro,
        leading: Icon(icone, color: cor),
        title: Text(nome),
        trailing: Text('${cont[filtro] ?? 0}'),
        onTap: () => setState(() => _filtro = filtro),
      );

  Widget _menuLateral(List<Credencial> todas) {
    final cont = contagensDoCofre(todas, _agora);
    final etiquetas = etiquetasDoCofre(todas);
    return ListView(children: [
      const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Cofre', style: TextStyle(fontWeight: FontWeight.w700))),
      _itemMenu(filtroTodos, 'Todos os itens', Icons.apps, cont),
      _itemMenu(filtroFavoritos, 'Favoritos', Icons.star, cont, cor: Colors.amber.shade700),
      for (final e in tiposSenha.entries) _itemMenu(filtroTipo(e.key), e.value, iconesTipoSenha[e.key]!, cont),
      _itemMenu(filtroRecentes, 'Recentes', Icons.history, cont),
      if (etiquetas.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Etiquetas', style: TextStyle(fontWeight: FontWeight.w700))),
        for (final t in etiquetas) _itemMenu(filtroTag(t), t, Icons.label_outline, cont),
      ],
    ]);
  }

  Widget _chips(List<Credencial> todas) {
    final cont = contagensDoCofre(todas, _agora);
    final itens = <(String, String)>[
      (filtroTodos, 'Todos'),
      (filtroFavoritos, 'Favoritos'),
      for (final e in tiposSenha.entries) (filtroTipo(e.key), e.value),
      (filtroRecentes, 'Recentes'),
      for (final t in etiquetasDoCofre(todas)) (filtroTag(t), '#$t'),
    ];
    return SizedBox(
      key: const Key('chips_senha'),
      height: 48,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
        for (final i in itens)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ChoiceChip(
              key: Key('chip_${i.$1}'),
              label: Text('${i.$2} (${cont[i.$1] ?? 0})'),
              selected: _filtro == i.$1,
              onSelected: (_) => setState(() => _filtro = i.$1),
            ),
          ),
      ]),
    );
  }

  Widget _lista(List<Credencial> visiveis, {required bool tresColunas}) {
    final tema = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          key: const Key('busca_senha'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Pesquisar'),
          onChanged: (v) => setState(() => _busca = v),
        ),
      ),
      Expanded(
        child: visiveis.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nada por aqui. Toque em + para guardar um item no cofre.', key: Key('cofre_vazio'), textAlign: TextAlign.center),
                ),
              )
            : ListView.builder(
                itemCount: visiveis.length,
                itemBuilder: (_, i) {
                  final c = visiveis[i];
                  return ListTile(
                    key: Key('item_${c.id}'),
                    selected: tresColunas && _selecionado == c.id,
                    leading: CircleAvatar(
                      backgroundColor: tema.colorScheme.primaryContainer,
                      child: Icon(iconesTipoSenha[c.tipo] ?? Icons.lock_outline, color: tema.colorScheme.onPrimaryContainer),
                    ),
                    title: Text(c.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([tiposSenha[c.tipo] ?? c.tipo, ...tagsDaCredencial(c)].join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: c.favorito ? Icon(Icons.star, size: 18, color: Colors.amber.shade700) : null,
                    onTap: () {
                      if (tresColunas) {
                        setState(() => _selecionado = c.id);
                      } else {
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SenhaDetalhePage(id: c.id)));
                      }
                    },
                  );
                },
              ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BarraPagina(title: Text(widget.titulo), actions: [
        IconButton(
          key: const Key('abrir_gerador'),
          tooltip: 'Gerador de senhas',
          icon: const Icon(Icons.auto_awesome_outlined),
          onPressed: () => abrirGeradorDeSenhas(context, permitirUsar: false),
        ),
        PopupMenuButton<String>(
          key: const Key('classificacao'),
          tooltip: 'Classificação',
          icon: const Icon(Icons.sort),
          initialValue: _ordem,
          onSelected: (v) => setState(() => _ordem = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'nome', child: Text('Por nome')),
            PopupMenuItem(value: 'modificado', child: Text('Modificados recentemente')),
            PopupMenuItem(value: 'criado', child: Text('Criados recentemente')),
          ],
        ),
      ]),
      body: StreamBuilder<List<Credencial>>(
        stream: ref.watch(bancoProvider).observarCredenciais(),
        builder: (context, snap) {
          final todas = snap.data ?? const <Credencial>[];
          final visiveis = ordenarCredenciais(
              todas.where((c) => confereFiltro(c, _filtro, _agora) && confereBusca(c, _busca)).toList(), _ordem);
          return LayoutBuilder(builder: (context, caixa) {
            if (caixa.maxWidth >= larguraTresColunas) {
              final selecionado = visiveis.any((c) => c.id == _selecionado) ? _selecionado : null;
              return Row(children: [
                SizedBox(width: 250, child: _menuLateral(todas)),
                const VerticalDivider(width: 1),
                SizedBox(width: 340, child: _lista(visiveis, tresColunas: true)),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selecionado == null
                      ? const Center(child: Text('Escolha um item para ver os detalhes.', key: Key('detalhe_vazio')))
                      : SenhaDetalhe(key: ValueKey(selecionado), id: selecionado, aoExcluir: () => setState(() => _selecionado = null)),
                ),
              ]);
            }
            return Column(children: [
              _chips(todas),
              Expanded(child: _lista(visiveis, tresColunas: false)),
            ]);
          });
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('fab_nova_senha'),
        tooltip: 'Adicionar',
        onPressed: _novo,
        child: const Icon(Icons.add),
      ),
    );
  }
}
