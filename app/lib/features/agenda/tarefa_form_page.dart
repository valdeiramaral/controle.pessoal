import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatos.dart';
import '../../core/lancamento_calculo.dart' show tagsDoTexto, tagsParaTexto;
import '../../core/tarefas_calculo.dart';
import '../../data/local/banco.dart';

/// Abre o cadastro de tarefa (nova ou edicao).
Future<void> abrirFormularioTarefa(BuildContext context, {Tarefa? tarefa, DateTime? hoje}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TarefaFormPage(tarefa: tarefa, hoje: hoje)));

/// Cadastro da tarefa: projeto, nome, descricao, prioridade (padrao Media, com tag colorida),
/// data, estimativa, responsavel, etapa, dados complementares e o que fazer depois de salvar.
class TarefaFormPage extends ConsumerStatefulWidget {
  const TarefaFormPage({super.key, this.tarefa, this.hoje});

  final Tarefa? tarefa;
  final DateTime? hoje; // para testes

  @override
  ConsumerState<TarefaFormPage> createState() => _TarefaFormPageState();
}

class _TarefaFormPageState extends ConsumerState<TarefaFormPage> {
  final _form = GlobalKey<FormState>();
  final _projeto = TextEditingController();
  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  final _estimativa = TextEditingController();
  final _responsavel = TextEditingController();
  final _observacoes = TextEditingController();
  final _tags = TextEditingController();
  String _prioridade = prioridadePadraoTarefa;
  String _etapa = etapaPadraoTarefa;
  String _unidade = 'minutos';
  DateTime? _prazo;
  String _depois = 'fechar'; // fechar | ver | nova
  List<String> _projetos = const [];
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.tarefa != null;

  @override
  void initState() {
    super.initState();
    final t = widget.tarefa;
    if (t != null) {
      _projeto.text = t.projeto ?? '';
      _nome.text = t.titulo;
      _descricao.text = t.descricao ?? '';
      _prioridade = prioridadesTarefa.containsKey(t.prioridade) ? t.prioridade : prioridadePadraoTarefa;
      _etapa = etapasTarefa.containsKey(t.etapa) ? t.etapa : etapaPadraoTarefa;
      _prazo = t.prazo == null ? null : DateTime(t.prazo!.year, t.prazo!.month, t.prazo!.day);
      _estimativa.text = t.estimativa == null ? '' : '${t.estimativa}';
      _unidade = unidadesEstimativa.containsKey(t.estimativaUnidade) ? t.estimativaUnidade : 'minutos';
      _responsavel.text = t.responsavel ?? '';
      _observacoes.text = t.observacoes ?? '';
      _tags.text = tagsDoTexto(t.tags).join(', ');
    }
    ref.read(bancoProvider).projetosDeTarefas().then((p) {
      if (mounted) setState(() => _projetos = p);
    });
  }

