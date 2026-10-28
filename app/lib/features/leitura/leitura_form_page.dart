import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/arquivos.dart';
import '../../core/formatos.dart';
import '../../core/leitura_calculo.dart';
import '../../data/local/banco.dart';
import 'nota_tema.dart';

/// Abre a ficha de leitura (nova ou edicao).
Future<void> abrirFichaLeitura(BuildContext context, {Leitura? leitura}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LeituraFormPage(leitura: leitura)));

/// Ficha de leitura: capa, titulo, autor, datas de inicio e fim, formato do livro (fisico/digital),
/// classificacao dos temas abordados, frase favorita e personagens principais.
class LeituraFormPage extends ConsumerStatefulWidget {
  const LeituraFormPage({super.key, this.leitura});

  final Leitura? leitura;

  @override
  ConsumerState<LeituraFormPage> createState() => _LeituraFormPageState();
}

class _LeituraFormPageState extends ConsumerState<LeituraFormPage> {
  final _form = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _autor = TextEditingController();
  final _frase = TextEditingController();
  final _personagens = TextEditingController();
  Uint8List? _capa;
  DateTime? _inicio;
  DateTime? _fim;
  String _formato = 'fisico';
  final Map<String, int> _notas = {for (final t in temasLeitura) t.codigo: 0};
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.leitura != null;

