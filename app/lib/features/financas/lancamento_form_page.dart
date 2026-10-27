import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/arquivos.dart';
import '../../core/formatos.dart';
import '../../core/lancamento_calculo.dart';
import '../../data/local/banco.dart';
import '../auth/widgets_auth.dart';
import 'contas_page.dart';

/// Abre o formulario de lancamento (despesa ou receita). Devolve true se salvou.
Future<bool?> abrirFormularioLancamento(BuildContext context, {String tipo = 'despesa', DateTime? hoje, Lancamento? lancamento}) =>
    Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => LancamentoFormPage(tipo: tipo, hoje: hoje, lancamento: lancamento)));

/// Lancamento de despesa/receita: descricao, valor (total, se parcelado), vencimento,
/// conta/cartao, categoria, repeticao (fixa ou parcelada), observacao, anexos e tags.
class LancamentoFormPage extends ConsumerStatefulWidget {
  const LancamentoFormPage({super.key, this.tipo = 'despesa', this.hoje, this.lancamento});
  final String tipo;
  final Lancamento? lancamento; // != null: edita este lancamento
  final DateTime? hoje; // para testes

  @override
  ConsumerState<LancamentoFormPage> createState() => _LancamentoFormPageState();
}

class _LancamentoFormPageState extends ConsumerState<LancamentoFormPage> {
  final _form = GlobalKey<FormState>();
  final _descricao = TextEditingController();
  final _valor = TextEditingController();
  final _vezes = TextEditingController(text: '2');
  final _observacao = TextEditingController();
  final _tagTexto = TextEditingController();
  late String _tipo;
  late DateTime _data;
  String _repeticao = 'unica'; // unica | fixa | parcelada
  bool _pago = false;
  String? _contaId;
  String? _categoriaId;
  final _tags = <String>[];
  final _anexos = <ArquivoParaAnexar>[];
  String? _erro;
  bool _salvando = false;

  final _existentes = <Anexo>[]; // anexos ja gravados (so na edicao)
  final _removidos = <String>{};
  bool _aplicarSeguintes = false;
  int _seguintes = 0;
  List<Conta> _contas = const [];
  List<Categoria> _categorias = const [];
  bool _carregado = false;

  @override
  void initState() {
    super.initState();
    final l = widget.lancamento;
    _tipo = l?.tipo ?? widget.tipo;
    final h = widget.hoje ?? DateTime.now();
    _data = l == null ? DateTime(h.year, h.month, h.day) : DateTime(l.dia.year, l.dia.month, l.dia.day);
    if (l != null) {
      _descricao.text = l.descricao;
      _valor.text = (l.valorCentavos / 100).toStringAsFixed(2).replaceAll('.', ',');
      _observacao.text = l.observacao ?? '';
      _pago = l.status == 'pago';
      _categoriaId = l.categoriaId;
      _tags.addAll(tagsDoTexto(l.tags));
    }
    _carregar();
  }

  Future<void> _carregar() async {
    final banco = ref.read(bancoProvider);
    final contas = (await (banco.select(banco.contas)..where((c) => c.excluidoEm.isNull())).get())
        .where((c) => c.titularidade != 'externa')
        .toList();
    final categorias = await (banco.select(banco.categorias)..where((c) => c.excluidoEm.isNull())).get();
    final l = widget.lancamento;
    final existentes = l == null ? <Anexo>[] : await banco.observarAnexos(l.id).first;
    final seguintes = l == null ? 0 : await banco.contarSeguintesDaSerie(l);
    if (!mounted) return;
    setState(() {
      _contas = contas;
      _categorias = categorias;
      _contaId = l != null && contas.any((c) => c.id == l.contaId) ? l.contaId : (l != null || contas.isEmpty ? null : contas.first.id);
      _existentes.addAll(existentes);
      _seguintes = seguintes;
      _carregado = true;
    });
  }

  @override
  void dispose() {
    for (final c in [_descricao, _valor, _vezes, _observacao, _tagTexto]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _despesa => _tipo == 'despesa';
  bool get _editando => widget.lancamento != null;
  bool get _daSerie => widget.lancamento?.grupoParcelas != null;

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Vencimento',
    );
    if (d != null) setState(() => _data = d);
  }