  @override
  void dispose() {
    for (final c in [_projeto, _nome, _descricao, _estimativa, _responsavel, _observacoes, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherData() async {
    final base = _prazo ?? widget.hoje ?? DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: base, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => _prazo = DateTime(d.year, d.month, d.day));
  }

  String? _opcional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _limpar() {
    for (final c in [_nome, _descricao, _estimativa, _observacoes, _tags]) {
      c.clear();
    }
    setState(() {
      _prioridade = prioridadePadraoTarefa;
      _etapa = etapaPadraoTarefa;
      _prazo = null;
      _erro = null;
    });
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _salvando = true);
    final banco = ref.read(bancoProvider);
    final estimativa = int.tryParse(_estimativa.text.trim());
    final tags = tagsParaTexto(_tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
    try {
      final String id;
      if (_editando) {
        id = widget.tarefa!.id;
        await banco.atualizarTarefa(id,
            titulo: _nome.text.trim(),
            descricao: _opcional(_descricao),
            projeto: _opcional(_projeto),
            prazo: _prazo,
            prioridade: _prioridade,
            etapa: _etapa,
            estimativa: estimativa,
            estimativaUnidade: _unidade,
            responsavel: _opcional(_responsavel),
            observacoes: _opcional(_observacoes),
            tags: tags);
      } else {
        id = await banco.inserirTarefa(
            titulo: _nome.text.trim(),
            descricao: _opcional(_descricao),
            projeto: _opcional(_projeto),
            prazo: _prazo,
            prioridade: _prioridade,
            etapa: _etapa,
            estimativa: estimativa,
            estimativaUnidade: _unidade,
            responsavel: _opcional(_responsavel),
            observacoes: _opcional(_observacoes),
            tags: tags);
      }
      if (!mounted) return;
      switch (_depois) {
        case 'ver':
          final salva = await banco.tarefaPorId(id);
          if (!mounted) return;
          if (salva != null) {
            await Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => TarefaFormPage(tarefa: salva, hoje: widget.hoje)));
          } else {
            Navigator.pop(context);
          }
        case 'nova':
          if (_editando) {
            Navigator.pop(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarefa salva. Cadastre a próxima.')));
            _limpar();
            setState(() => _salvando = false);
          }
        default:
          Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível salvar a tarefa: $e';
        });
      }
    }
  }

  Widget _rotulo(String texto) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar tarefa' : 'Nova tarefa')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Autocomplete<String>(
              optionsBuilder: (v) => _projetos.where((p) => p.toLowerCase().contains(v.text.toLowerCase())),
              initialValue: TextEditingValue(text: _projeto.text),
              onSelected: (v) => _projeto.text = v,
              fieldViewBuilder: (context, controle, foco, _) => TextFormField(
                key: const Key('campo_projeto_tarefa'),
                controller: controle,
                focusNode: foco,
                decoration: const InputDecoration(labelText: 'Projeto (opcional)', helperText: 'Agrupa tarefas. Ex.: Reforma da casa'),
                onChanged: (v) => _projeto.text = v,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('campo_nome_tarefa'),
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome', helperText: 'Dica: pressione Enter para salvar'),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _salvar(),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome da tarefa' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('campo_descricao_tarefa'),
              controller: _descricao,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Descrição', alignLabelWithHint: true),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('campo_prioridade_tarefa'),
              initialValue: _prioridade,
              decoration: InputDecoration(
                labelText: 'Prioridade',
                helperText: 'Padrão: Média. A cor da tag organiza a sua agenda.',
                prefixIcon: Icon(Icons.flag, color: corDaPrioridade(_prioridade), key: Key('tag_prioridade_$_prioridade')),
              ),
              items: [
                for (final e in prioridadesTarefa.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Row(children: [
                      Icon(Icons.circle, size: 12, color: corDaPrioridade(e.key)),
                      const SizedBox(width: 8),
                      Text(e.value),
                    ]),
                  ),
              ],
              onChanged: (v) => setState(() => _prioridade = v ?? _prioridade),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 200,
                child: InkWell(
                  key: const Key('campo_data_tarefa'),
                  onTap: _escolherData,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Data',
                      suffixIcon: _prazo != null
                          ? IconButton(icon: const Icon(Icons.close), tooltip: 'Remover', onPressed: () => setState(() => _prazo = null))
                          : const Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(_prazo == null ? 'Sem data' : formatarData(_prazo!)),
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextFormField(
                  key: const Key('campo_estimativa_tarefa'),
                  controller: _estimativa,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Estimativa'),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  key: const Key('campo_unidade_tarefa'),
                  isExpanded: true,
                  initialValue: _unidade,
                  decoration: const InputDecoration(labelText: 'Unidade'),
                  items: [for (final e in unidadesEstimativa.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _unidade = v ?? _unidade),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('campo_responsavel_tarefa'),
              controller: _responsavel,
              decoration: const InputDecoration(labelText: 'Responsável (opcional)', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('campo_etapa_tarefa'),
              initialValue: _etapa,
              decoration: const InputDecoration(
                  labelText: 'Etapa', helperText: 'Não é obrigatório: sem escolher, a tarefa entra em "A fazer"', helperMaxLines: 2),
              items: [for (final e in etapasTarefa.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _etapa = v ?? _etapa),
            ),
            ExpansionTile(
              key: const Key('dados_complementares_tarefa'),
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('Dados complementares', style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              children: [
                TextFormField(
                  key: const Key('campo_observacoes_tarefa'),
                  controller: _observacoes,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Observações', alignLabelWithHint: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_tags_tarefa'),
                  controller: _tags,
                  decoration: const InputDecoration(labelText: 'Tags', helperText: 'Separe por vírgula. Ex.: casa, urgente'),
                ),
              ],
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, key: const Key('erro_tarefa'), style: TextStyle(color: tema.colorScheme.error)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(children: [
            Expanded(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                const Text('Após salvar:'),
                for (final e in const {'fechar': 'Fechar', 'ver': 'Ver tarefa', 'nova': 'Adicionar nova'}.entries)
                  ChoiceChip(
                    key: Key('depois_${e.key}'),
                    label: Text(e.value),
                    selected: _depois == e.key,
                    onSelected: (_) => setState(() => _depois = e.key),
                  ),
              ]),
            ),
            FilledButton(key: const Key('botao_salvar_tarefa'), onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
          ]),
        ),
      ),
    );
  }
}
