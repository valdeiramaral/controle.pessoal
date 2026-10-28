import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalogo_medicamentos.dart';
import '../../core/formatos.dart';
import '../../core/lembretes_saude.dart';
import '../../core/saude_calculo.dart';
import '../../data/local/banco.dart';

/// Abre o formulario de medicamento (novo ou edicao). Devolve true se algo mudou.
Future<bool?> abrirFormularioMedicamento(BuildContext context, {Medicamento? medicamento, DateTime? hoje}) =>
    Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => MedicamentoFormPage(medicamento: medicamento, hoje: hoje)));

/// Cadastro do medicamento: detalhes (nome, dose, formato, tratamento, instrucoes),
/// posologia (inicio, termino, frequencia, horarios, quantidade) e estoque com lembrete de reabastecimento.
class MedicamentoFormPage extends ConsumerStatefulWidget {
  const MedicamentoFormPage({super.key, this.medicamento, this.hoje});
  final Medicamento? medicamento; // != null: edita
  final DateTime? hoje; // para testes

  @override
  ConsumerState<MedicamentoFormPage> createState() => _MedicamentoFormPageState();
}

class _MedicamentoFormPageState extends ConsumerState<MedicamentoFormPage> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _dose = TextEditingController();
  final _tratamento = TextEditingController();
  final _instrucoes = TextEditingController();
  final _quantidade = TextEditingController(text: '1');
  final _intervalo = TextEditingController(text: '2');
  final _estoque = TextEditingController();
  final _estoqueMinimo = TextEditingController();
  final _fabricante = TextEditingController();
  final _posologia = TextEditingController();
  final _informacoes = TextEditingController();
  String? _infoAuto; // ultima informacao preenchida sozinha pelo catalogo
  String? _tipoMed; // referencia | generico | similar
  DateTime? _validade;
  String _formato = 'comprimido';
  String _frequencia = 'diaria';
  final _dias = <int>{};
  var _horarios = <(int, int)>[(8, 0)];
  late DateTime _inicio;
  String _periodo = 'continuo';
  final _duracao = TextEditingController(text: '7');
  bool _lembrete = true;
  String? _erro;
  bool _salvando = false;

  bool get _editando => widget.medicamento != null;

  int? get _duracaoUso {
    final n = int.tryParse(_duracao.text.trim());
    return n == null || n < 1 ? null : n;
  }

  /// Data final do uso, calculada pelo periodo e pela duracao (continuo = sem data final).
  DateTime? get _fimCalculado => _periodo == 'continuo' ? null : fimDoPeriodo(_inicio, _periodo, _duracaoUso);

  @override
  void initState() {
    super.initState();
    final h = widget.hoje ?? DateTime.now();
    _inicio = soDia(h);
    final m = widget.medicamento;
    if (m != null) {
      _nome.text = m.nome;
      _dose.text = m.dose;
      _tratamento.text = m.tratamento ?? '';
      _instrucoes.text = m.instrucoes ?? '';
      _quantidade.text = '${m.quantidade}';
      _intervalo.text = '${m.intervaloDias < 2 ? 2 : m.intervaloDias}';
      _estoque.text = m.estoque == null ? '' : '${m.estoque}';
      _estoqueMinimo.text = m.estoqueMinimo == null ? '' : '${m.estoqueMinimo}';
      _formato = formatosMedicamento.containsKey(m.formato) ? m.formato : 'outro';
      _frequencia = m.frequencia;
      _dias.addAll(lerDiasSemana(m.diasSemana));
      _horarios = lerHorarios(m.horarios);
      _inicio = soDia(m.inicio);
      _periodo = periodosUso.containsKey(m.periodoUso) ? m.periodoUso : 'continuo';
      if (_periodo != 'continuo' && m.duracaoUso != null) {
        _duracao.text = '${m.duracaoUso}';
      } else if (m.fim != null) {
        // cadastro antigo, so com data final: vira "diario" pelo numero de dias
        _periodo = 'diario';
        _duracao.text = '${soDia(m.fim!).difference(soDia(m.inicio)).inDays + 1}';
      } else {
        _periodo = 'continuo';
      }
      _lembrete = m.lembreteReabastecer;
      _tipoMed = tiposMedicamento.containsKey(m.tipoMedicamento) ? m.tipoMedicamento : null;
      _fabricante.text = m.fabricante ?? '';
      _validade = m.validade == null ? null : soDia(m.validade!);
      _posologia.text = m.posologia ?? '';
      _informacoes.text = m.informacoes ?? '';
    }
  }

  /// Ao digitar o nome, preenche a informacao breve se o remedio for conhecido (sem apagar o que a pessoa escreveu).
  void _nomeMudou(String texto) {
    final info = infoDoMedicamento(texto)?.informacao;
    final vazio = _informacoes.text.trim().isEmpty || _informacoes.text == _infoAuto;
    if (vazio) {
      _informacoes.text = info ?? '';
      _infoAuto = info;
    }
    setState(() {});
  }

  void _usarSugestao(InfoMedicamento m) {
    _nome.text = m.nome;
    _nome.selection = TextSelection.collapsed(offset: m.nome.length);
    _nomeMudou(m.nome);
  }

  Future<void> _escolherValidade() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _validade ?? _inicio,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _validade = soDia(d));
  }

  @override
  void dispose() {
    for (final c in [_duracao, _nome, _dose, _tratamento, _instrucoes, _quantidade, _intervalo, _estoque, _estoqueMinimo, _fabricante, _posologia, _informacoes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherData({required bool inicio}) async {
    final base = _inicio;
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() => _inicio = soDia(d));
  }

  Future<void> _adicionarHorario() async {
    if (_horarios.length >= maximoHorarios) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    final novo = (t.hour, t.minute);
    if (_horarios.contains(novo)) return;
    setState(() => _horarios = lerHorarios(horariosParaTexto([..._horarios, novo])));
  }

  String? _inteiroOpcional(String? v, {int minimo = 0}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n < minimo) return 'Use um número inteiro a partir de $minimo';
    return null;
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (!_form.currentState!.validate()) return;
    if (_frequencia != 'necessario' && _horarios.isEmpty) {
      setState(() => _erro = 'Adicione ao menos um horário.');
      return;
    }
    if (_frequencia == 'dias_semana' && _dias.isEmpty) {
      setState(() => _erro = 'Escolha os dias da semana.');
      return;
    }
    if (_periodo != 'continuo' && _duracaoUso == null) {
      setState(() => _erro = 'Informe por quanto tempo o medicamento será usado (um número a partir de 1).');
      return;
    }
    setState(() => _salvando = true);
    final banco = ref.read(bancoProvider);
    final horarios = _frequencia == 'necessario' ? '' : horariosParaTexto(_horarios);
    final dias = _frequencia == 'dias_semana' ? (_dias.toList()..sort()).join(',') : '';
    final intervalo = _frequencia == 'intervalo' ? int.parse(_intervalo.text.trim()) : 1;
    final estoque = int.tryParse(_estoque.text.trim());
    final minimo = _lembrete ? int.tryParse(_estoqueMinimo.text.trim()) : null;
    final tratamento = _tratamento.text.trim().isEmpty ? null : _tratamento.text.trim();
    final instrucoes = _instrucoes.text.trim().isEmpty ? null : _instrucoes.text.trim();
    String? opcional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final String id;
      if (_editando) {
        id = widget.medicamento!.id;
        await LembretesSaude.cancelarMedicamento(widget.medicamento!);
        await banco.atualizarMedicamento(
          id,
          nome: _nome.text.trim(),
          dose: _dose.text.trim(),
          horarios: horarios,
          formato: _formato,
          tratamento: tratamento,
          instrucoes: instrucoes,
          quantidade: int.parse(_quantidade.text.trim()),
          frequencia: _frequencia,
          diasSemana: dias,
          intervaloDias: intervalo,
          inicio: _inicio,
          fim: _fimCalculado,
          periodoUso: _periodo,
          duracaoUso: _periodo == 'continuo' ? null : _duracaoUso,
          estoque: estoque,
          estoqueMinimo: minimo,
          lembreteReabastecer: _lembrete,
          tipoMedicamento: _tipoMed,
          fabricante: opcional(_fabricante),
          validade: _validade,
          posologia: opcional(_posologia),
          informacoes: opcional(_informacoes),
        );
      } else {
        id = await banco.inserirMedicamento(
          nome: _nome.text.trim(),
          dose: _dose.text.trim(),
          horarios: horarios,
          formato: _formato,
          tratamento: tratamento,
          instrucoes: instrucoes,
          quantidade: int.parse(_quantidade.text.trim()),
          frequencia: _frequencia,
          diasSemana: dias,
          intervaloDias: intervalo,
          inicio: _inicio,
          fim: _fimCalculado,
          periodoUso: _periodo,
          duracaoUso: _periodo == 'continuo' ? null : _duracaoUso,
          estoque: estoque,
          estoqueMinimo: minimo,
          lembreteReabastecer: _lembrete,
          tipoMedicamento: _tipoMed,
          fabricante: opcional(_fabricante),
          validade: _validade,
          posologia: opcional(_posologia),
          informacoes: opcional(_informacoes),
        );
      }
      final salvo = await banco.medicamentoPorId(id);
      if (salvo != null) await LembretesSaude.agendarMedicamento(salvo);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() {
        _erro = 'Não foi possível salvar: $e';
        _salvando = false;
      });
    }
  }

  Future<void> _suspender() async {
    final m = widget.medicamento!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Suspender ${m.nome}?'),
        content: const Text(
            'O medicamento será alterado para "Não estou tomando". Você não receberá mais lembretes sobre esse medicamento.'),
        actions: [
          TextButton(key: const Key('manter_med'), onPressed: () => Navigator.pop(c, false), child: const Text('Manter')),
          FilledButton(key: const Key('confirmar_suspender'), onPressed: () => Navigator.pop(c, true), child: const Text('Suspender')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(bancoProvider).definirAtivoMedicamento(m.id, false);
    await LembretesSaude.cancelarMedicamento(m);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _reativar() async {
    final banco = ref.read(bancoProvider);
    final m = widget.medicamento!;
    await banco.definirAtivoMedicamento(m.id, true);
    final atual = await banco.medicamentoPorId(m.id);
    if (atual != null) await LembretesSaude.agendarMedicamento(atual);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _excluir() async {
    final m = widget.medicamento!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Excluir ${m.nome}?'),
        content: const Text('O medicamento e seus lembretes serão removidos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('confirmar_excluir_med'), onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(bancoProvider).excluirMedicamento(m.id);
    await LembretesSaude.cancelarMedicamento(m);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _secao(String texto) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _campoData(Key chave, String rotulo, DateTime? valor, VoidCallback aoTocar,
          {VoidCallback? limpar, String vazio = 'Sem data de término'}) => InkWell(
        key: chave,
        onTap: aoTocar,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: rotulo,
            suffixIcon: limpar != null && valor != null
                ? IconButton(icon: const Icon(Icons.close), tooltip: 'Remover', onPressed: limpar)
                : const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(valor == null ? vazio : formatarData(valor)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.medicamento;
    final nec = _frequencia == 'necessario';
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar medicamento' : 'Novo medicamento')),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (m != null && !m.ativo)
                  Card(
                    key: const Key('aviso_suspenso'),
                    child: const ListTile(
                      leading: Icon(Icons.pause_circle_outline),
                      title: Text('Não estou tomando'),
                      subtitle: Text('Sem doses programadas nem lembretes.'),
                    ),
                  ),
                _secao('Detalhes do medicamento'),
                TextFormField(
                  key: const Key('campo_nome_med'),
                  controller: _nome,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nome', helperText: 'Ex.: Ácido acetilsalicílico'),
                  onChanged: _nomeMudou,
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Informe o nome' : null,
                ),
                Builder(builder: (context) {
                  final sugestoes = sugerirMedicamentos(_nome.text).where((m) => m.nome != _nome.text.trim()).toList();
                  if (sugestoes.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 0; i < sugestoes.length; i++)
                          ActionChip(
                            key: Key('sugestao_med_$i'),
                            label: Text(sugestoes[i].nome),
                            onPressed: () => _usarSugestao(sugestoes[i]),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_dose_med'),
                  controller: _dose,
                  decoration: const InputDecoration(labelText: 'Dose', helperText: 'Concentração do medicamento. Ex.: 100 mg'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Informe a dose' : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('campo_formato_med'),
                  initialValue: _formato,
                  decoration: const InputDecoration(labelText: 'Formato'),
                  items: [for (final e in formatosMedicamento.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _formato = v ?? _formato),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_tratamento_med'),
                  controller: _tratamento,
                  decoration: const InputDecoration(labelText: 'Tratamento (opcional)', helperText: 'Para que serve. Ex.: Colesterol alto'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_instrucoes_med'),
                  controller: _instrucoes,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Instruções (opcional)', helperText: 'Ex.: Tomar após o almoço, com água'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_informacoes_med'),
                  controller: _informacoes,
                  maxLines: 4,
                  maxLength: 600,
                  decoration: const InputDecoration(
                    labelText: 'Sobre o medicamento',
                    helperText: avisoInformacao,
                    helperMaxLines: 3,
                    alignLabelWithHint: true,
                  ),
                ),
                _secao('Identificação'),
                DropdownButtonFormField<String?>(
                  key: const Key('campo_tipo_medicamento'),
                  initialValue: _tipoMed,
                  decoration: const InputDecoration(
                    labelText: 'Classificação (Anvisa)',
                    helperText: explicacaoTipoMedicamento,
                    helperMaxLines: 5,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Não informado')),
                    for (final e in tiposMedicamento.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _tipoMed = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_fabricante_med'),
                  controller: _fabricante,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Fabricante/laboratório (opcional)', helperText: 'Ex.: EMS, Eurofarma, Medley'),
                ),
                const SizedBox(height: 8),
                _campoData(const Key('campo_validade_med'), 'Validade (opcional)', _validade, _escolherValidade,
                    limpar: () => setState(() => _validade = null), vazio: 'Não informada'),
                if (_validade != null && _validade!.isBefore(soDia(widget.hoje ?? DateTime.now())))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Medicamento vencido. Não use e descarte conforme orientação do farmacêutico.',
                        key: const Key('aviso_vencido_form'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                _secao('Quando você toma'),
                TextFormField(
                  key: const Key('campo_posologia_med'),
                  controller: _posologia,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Posologia da receita (opcional)',
                    helperText: 'Como o médico mandou tomar. Ex.: 1 comprimido de 8 em 8 horas, por 7 dias',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 8),
                _campoData(const Key('campo_inicio_med'), 'Começar', _inicio, () => _escolherData(inicio: true)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('campo_periodo_med'),
                  initialValue: _periodo,
                  decoration: const InputDecoration(labelText: 'Período de uso'),
                  items: [for (final e in periodosUso.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _periodo = v ?? _periodo),
                ),
                if (_periodo != 'continuo') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('campo_duracao_med'),
                    controller: _duracao,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Por quanto tempo (${_periodo == 'diario' ? 'dias' : _periodo == 'semanal' ? 'semanas' : 'meses'})',
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => _periodo != 'continuo' && (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'Informe um número a partir de 1' : null,
                  ),
                  if (_fimCalculado != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text('Termina em ${formatarData(_fimCalculado!)}', key: const Key('termino_med')),
                    ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('campo_frequencia_med'),
                  initialValue: _frequencia,
                  decoration: const InputDecoration(labelText: 'Frequência'),
                  items: [for (final e in frequenciasMedicamento.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _frequencia = v ?? _frequencia),
                ),
                if (_frequencia == 'dias_semana') ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          key: Key('dia_semana_$d'),
                          label: Text(nomesDiasSemana[d - 1]),
                          selected: _dias.contains(d),
                          onSelected: (s) => setState(() => s ? _dias.add(d) : _dias.remove(d)),
                        ),
                    ],
                  ),
                ],
                if (_frequencia == 'intervalo') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('campo_intervalo_dias'),
                    controller: _intervalo,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'A cada quantos dias', helperText: 'Ex.: 2 = dia sim, dia não'),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return n == null || n < 2 || n > 365 ? 'Use de 2 a 365 dias' : null;
                    },
                  ),
                ],
                if (!nec) ...[
                  const SizedBox(height: 10),
                  Text('Horários', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final h in _horarios)
                        InputChip(
                          key: Key('horario_${formatarHorario(h)}'),
                          label: Text(formatarHorario(h)),
                          onDeleted: () => setState(() => _horarios = [..._horarios]..remove(h)),
                        ),
                      ActionChip(
                        key: const Key('botao_add_horario'),
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar horário'),
                        onPressed: _adicionarHorario,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_quantidade_med'),
                  controller: _quantidade,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Quantidade por tomada',
                    helperText: 'Quanto você toma de cada vez (${descricaoQuantidade(_formato, 1).split(' ').last}). Desconta do estoque.',
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    return n == null || n < 1 || n > 99 ? 'Use de 1 a 99' : null;
                  },
                ),
                _secao('Estoque'),
                TextFormField(
                  key: const Key('campo_estoque_med'),
                  controller: _estoque,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Estoque atual (unidades)', helperText: 'Deixe em branco para não controlar'),
                  validator: (v) => _inteiroOpcional(v),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('campo_lembrete_reabastecer'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lembrete de reabastecer'),
                  value: _lembrete,
                  onChanged: (v) => setState(() => _lembrete = v),
                ),
                if (_lembrete)
                  TextFormField(
                    key: const Key('campo_estoque_minimo_med'),
                    controller: _estoqueMinimo,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Lembrar quando restarem', helperText: 'Quantidade de unidades. Ex.: 5'),
                    validator: (v) => _inteiroOpcional(v),
                  ),
                if (_erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_erro!, key: const Key('erro_medicamento'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('botao_salvar_med'),
                  onPressed: _salvando ? null : _salvar,
                  child: Text(_salvando ? 'Salvando...' : 'Salvar'),
                ),
                if (m != null) ...[
                  const SizedBox(height: 8),
                  if (m.ativo)
                    OutlinedButton.icon(
                      key: const Key('botao_suspender_med'),
                      icon: const Icon(Icons.pause_circle_outline),
                      label: const Text('Suspender (não estou tomando)'),
                      onPressed: _suspender,
                    )
                  else
                    OutlinedButton.icon(
                      key: const Key('botao_reativar_med'),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Voltar a tomar'),
                      onPressed: _reativar,
                    ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('botao_excluir_med'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Excluir medicamento'),
                    onPressed: _excluir,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
