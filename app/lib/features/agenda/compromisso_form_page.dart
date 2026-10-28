import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatos.dart';
import '../../core/lancamento_calculo.dart' show tagsDoTexto, tagsParaTexto;
import '../../core/notificacoes.dart';
import '../../core/tarefas_calculo.dart';
import '../../data/local/banco.dart';

/// Abre o cadastro de compromisso (novo ou edicao).
Future<void> abrirFormularioCompromisso(BuildContext context, {Evento? evento, DateTime? hoje, DateTime? dataInicial}) =>
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CompromissoFormPage(evento: evento, hoje: hoje, dataInicial: dataInicial)));

/// Cadastro do compromisso, no mesmo molde da tarefa: projeto, nome, descricao, prioridade, data,
/// horario, local, participantes, lembrete, dados complementares e o que fazer depois de salvar.
class CompromissoFormPage extends ConsumerStatefulWidget {
  const CompromissoFormPage({super.key, this.evento, this.hoje, this.dataInicial});

  final Evento? evento;
  final DateTime? hoje; // para testes
  final DateTime? dataInicial; // novo compromisso ja nesse dia (o "+" da coluna do quadro)

  @override
  ConsumerState<CompromissoFormPage> createState() => _CompromissoFormPageState();
}

class _CompromissoFormPageState extends ConsumerState<CompromissoFormPage> {
  final _form = GlobalKey<FormState>();
  final _projeto = TextEditingController();
  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  final _local = TextEditingController();
  final _participantes = TextEditingController();
  final _observacoes = TextEditingController();
  final _comentarios = TextEditingController();
  final _link = TextEditingController();
  final _tags = TextEditingController();
  String _prioridade = prioridadePadraoTarefa;
  int _lembrete = 30;
  late DateTime _data;
  bool _diaInteiro = false;
  TimeOfDay _inicio = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? _fim;
  String _depois = 'fechar'; // fechar | ver | nova
  List<String> _projetos = const [];
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.evento != null;

  @override
  void initState() {
    super.initState();
    final h = widget.hoje ?? DateTime.now();
    final base = widget.dataInicial ?? h;
    _data = DateTime(base.year, base.month, base.day);
    final e = widget.evento;
    if (e != null) {
      _projeto.text = e.projeto ?? '';
      _nome.text = e.titulo;
      _descricao.text = e.notas ?? '';
      _local.text = e.local ?? '';
      _participantes.text = e.participantes ?? '';
      _observacoes.text = e.observacoes ?? '';
      _comentarios.text = e.comentarios ?? '';
      _link.text = e.link ?? '';
      _tags.text = tagsDoTexto(e.tags).join(', ');
      _prioridade = prioridadesTarefa.containsKey(e.prioridade) ? e.prioridade : prioridadePadraoTarefa;
      _lembrete = lembretesCompromisso.containsKey(e.lembreteMinutos) ? e.lembreteMinutos : 30;
      _data = DateTime(e.inicio.year, e.inicio.month, e.inicio.day);
      _diaInteiro = e.diaInteiro;
      _inicio = TimeOfDay(hour: e.inicio.hour, minute: e.inicio.minute);
      _fim = e.fim == null ? null : TimeOfDay(hour: e.fim!.hour, minute: e.fim!.minute);
    }
    ref.read(bancoProvider).projetosUsados().then((p) {
      if (mounted) setState(() => _projetos = p);
    });
  }