  @override
  void initState() {
    super.initState();
    final l = widget.leitura;
    if (l != null) {
      _titulo.text = l.titulo;
      _autor.text = l.autor ?? '';
      _frase.text = l.fraseFavorita ?? '';
      _personagens.text = l.personagens ?? '';
      _capa = l.capa;
      _inicio = l.iniciouEm;
      _fim = l.terminouEm;
      _formato = formatosLivro.containsKey(l.formato) ? l.formato : 'fisico';
      for (final t in temasLeitura) {
        _notas[t.codigo] = notaDoTema(l, t.codigo).clamp(0, notaMaximaTema);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_titulo, _autor, _frase, _personagens]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opcional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _escolherCapa() async {
    final arquivos = await ref.read(escolhedorArquivosProvider)();
    final imagens = arquivos.where((a) => (a.tipoMime ?? '').startsWith('image/'));
    if (imagens.isNotEmpty && mounted) setState(() => _capa = imagens.first.bytes);
  }

  Future<DateTime?> _escolherData(DateTime? atual) => showDatePicker(
      context: context, initialDate: atual ?? DateTime.now(), firstDate: DateTime(1900), lastDate: DateTime(2100));

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir ficha de leitura?'),
        content: Text('"${widget.leitura!.titulo}" será excluída.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
              key: const Key('confirmar_exclusao_leitura'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(bancoProvider).excluirLeitura(widget.leitura!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (!_form.currentState!.validate()) return;
    if (_inicio != null && _fim != null && _fim!.isBefore(_inicio!)) {
      setState(() => _erro = 'A data em que terminou não pode ser antes da data em que iniciou.');
      return;
    }
    setState(() => _salvando = true);
    final banco = ref.read(bancoProvider);
    try {
      if (_editando) {
        await banco.atualizarLeitura(widget.leitura!.id,
            titulo: _titulo.text.trim(),
            autor: _opcional(_autor),
            capa: _capa,
            iniciouEm: _inicio,
            terminouEm: _fim,
            formato: _formato,
            notaDrama: _notas['drama']!,
            notaFantasia: _notas['fantasia']!,
            notaRomance: _notas['romance']!,
            notaReflexao: _notas['reflexao']!,
            fraseFavorita: _opcional(_frase),
            personagens: _opcional(_personagens));
      } else {
        await banco.inserirLeitura(
            titulo: _titulo.text.trim(),
            autor: _opcional(_autor),
            capa: _capa,
            iniciouEm: _inicio,
            terminouEm: _fim,
            formato: _formato,
            notaDrama: _notas['drama']!,
            notaFantasia: _notas['fantasia']!,
            notaRomance: _notas['romance']!,
            notaReflexao: _notas['reflexao']!,
            fraseFavorita: _opcional(_frase),
            personagens: _opcional(_personagens));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível salvar a ficha: $e';
        });
      }
    }
  }

  Widget _secao(String texto) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _campoData(String chave, String rotulo, DateTime? valor, ValueChanged<DateTime?> aoMudar) => InkWell(
        key: Key(chave),
        onTap: () async {
          final d = await _escolherData(valor);
          if (d != null) aoMudar(DateTime(d.year, d.month, d.day));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: rotulo,
            suffixIcon: valor != null
                ? IconButton(icon: const Icon(Icons.close), tooltip: 'Remover', onPressed: () => aoMudar(null))
                : const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(valor == null ? 'Sem data' : formatarData(valor)),
        ),
      );

  Widget _blocoCapa(ColorScheme cores) => InkWell(
        key: const Key('campo_capa_leitura'),
        onTap: _escolherCapa,
        child: Container(
          width: 130,
          height: 190,
          decoration: BoxDecoration(
            color: cores.primaryContainer,
            border: Border.all(color: cores.outlineVariant),
          ),
          child: _capa == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 36, color: cores.onPrimaryContainer),
                  const SizedBox(height: 6),
                  Text('Capa do livro', style: TextStyle(color: cores.onPrimaryContainer)),
                ])
              : Stack(fit: StackFit.expand, children: [
                  Image.memory(_capa!,
                      fit: BoxFit.cover,
                      key: const Key('imagem_capa_leitura'),
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton.filledTonal(
                      key: const Key('remover_capa_leitura'),
                      tooltip: 'Remover capa',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _capa = null),
                    ),
                  ),
                ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ficha de Leitura'), actions: [
        if (_editando)
          IconButton(
            key: const Key('excluir_leitura_form'),
            tooltip: 'Excluir',
            icon: const Icon(Icons.delete_outline),
            onPressed: _excluir,
          ),
      ]),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Wrap(spacing: 16, runSpacing: 12, children: [
              _blocoCapa(tema.colorScheme),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 240, maxWidth: 520),
                child: Column(children: [
                  TextFormField(
                    key: const Key('campo_titulo_leitura'),
                    controller: _titulo,
                    minLines: 1,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Título'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o título do livro' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('campo_autor_leitura'),
                    controller: _autor,
                    minLines: 1,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Autor'),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                  width: 190,
                  child: _campoData('campo_inicio_leitura', 'Iniciou a leitura', _inicio, (d) => setState(() => _inicio = d))),
              const Icon(Icons.arrow_forward),
              SizedBox(
                  width: 190,
                  child: _campoData('campo_fim_leitura', 'Terminou a leitura', _fim, (d) => setState(() => _fim = d))),
            ]),
            _secao('Livro'),
            Wrap(spacing: 8, children: [
              for (final e in formatosLivro.entries)
                ChoiceChip(
                  key: Key('formato_${e.key}'),
                  avatar: Icon(e.key == 'fisico' ? Icons.menu_book_outlined : Icons.tablet_android_outlined, size: 18),
                  label: Text(e.value),
                  selected: _formato == e.key,
                  onSelected: (_) => setState(() => _formato = e.key),
                ),
            ]),
            _secao('Classificação dos temas abordados'),
            for (final t in temasLeitura)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 100, child: Text(t.nome.toUpperCase(), style: tema.textTheme.labelLarge)),
                  NotaTema(tema: t, nota: _notas[t.codigo]!, onChanged: (n) => setState(() => _notas[t.codigo] = n)),
                ]),
              ),
            _secao('Frase favorita'),
            TextFormField(
              key: const Key('campo_frase_leitura'),
              controller: _frase,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'A frase que mais marcou você'),
            ),
            _secao('Personagens principais'),
            TextFormField(
              key: const Key('campo_personagens_leitura'),
              controller: _personagens,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'Um personagem por linha'),
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, key: const Key('erro_leitura'), style: TextStyle(color: tema.colorScheme.error)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            FilledButton(
                key: const Key('botao_salvar_leitura'), onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
          ]),
        ),
      ),
    );
  }
}
