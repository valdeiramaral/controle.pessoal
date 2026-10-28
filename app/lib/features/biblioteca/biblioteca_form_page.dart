import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/arquivos.dart';
import '../../core/formatos.dart';
import '../../data/local/banco.dart';

/// Abre o cadastro de obra (nova ou edicao).
Future<void> abrirCadastroObra(BuildContext context, {Obra? obra}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ObraFormPage(obra: obra)));

/// Campo de lista: codigo + descricao, com lupa para escolher entre os valores ja usados em outras obras.
class _Lista {
  _Lista(this.chave, this.rotulo, {this.larguraCodigo = 70});
  final String chave;
  final String rotulo;
  final double larguraCodigo;
  final codigo = TextEditingController();
  final descricao = TextEditingController();
  void dispose() {
    codigo.dispose();
    descricao.dispose();
  }
}

/// Cadastro da obra: tombo, ISBN, no acervo, tipo, titulo, subtitulo, dados da edicao, classificacao,
/// colecao, idioma, editora, cobranca, localizacao, situacao, capa e observacoes.
class ObraFormPage extends ConsumerStatefulWidget {
  const ObraFormPage({super.key, this.obra});

  final Obra? obra;

  @override
  ConsumerState<ObraFormPage> createState() => _ObraFormPageState();
}

class _ObraFormPageState extends ConsumerState<ObraFormPage> {
  final _form = GlobalKey<FormState>();
  final _tombo = TextEditingController();
  final _isbn = TextEditingController();
  final _titulo = TextEditingController();
  final _subtitulo = TextEditingController();
  final _edicao = TextEditingController();
  final _refEdicao = TextEditingController();
  final _ano = TextEditingController();
  final _dias = TextEditingController();
  final _codClassificacao = TextEditingController();
  final _codAutor = TextEditingController();
  final _tomo = TextEditingController();
  final _volume = TextEditingController();
  final _exemplar = TextEditingController(text: '1');
  final _faixa = TextEditingController(text: '00-99');
  final _paginas = TextEditingController();
  final _serie = TextEditingController();
  final _editoraComplemento = TextEditingController();
  final _valor = TextEditingController();
  final _observacoes = TextEditingController();
  final _listas = <String, _Lista>{
    'tipo': _Lista('tipo', 'Tipo'),
    'classif': _Lista('classif', 'Tipo de Classificação Bibliográfica'),
    'colecao': _Lista('colecao', 'Coleção'),
    'idioma': _Lista('idioma', 'Idioma'),
    'editora': _Lista('editora', 'Editora'),
    'categoria': _Lista('categoria', 'Categoria de Cobrança'),
    'localizacao': _Lista('localizacao', 'Localização'),
    'situacao': _Lista('situacao', 'Situação'),
  };
  bool _noAcervo = true;
  bool _autoAjuste = true;
  bool _centralizar = true;
  Uint8List? _capa;
  List<Obra> _todas = const [];
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.obra != null;

  @override
  void initState() {
    super.initState();
    final o = widget.obra;
    if (o != null) {
      _tombo.text = '${o.tombo}';
      _isbn.text = o.isbn ?? '';
      _noAcervo = o.noAcervo;
      _titulo.text = o.titulo;
      _subtitulo.text = o.subtitulo ?? '';
      _edicao.text = o.edicao ?? '';
      _refEdicao.text = o.referenciaEdicao ?? '';
      _ano.text = o.ano == null ? '' : '${o.ano}';
      _dias.text = o.diasPrevisao == null ? '' : '${o.diasPrevisao}';
      _codClassificacao.text = o.codClassificacao ?? '';
      _codAutor.text = o.codAutor ?? '';
      _tomo.text = o.tomo ?? '';
      _volume.text = o.volume ?? '';
      _exemplar.text = '${o.exemplar}';
      _faixa.text = o.faixaEtaria;
      _paginas.text = o.nroPaginas == null ? '' : '${o.nroPaginas}';
      _serie.text = o.serie ?? '';
      _editoraComplemento.text = o.editoraComplemento ?? '';
      _valor.text = o.valorCentavos == null ? '' : (o.valorCentavos! / 100).toStringAsFixed(2).replaceAll('.', ',');
      _observacoes.text = o.observacoes ?? '';
      _capa = o.capa;
      _autoAjuste = o.capaAutoAjuste;
      _centralizar = o.capaCentralizar;
      _par('tipo', o.tipoCodigo, o.tipoDescricao);
      _par('classif', o.classifTipoCodigo, o.classifTipoDescricao);
      _par('colecao', o.colecaoCodigo, o.colecaoDescricao);
      _par('idioma', o.idiomaCodigo, o.idiomaDescricao);
      _par('editora', o.editoraCodigo, o.editoraDescricao);
      _par('categoria', o.categoriaCobrancaCodigo, o.categoriaCobrancaDescricao);
      _par('localizacao', o.localizacaoCodigo, o.localizacaoDescricao);
      _par('situacao', o.situacaoCodigo, o.situacaoDescricao);
    } else {
      ref.read(bancoProvider).proximoTombo().then((n) {
        if (mounted && _tombo.text.isEmpty) setState(() => _tombo.text = '$n');
      });
    }
    ref.read(bancoProvider).listarObras().then((l) {
      if (mounted) setState(() => _todas = l);
    });
  }