  void _adicionarTag([String? texto]) {
    for (final bruto in (texto ?? _tagTexto.text).split(',')) {
      final t = normalizarTag(bruto);
      if (t.isEmpty || _tags.contains(t)) continue;
      if (_tags.length >= maximoTags) {
        setState(() => _erro = 'Use no máximo $maximoTags tags.');
        break;
      }
      _tags.add(t);
    }
    setState(() => _tagTexto.clear());
  }

  Future<void> _anexar() async {
    final novos = await ref.read(escolhedorArquivosProvider)();
    if (novos.isEmpty) return;
    String? aviso;
    setState(() {
      for (final a in novos) {
        if (_anexos.length + _existentes.where((e) => !_removidos.contains(e.id)).length >= maximoAnexos) {
          aviso = 'Use no máximo $maximoAnexos anexos.';
          break;
        }
        if (a.bytes.length > maximoBytesAnexo) {
          aviso = '"${a.nome}" passa de ${formatarTamanho(maximoBytesAnexo)} e não foi anexado.';
          continue;
        }
        _anexos.add(a);
      }
      _erro = aviso;
    });
  }

  Future<void> _novaCategoria() async {
    final c = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_despesa ? 'Nova categoria de despesa' : 'Nova categoria de receita'),
        content: TextField(key: const Key('campo_nova_categoria'), controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nome da categoria')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(key: const Key('confirmar_categoria'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Criar')),
        ],
      ),
    );
    if (nome == null || nome.length < 2) return;
    final banco = ref.read(bancoProvider);
    final id = await banco.inserirCategoria(nome: nome, tipo: _tipo);
    final cats = await (banco.select(banco.categorias)..where((x) => x.excluidoEm.isNull())).get();
    if (!mounted) return;
    setState(() {
      _categorias = cats;
      _categoriaId = id;
    });
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (_tagTexto.text.trim().isNotEmpty) _adicionarTag();
    if (!(_form.currentState?.validate() ?? false)) return;
    final centavos = centavosDeTexto(_valor.text)!;
    final vezes = _repeticao == 'unica' ? 1 : int.parse(_vezes.text.trim());
    setState(() => _salvando = true);
    try {
      if (_editando) {
        await ref.read(bancoProvider).atualizarLancamento(
              widget.lancamento!,
              descricao: _descricao.text.trim(),
              valorCentavos: centavos,
              dia: _data,
              contaId: _contaId!,
              categoriaId: _categoriaId,
              tags: tagsParaTexto(_tags),
              observacao: _observacao.text.trim().isEmpty ? null : _observacao.text.trim(),
              pago: _pago,
              aplicarNosSeguintes: _aplicarSeguintes,
              novosAnexos: List.of(_anexos),
              anexosRemovidos: _removidos.toList(),
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lançamento atualizado.')));
        Navigator.of(context).pop(true);
        return;
      }
      await ref.read(bancoProvider).lancar(
            descricao: _descricao.text.trim(),
            valorCentavos: centavos,
            tipo: _tipo,
            vencimento: _data,
            contaId: _contaId!,
            categoriaId: _categoriaId,
            repeticao: _repeticao,
            vezes: vezes,
            pago: _pago,
            tags: tagsParaTexto(_tags),
            observacao: _observacao.text.trim().isEmpty ? null : _observacao.text.trim(),
            anexos: List.of(_anexos),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_repeticao == 'unica'
              ? (_despesa ? 'Despesa lançada.' : 'Receita lançada.')
              : '$vezes lançamentos criados.')));
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String? _validarValor(String? v) {
    final c = centavosDeTexto(v ?? '');
    if (c == null) return 'Informe o valor';
    if (c <= 0) return 'O valor deve ser maior que zero';
    return null;
  }

  String? _validarVezes(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (_repeticao == 'parcelada') {
      if (n == null || n < 2 || n > 120) return 'Informe de 2 a 120 parcelas';
    } else if (_repeticao == 'fixa') {
      if (n == null || n < 2 || n > 60) return 'Informe de 2 a 60 meses';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categorias.where((c) => c.tipo == _tipo).toList();
    if (_categoriaId != null && !cats.any((c) => c.id == _categoriaId)) _categoriaId = null;
    final centavos = centavosDeTexto(_valor.text);
    final vezes = int.tryParse(_vezes.text.trim());
    final previa = (_repeticao == 'parcelada' && centavos != null && centavos > 0 && vezes != null && vezes >= 2 && vezes <= 120)
        ? dividirParcelas(centavos, vezes)
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? (_despesa ? 'Editar despesa' : 'Editar receita') : (_despesa ? 'Nova despesa' : 'Nova receita'))),
      body: !_carregado
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (!_editando) SegmentedButton<String>(
                        key: const Key('campo_tipo_lancamento'),
                        segments: const [
                          ButtonSegment(value: 'despesa', label: Text('Despesa')),
                          ButtonSegment(value: 'receita', label: Text('Receita')),
                        ],
                        selected: {_tipo},
                        onSelectionChanged: (s) => setState(() => _tipo = s.first),
                      ),
                      if (!_editando) const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('campo_descricao'),
                        controller: _descricao,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Descrição',
                          helperText: _despesa
                              ? 'Algo que facilite achar a despesa na listagem. Ex.: Aluguel da casa, Telefone, Energia'
                              : 'Algo que facilite achar a receita na listagem. Ex.: Salário, Freela',
                          helperMaxLines: 2,
                        ),
                        validator: (v) => (v ?? '').trim().length < 2 ? 'Informe a descrição' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('campo_valor'),
                        controller: _valor,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,R\$ ]'))],
                        decoration: InputDecoration(
                          labelText: _editando
                              ? (widget.lancamento!.parcelaTotal != null ? 'Valor desta parcela (R\$)' : 'Valor (R\$)')
                              : (_repeticao == 'parcelada' ? 'Valor total (R\$)' : 'Valor (R\$)'),
                          helperText: !_editando && _repeticao == 'parcelada' ? 'Informe o valor total; ele será dividido nas parcelas' : null,
                        ),
                        validator: _validarValor,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        key: const Key('campo_data'),
                        onTap: _escolherData,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                              labelText: _despesa ? 'Data de vencimento' : 'Data de recebimento',
                              suffixIcon: const Icon(Icons.calendar_today_outlined)),
                          child: Text(formatarData(_data), key: const Key('texto_data')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const Key('campo_conta'),
                        value: _contaId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: _despesa ? 'Conta/cartão para pagar' : 'Conta/cartão para receber'),
                        items: [
                          for (final c in _contas)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                  '${tituloDaConta(c) == c.nome ? c.nome : '${tituloDaConta(c)} · ${c.nome}'}  (${nomeDoTipoConta(c.tipo)})',
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        validator: (v) => v == null ? 'Escolha a conta ou cartão' : null,
                        onChanged: (v) => setState(() => _contaId = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        key: const Key('campo_categoria'),
                        value: _categoriaId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Categoria', helperText: 'Agrupa despesas parecidas: aluguel, alimentação...'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Sem categoria')),
                          for (final c in cats) DropdownMenuItem<String?>(value: c.id, child: Text(c.nome)),
                          const DropdownMenuItem<String?>(value: '__nova__', child: Text('+ Nova categoria…')),
                        ],
                        onChanged: (v) {
                          if (v == '__nova__') {
                            _novaCategoria();
                          } else {
                            setState(() => _categoriaId = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      if (!_editando)
                      DropdownButtonFormField<String>(
                        key: const Key('campo_repetir'),
                        value: _repeticao,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Repetir', helperText: 'Use para despesa fixa ou parcelada'),
                        items: const [
                          DropdownMenuItem(value: 'unica', child: Text('Não repetir')),
                          DropdownMenuItem(value: 'fixa', child: Text('Fixa (todo mês)')),
                          DropdownMenuItem(value: 'parcelada', child: Text('Parcelada')),
                        ],
                        onChanged: (v) => setState(() {
                          _repeticao = v ?? 'unica';
                          _vezes.text = _repeticao == 'fixa' ? '12' : '2';
                        }),
                      ),
                      if (_editando && _daSerie) ...[
                        Text(
                          widget.lancamento!.parcelaTotal != null
                              ? 'Parcela ${widget.lancamento!.parcelaNumero} de ${widget.lancamento!.parcelaTotal}'
                              : 'Despesa fixa: parte de uma série mensal',
                          key: const Key('info_serie'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (_seguintes > 0)
                          CheckboxListTile(
                            key: const Key('campo_aplicar_seguintes'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text('Aplicar conta, categoria, tags e observação também aos $_seguintes lançamentos seguintes'),
                            value: _aplicarSeguintes,
                            onChanged: (v) => setState(() => _aplicarSeguintes = v ?? false),
                          ),
                      ],
                      if (_repeticao != 'unica') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('campo_vezes'),
                          controller: _vezes,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: _repeticao == 'parcelada' ? 'Número de parcelas' : 'Por quantos meses'),
                          validator: _validarVezes,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                      if (previa != null)
                        Padding(
                          key: const Key('previa_parcelas'),
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            previa.toSet().length == 1
                                ? '${previa.length}x de ${formatarCentavos(previa.first)}'
                                : '${previa.length} parcelas: ${formatarCentavos(previa.first)} (primeiras) e ${formatarCentavos(previa.last)} (demais)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (_repeticao == 'unica')
                        CheckboxListTile(
                          key: const Key('campo_pago'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(_despesa ? 'Já foi paga' : 'Já foi recebida'),
                          value: _pago,
                          onChanged: (v) => setState(() => _pago = v ?? false),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('campo_observacao'),
                        controller: _observacao,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 500,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Observação (opcional)',
                          helperText: 'Método de pagamento, valor dos juros, detalhes extras',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _secaoAnexos(context),
                      const SizedBox(height: 16),
                      _secaoTags(context),
                      if (_erro != null) ...[
                        const SizedBox(height: 12),
                        KeyedSubtree(key: const Key('erro_lancamento'), child: CaixaMensagem(texto: _erro!)),
                      ],
                      const SizedBox(height: 20),
                      KeyedSubtree(
                        key: const Key('botao_salvar_lancamento'),
                        child: BotaoPrincipal(
                            texto: _editando ? 'Salvar alterações' : (_despesa ? 'Lançar despesa' : 'Lançar receita'), enviando: _salvando, aoPressionar: _salvar),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _secaoAnexos(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Anexos (opcional)', style: Theme.of(context).textTheme.titleSmall)),
        OutlinedButton.icon(
          key: const Key('botao_anexar'),
          onPressed: _anexar,
          icon: const Icon(Icons.attach_file),
          label: const Text('Anexar arquivo'),
        ),
      ]),
      Text('Comprovante, cupom… PDF, foto ou texto, até ${formatarTamanho(maximoBytesAnexo)} cada. Pode anexar mais de um.',
          style: Theme.of(context).textTheme.bodySmall),
      for (final e in _existentes)
        ListTile(
          key: Key('anexo_existente_${e.id}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon((e.tipoMime ?? '').startsWith('image/') ? Icons.image_outlined : Icons.description_outlined),
          title: Text(e.nomeArquivo,
              overflow: TextOverflow.ellipsis,
              style: _removidos.contains(e.id) ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
          subtitle: Text(_removidos.contains(e.id) ? 'Será removido ao salvar' : formatarTamanho(e.tamanhoBytes)),
          trailing: IconButton(
            key: Key('remover_anexo_existente_${e.id}'),
            tooltip: _removidos.contains(e.id) ? 'Desfazer' : 'Remover anexo',
            icon: Icon(_removidos.contains(e.id) ? Icons.undo : Icons.close),
            onPressed: () => setState(() => _removidos.contains(e.id) ? _removidos.remove(e.id) : _removidos.add(e.id)),
          ),
        ),
      for (var i = 0; i < _anexos.length; i++)
        ListTile(
          key: Key('anexo_$i'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon((_anexos[i].tipoMime ?? '').startsWith('image/') ? Icons.image_outlined : Icons.description_outlined),
          title: Text(_anexos[i].nome, overflow: TextOverflow.ellipsis),
          subtitle: Text(formatarTamanho(_anexos[i].bytes.length)),
          trailing: IconButton(
            key: Key('remover_anexo_$i'),
            tooltip: 'Remover anexo',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _anexos.removeAt(i)),
          ),
        ),
    ]);
  }

  Widget _secaoTags(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        key: const Key('campo_tags'),
        controller: _tagTexto,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Tags (opcional)',
          helperText: 'Complementam a categoria. Digite e toque em Adicionar (ou Enter). Ex.: viagem, reembolsável',
          helperMaxLines: 2,
          suffixIcon: IconButton(key: const Key('botao_add_tag'), tooltip: 'Adicionar tag', icon: const Icon(Icons.add), onPressed: _adicionarTag),
        ),
        onSubmitted: (_) => _adicionarTag(),
      ),
      if (_tags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final t in _tags)
              InputChip(
                key: Key('tag_$t'),
                label: Text('#$t'),
                onDeleted: () => setState(() => _tags.remove(t)),
              ),
          ]),
        ),
    ]);
  }
}