  @override
  void dispose() {
    for (final c in [_projeto, _nome, _descricao, _local, _participantes, _observacoes, _comentarios, _link, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  String _hora(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _escolherData() async {
    final d = await showDatePicker(context: context, initialDate: _data, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => _data = DateTime(d.year, d.month, d.day));
  }

  Future<void> _escolherHora({required bool inicio}) async {
    final t = await showTimePicker(context: context, initialTime: inicio ? _inicio : (_fim ?? _inicio));
    if (t != null) setState(() => inicio ? _inicio = t : _fim = t);
  }

  String? _opcional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _limpar() {
    for (final c in [_nome, _descricao, _local, _participantes, _observacoes, _comentarios, _link, _tags]) {
      c.clear();
    }
    setState(() {
      _prioridade = prioridadePadraoTarefa;
      _lembrete = 30;
      _diaInteiro = false;
      _fim = null;
      _erro = null;
    });
  }

  Future<void> _agendarLembrete(String id, String titulo, DateTime inicio, int minutos) async {
    final nid = ServicoNotificacoes.idNumerico(id);
    await ServicoNotificacoes.instancia.cancelar(nid);
    if (minutos <= 0 || _diaInteiro) return;
    await ServicoNotificacoes.instancia.agendar(
      id: nid,
      titulo: titulo,
      corpo: 'Começa às ${formatarDataHora(inicio)}',
      quando: inicio.subtract(Duration(minutes: minutos)),
    );
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (!_form.currentState!.validate()) return;
    final inicio = _diaInteiro
        ? DateTime(_data.year, _data.month, _data.day)
        : DateTime(_data.year, _data.month, _data.day, _inicio.hour, _inicio.minute);
    DateTime? fim;
    if (!_diaInteiro && _fim != null) {
      fim = DateTime(_data.year, _data.month, _data.day, _fim!.hour, _fim!.minute);
      if (!fim.isAfter(inicio)) {
        setState(() => _erro = 'O horário final precisa ser depois do inicial.');
        return;
      }
    }
    setState(() => _salvando = true);
    final banco = ref.read(bancoProvider);
    final tags = tagsParaTexto(_tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
    try {
      final String id;
      if (_editando) {
        id = widget.evento!.id;
        await banco.atualizarCompromisso(id,
            titulo: _nome.text.trim(),
            inicio: inicio,
            fim: fim,
            diaInteiro: _diaInteiro,
            local: _opcional(_local),
            notas: _opcional(_descricao),
            link: _opcional(_link),
            projeto: _opcional(_projeto),
            prioridade: _prioridade,
            participantes: _opcional(_participantes),
            observacoes: _opcional(_observacoes),
            comentarios: _opcional(_comentarios),
            tags: tags,
            lembreteMinutos: _lembrete);
      } else {
        id = await banco.inserirEvento(
            titulo: _nome.text.trim(),
            inicio: inicio,
            fim: fim,
            diaInteiro: _diaInteiro,
            local: _opcional(_local),
            notas: _opcional(_descricao),
            link: _opcional(_link),
            projeto: _opcional(_projeto),
            prioridade: _prioridade,
            participantes: _opcional(_participantes),
            observacoes: _opcional(_observacoes),
            comentarios: _opcional(_comentarios),
            tags: tags,
            lembreteMinutos: _lembrete);
      }
      await _agendarLembrete(id, _nome.text.trim(), inicio, _lembrete);
      if (!mounted) return;
      switch (_depois) {
        case 'ver':
          final salvo = await banco.compromissoPorId(id);
          if (!mounted) return;
          if (salvo != null) {
            await Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => CompromissoFormPage(evento: salvo, hoje: widget.hoje)));
          } else {
            Navigator.pop(context);
          }
        case 'nova':
          if (_editando) {
            Navigator.pop(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compromisso salvo. Cadastre o próximo.')));
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
          _erro = 'Não foi possível salvar o compromisso: $e';
        });
      }
    }
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir compromisso?'),
        content: Text('"${widget.evento!.titulo}" será excluído.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('confirmar_exclusao_compromisso'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ServicoNotificacoes.instancia.cancelar(ServicoNotificacoes.idNumerico(widget.evento!.id));
    await ref.read(bancoProvider).excluirEvento(widget.evento!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar compromisso' : 'Novo compromisso'), actions: [
        if (_editando)
          IconButton(key: const Key('excluir_compromisso_form'), tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
      ]),
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
                key: const Key('campo_projeto_compromisso'),
                controller: controle,
                focusNode: foco,
                decoration: const InputDecoration(labelText: 'Projeto (opcional)', helperText: 'Agrupa tarefas e compromissos'),
                onChanged: (v) => _projeto.text = v,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('campo_nome_compromisso'),
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome', helperText: 'Dica: pressione Enter para salvar'),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _salvar(),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome do compromisso' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('campo_descricao_compromisso'),
              controller: _descricao,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Descrição', alignLabelWithHint: true),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('campo_prioridade_compromisso'),
              initialValue: _prioridade,
              decoration: InputDecoration(
                labelText: 'Prioridade',
                helperText: 'Padrão: Média',
                prefixIcon: Icon(Icons.flag, color: corDaPrioridade(_prioridade), key: Key('tag_prioridade_comp_$_prioridade')),
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
                width: 180,
                child: InkWell(
                  key: const Key('campo_data_compromisso'),
                  onTap: _escolherData,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Data', suffixIcon: Icon(Icons.calendar_today_outlined)),
                    child: Text(formatarData(_data)),
                  ),
                ),
              ),
              if (!_diaInteiro) ...[
                SizedBox(
                  width: 130,
                  child: InkWell(
                    key: const Key('campo_hora_inicio_compromisso'),
                    onTap: () => _escolherHora(inicio: true),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Início', suffixIcon: Icon(Icons.schedule)),
                      child: Text(_hora(_inicio)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: InkWell(
                    key: const Key('campo_hora_fim_compromisso'),
                    onTap: () => _escolherHora(inicio: false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Término',
                        suffixIcon: _fim != null
                            ? IconButton(icon: const Icon(Icons.close), tooltip: 'Remover', onPressed: () => setState(() => _fim = null))
                            : const Icon(Icons.schedule),
                      ),
                      child: Text(_fim == null ? 'Opcional' : _hora(_fim!)),
                    ),
                  ),
                ),
              ],
            ]),
            SwitchListTile(
              key: const Key('campo_dia_inteiro_compromisso'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Dia inteiro'),
              value: _diaInteiro,
              onChanged: (v) => setState(() => _diaInteiro = v),
            ),
            TextFormField(
              key: const Key('campo_local_compromisso'),
              controller: _local,
              decoration: const InputDecoration(labelText: 'Local (opcional)', prefixIcon: Icon(Icons.place_outlined)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('campo_participantes_compromisso'),
              controller: _participantes,
              decoration: const InputDecoration(labelText: 'Participantes (opcional)', prefixIcon: Icon(Icons.people_outline)),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const Key('campo_lembrete_compromisso'),
              initialValue: _lembrete,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Lembrete', prefixIcon: Icon(Icons.notifications_none)),
              items: [for (final e in lembretesCompromisso.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _lembrete = v ?? _lembrete),
            ),
            ExpansionTile(
              key: const Key('dados_complementares_compromisso'),
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('Dados complementares', style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              children: [
                TextFormField(
                  key: const Key('campo_observacoes_compromisso'),
                  controller: _observacoes,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Observações', alignLabelWithHint: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_comentarios_compromisso'),
                  controller: _comentarios,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Comentários', alignLabelWithHint: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_link_compromisso'),
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Link (opcional)', prefixIcon: Icon(Icons.link)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_tags_compromisso'),
                  controller: _tags,
                  decoration: const InputDecoration(labelText: 'Tags', helperText: 'Separe por vírgula. Ex.: saúde, família'),
                ),
              ],
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, key: const Key('erro_compromisso'), style: TextStyle(color: tema.colorScheme.error)),
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
                for (final e in const {'fechar': 'Fechar', 'ver': 'Ver compromisso', 'nova': 'Adicionar novo'}.entries)
                  ChoiceChip(
                    key: Key('depois_comp_${e.key}'),
                    label: Text(e.value),
                    selected: _depois == e.key,
                    onSelected: (_) => setState(() => _depois = e.key),
                  ),
              ]),
            ),
            FilledButton(key: const Key('botao_salvar_compromisso'), onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
          ]),
        ),
      ),
    );
  }
}