  void _par(String chave, String? cod, String? desc) {
    _listas[chave]!.codigo.text = cod ?? '';
    _listas[chave]!.descricao.text = desc ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _tombo, _isbn, _titulo, _subtitulo, _edicao, _refEdicao, _ano, _dias, _codClassificacao, _codAutor,
      _tomo, _volume, _exemplar, _faixa, _paginas, _serie, _editoraComplemento, _valor, _observacoes,
    ]) {
      c.dispose();
    }
    for (final l in _listas.values) {
      l.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
  int? _n(TextEditingController c) => int.tryParse(c.text.trim());

  /// Pares (codigo, descricao) ja usados nas obras cadastradas, para a lupa.
  List<(String, String)> _opcoes(String chave) {
    final vistos = <String, String>{};
    for (final o in _todas) {
      final (c, d) = switch (chave) {
        'tipo' => (o.tipoCodigo, o.tipoDescricao),
        'classif' => (o.classifTipoCodigo, o.classifTipoDescricao),
        'colecao' => (o.colecaoCodigo, o.colecaoDescricao),
        'idioma' => (o.idiomaCodigo, o.idiomaDescricao),
        'editora' => (o.editoraCodigo, o.editoraDescricao),
        'categoria' => (o.categoriaCobrancaCodigo, o.categoriaCobrancaDescricao),
        'localizacao' => (o.localizacaoCodigo, o.localizacaoDescricao),
        _ => (o.situacaoCodigo, o.situacaoDescricao),
      };
      if ((c ?? '').isNotEmpty) vistos.putIfAbsent(c!, () => d ?? '');
    }
    return [for (final e in vistos.entries) (e.key, e.value)]..sort((a, b) => a.$1.compareTo(b.$1));
  }

  Future<void> _lupa(_Lista l) async {
    final opcoes = _opcoes(l.chave);
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.rotulo),
        content: SizedBox(
          width: 360,
          child: opcoes.isEmpty
              ? const Text('Nada cadastrado ainda. Digite o código e a descrição no campo; eles ficam disponíveis aqui nas próximas obras.',
                  key: Key('lupa_vazia'))
              : ListView(shrinkWrap: true, children: [
                  for (final o in opcoes)
                    ListTile(
                      key: Key('opcao_${l.chave}_${o.$1}'),
                      title: Text(o.$1),
                      subtitle: Text(o.$2),
                      onTap: () => Navigator.pop(ctx, o),
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
      ),
    );
    if (r != null) {
      l.codigo.text = r.$1;
      l.descricao.text = r.$2;
    }
  }

  Future<void> _escolherCapa() async {
    final arquivos = await ref.read(escolhedorArquivosProvider)();
    final imagens = arquivos.where((a) => (a.tipoMime ?? '').startsWith('image/'));
    if (imagens.isNotEmpty && mounted) setState(() => _capa = imagens.first.bytes);
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir obra?'),
        content: Text('"${widget.obra!.titulo}" será excluída do cadastro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
              key: const Key('confirmar_exclusao_obra'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(bancoProvider).excluirObra(widget.obra!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (!_form.currentState!.validate()) return;
    final banco = ref.read(bancoProvider);
    final tombo = _n(_tombo)!;
    if (await banco.tomboEmUso(tombo, exceto: widget.obra?.id)) {
      setState(() => _erro = 'O tombo $tombo já está cadastrado em outra obra.');
      return;
    }
    setState(() => _salvando = true);
    final valor = _valor.text.trim().isEmpty ? null : centavosDeTexto(_valor.text);
    String? cod(String k) => _t(_listas[k]!.codigo);
    String? desc(String k) => _t(_listas[k]!.descricao);
    final dados = ObrasCompanion(
      tombo: Value(tombo),
      isbn: Value(_t(_isbn)),
      noAcervo: Value(_noAcervo),
      tipoCodigo: Value(cod('tipo')),
      tipoDescricao: Value(desc('tipo')),
      titulo: Value(_titulo.text.trim()),
      subtitulo: Value(_t(_subtitulo)),
      edicao: Value(_t(_edicao)),
      referenciaEdicao: Value(_t(_refEdicao)),
      ano: Value(_n(_ano)),
      diasPrevisao: Value(_n(_dias)),
      classifTipoCodigo: Value(cod('classif')),
      classifTipoDescricao: Value(desc('classif')),
      codClassificacao: Value(_t(_codClassificacao)),
      codAutor: Value(_t(_codAutor)),
      tomo: Value(_t(_tomo)),
      volume: Value(_t(_volume)),
      exemplar: Value(_n(_exemplar) ?? 1),
      faixaEtaria: Value(_t(_faixa) ?? '00-99'),
      nroPaginas: Value(_n(_paginas)),
      serie: Value(_t(_serie)),
      colecaoCodigo: Value(cod('colecao')),
      colecaoDescricao: Value(desc('colecao')),
      idiomaCodigo: Value(cod('idioma')),
      idiomaDescricao: Value(desc('idioma')),
      editoraCodigo: Value(cod('editora')),
      editoraDescricao: Value(desc('editora')),
      editoraComplemento: Value(_t(_editoraComplemento)),
      categoriaCobrancaCodigo: Value(cod('categoria')),
      categoriaCobrancaDescricao: Value(desc('categoria')),
      valorCentavos: Value(valor),
      localizacaoCodigo: Value(cod('localizacao')),
      localizacaoDescricao: Value(desc('localizacao')),
      situacaoCodigo: Value(cod('situacao')),
      situacaoDescricao: Value(desc('situacao')),
      capa: Value(_capa),
      capaAutoAjuste: Value(_autoAjuste),
      capaCentralizar: Value(_centralizar),
      observacoes: Value(_t(_observacoes)),
    );
    try {
      if (_editando) {
        await banco.atualizarObra(widget.obra!.id, dados);
      } else {
        await banco.inserirObra(dados);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível salvar a obra: $e';
        });
      }
    }
  }

  Widget _campo(String chave, String rotulo, TextEditingController c,
          {double largura = 140, bool numero = false, String? Function(String?)? validar, int? maxLen}) =>
      SizedBox(
        width: largura,
        child: TextFormField(
          key: Key(chave),
          controller: c,
          keyboardType: numero ? TextInputType.number : null,
          inputFormatters: numero ? [FilteringTextInputFormatter.digitsOnly] : null,
          maxLength: maxLen,
          decoration: InputDecoration(labelText: rotulo, counterText: ''),
          validator: validar,
        ),
      );

  Widget _lista(String chave, {double largura = 520, bool comLupa = true, Widget? extra}) {
    final l = _listas[chave]!;
    return SizedBox(
      width: largura,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: l.larguraCodigo,
          child: TextFormField(
            key: Key('campo_${chave}_codigo'),
            controller: l.codigo,
            decoration: const InputDecoration(labelText: 'Cód.'),
          ),
        ),
        if (comLupa)
          IconButton(key: Key('lupa_$chave'), tooltip: 'Escolher ${l.rotulo}', icon: const Icon(Icons.search), onPressed: () => _lupa(l)),
        const SizedBox(width: 4),
        Expanded(
          child: TextFormField(
            key: Key('campo_${chave}_descricao'),
            controller: l.descricao,
            decoration: InputDecoration(labelText: l.rotulo),
          ),
        ),
      ]),
    );
  }

  Widget _blocoCapa(ColorScheme cores) => Container(
        width: 180,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(border: Border.all(color: cores.outlineVariant)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Capa', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(children: [
            IconButton(key: const Key('escolher_capa_obra'), tooltip: 'Escolher capa', icon: const Icon(Icons.folder_open), onPressed: _escolherCapa),
            IconButton(
                key: const Key('remover_capa_obra'),
                tooltip: 'Remover capa',
                icon: Icon(Icons.close, color: cores.error),
                onPressed: () => setState(() => _capa = null)),
          ]),
          Container(
            height: 170,
            width: double.infinity,
            color: cores.surfaceContainerHighest,
            child: _capa == null
                ? null
                : Image.memory(_capa!,
                    key: const Key('imagem_capa_obra'),
                    fit: _autoAjuste ? BoxFit.contain : BoxFit.none,
                    alignment: _centralizar ? Alignment.center : Alignment.topLeft,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
          ),
          CheckboxListTile(
            key: const Key('capa_auto_ajuste'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Auto-ajuste > ${_autoAjuste ? 'SIM' : 'NÃO'}'),
            value: _autoAjuste,
            onChanged: (v) => setState(() => _autoAjuste = v ?? true),
          ),
          CheckboxListTile(
            key: const Key('capa_centralizar'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Centralizar > ${_centralizar ? 'SIM' : 'NÃO'}'),
            value: _centralizar,
            onChanged: (v) => setState(() => _centralizar = v ?? true),
          ),
        ]),
      );

  Widget _abaDados(ThemeData tema) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Wrap(spacing: 16, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.start, children: [
            _campo('campo_tombo_obra', 'Tombo Obra', _tombo,
                largura: 130,
                numero: true,
                validar: (v) => int.tryParse((v ?? '').trim()) == null ? 'Informe o tombo' : null),
            _campo('campo_isbn_obra', 'ISBN', _isbn, largura: 200),
            SizedBox(
              width: 180,
              child: CheckboxListTile(
                key: const Key('campo_no_acervo'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_noAcervo ? 'NO ACERVO' : 'FORA DO ACERVO',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _noAcervo ? Colors.green.shade800 : tema.colorScheme.error)),
                value: _noAcervo,
                onChanged: (v) => setState(() => _noAcervo = v ?? true),
              ),
            ),
          ]),
          _lista('tipo', largura: 560),
          Wrap(spacing: 16, runSpacing: 4, children: [
            SizedBox(
              width: 460,
              child: TextFormField(
                key: const Key('campo_titulo_obra'),
                controller: _titulo,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o título da obra' : null,
              ),
            ),
            _campo('campo_subtitulo_obra', 'SubTítulo', _subtitulo, largura: 360),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: [
            SizedBox(
              width: 580,
              child: Wrap(spacing: 12, runSpacing: 4, children: [
                _campo('campo_edicao_obra', 'Edição', _edicao, largura: 80),
                _campo('campo_ref_edicao_obra', 'Referência de Edição', _refEdicao, largura: 230),
                _campo('campo_ano_obra', 'Ano', _ano, largura: 80, numero: true, maxLen: 4),
                _campo('campo_dias_obra', 'Dias Previsão', _dias, largura: 120, numero: true),
                _lista('classif', largura: 580),
                _campo('campo_cod_classificacao', 'Cód. Classificação', _codClassificacao, largura: 170),
                _campo('campo_cod_autor', 'Cód. Autor', _codAutor, largura: 140),
                _campo('campo_tomo_obra', 'Tomo', _tomo, largura: 80),
                _campo('campo_volume_obra', 'Volume', _volume, largura: 80),
                _campo('campo_exemplar_obra', 'Exemplar', _exemplar, largura: 90, numero: true),
                _campo('campo_faixa_etaria', 'Faixa Etária', _faixa, largura: 100),
                _campo('campo_paginas_obra', 'Nro. Págs', _paginas, largura: 100, numero: true),
                _campo('campo_serie_obra', 'Série', _serie, largura: 580),
                _lista('colecao', largura: 580),
                _lista('idioma', largura: 580),
                _lista('editora', largura: 580),
                _campo('campo_editora_complemento', 'Complemento da editora', _editoraComplemento, largura: 580),
                _lista('categoria', largura: 420),
                _campo('campo_valor_obra', 'Valor (R\$)', _valor,
                    largura: 140,
                    validar: (v) => (v ?? '').trim().isEmpty || centavosDeTexto(v!) != null ? null : 'Valor inválido'),
                _lista('localizacao', largura: 340),
                _lista('situacao', largura: 340),
              ]),
            ),
            _blocoCapa(tema.colorScheme),
          ]),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erro!, key: const Key('erro_obra'), style: TextStyle(color: tema.colorScheme.error)),
            ),
        ],
      );

  Widget _abaObservacoes() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: const Key('campo_observacoes_obra'),
            controller: _observacoes,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(labelText: 'Observações', alignLabelWithHint: true),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editando ? 'Alterando obra' : 'Incluindo obra'),
          actions: [
            if (_editando)
              IconButton(key: const Key('excluir_obra_form'), tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Dados da obra'), Tab(text: 'Observações')]),
        ),
        body: Form(key: _form, child: TabBarView(children: [_abaDados(tema), _abaObservacoes()])),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              FilledButton(key: const Key('botao_salvar_obra'), onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
            ]),
          ),
        ),
      ),
    );
  }
}
