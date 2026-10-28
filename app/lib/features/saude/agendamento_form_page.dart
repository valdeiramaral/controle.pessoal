import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatos.dart';
import '../../core/lembretes_saude.dart';
import '../../core/saude_calculo.dart';
import '../../data/local/banco.dart';

/// Abre o formulario de agendamento (novo ou edicao). Devolve true se salvou.
Future<bool?> abrirFormularioAgendamento(BuildContext context,
        {AgendamentoSaude? agendamento, String tipo = 'consulta', DateTime? agora}) =>
    Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => AgendamentoFormPage(agendamento: agendamento, tipoInicial: tipo, agora: agora)));

/// Agendamento de consulta, exame, retorno ou vacina, unico ou periodico (a cada N dias/semanas/meses/anos).
class AgendamentoFormPage extends ConsumerStatefulWidget {
  const AgendamentoFormPage({super.key, this.agendamento, this.tipoInicial = 'consulta', this.agora});
  final AgendamentoSaude? agendamento; // != null: edita
  final String tipoInicial;
  final DateTime? agora; // para testes

  @override
  ConsumerState<AgendamentoFormPage> createState() => _AgendamentoFormPageState();
}

class _AgendamentoFormPageState extends ConsumerState<AgendamentoFormPage> {
  final _form = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _profissional = TextEditingController();
  final _especialidade = TextEditingController();
  final _local = TextEditingController();
  final _preparo = TextEditingController();
  final _observacao = TextEditingController();
  final _vezes = TextEditingController(text: '4');
  final _intervalo = TextEditingController(text: '1');
  String _tipo = 'consulta';
  late DateTime _quando;
  int? _lembrete = 60;
  String _repetir = 'nao'; // nao | semanal ... anual | personalizado
  String _unidade = 'meses';
  bool _aplicarSeguintes = false;
  int _seguintes = 0;
  String? _erro;
  bool _salvando = false;

  bool get _editando => widget.agendamento != null;

  @override
  void initState() {
    super.initState();
    final base = widget.agora ?? DateTime.now();
    _tipo = widget.tipoInicial;
    _quando = DateTime(base.year, base.month, base.day, base.hour, 0).add(const Duration(days: 1));
    final a = widget.agendamento;
    if (a != null) {
      _tipo = a.tipo;
      _quando = a.dataHora;
      _titulo.text = a.titulo;
      _profissional.text = a.profissional ?? '';
      _especialidade.text = a.especialidade ?? '';
      _local.text = a.local ?? '';
      _preparo.text = a.preparo ?? '';
      _observacao.text = a.observacao ?? '';
      _lembrete = a.lembreteMin;
      ref.read(bancoProvider).contarSeguintesAgendamento(a).then((n) {
        if (mounted) setState(() => _seguintes = n);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_titulo, _profissional, _especialidade, _local, _preparo, _observacao, _vezes, _intervalo]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ehConsulta => _tipo == 'consulta' || _tipo == 'retorno';

  (String, int)? get _periodo {
    if (_repetir == 'nao') return null;
    if (_repetir == 'personalizado') {
      final n = int.tryParse(_intervalo.text.trim());
      return n == null || n < 1 || n > 365 ? null : (_unidade, n);
    }
    return repeticoesProntas[_repetir];
  }

  Future<void> _escolherQuando() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _quando,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_quando));
    if (t == null) return;
    setState(() => _quando = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  String? _nulo(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (!_form.currentState!.validate()) return;
    final periodo = _editando ? null : _periodo;
    if (!_editando && _repetir != 'nao' && periodo == null) {
      setState(() => _erro = 'Informe de quanto em quanto tempo repete (1 a 365).');
      return;
    }
    setState(() => _salvando = true);
    final banco = ref.read(bancoProvider);
    try {
      final List<AgendamentoSaude> afetados;
      if (_editando) {
        afetados = await banco.atualizarAgendamento(
          widget.agendamento!,
          tipo: _tipo,
          titulo: _titulo.text.trim(),
          profissional: _nulo(_profissional),
          especialidade: _ehConsulta ? _nulo(_especialidade) : null,
          local: _nulo(_local),
          dataHora: _quando,
          preparo: _nulo(_preparo),
          observacao: _nulo(_observacao),
          lembreteMin: _lembrete,
          aplicarNosSeguintes: _aplicarSeguintes,
        );
      } else {
        afetados = await banco.criarAgendamentos(
          tipo: _tipo,
          titulo: _titulo.text.trim(),
          profissional: _nulo(_profissional),
          especialidade: _ehConsulta ? _nulo(_especialidade) : null,
          local: _nulo(_local),
          dataHora: _quando,
          preparo: _nulo(_preparo),
          observacao: _nulo(_observacao),
          lembreteMin: _lembrete,
          repeticaoUnidade: periodo?.$1,
          repeticaoIntervalo: periodo?.$2 ?? 1,
          vezes: periodo == null ? 1 : int.parse(_vezes.text.trim()),
        );
      }
      for (final a in afetados) {
        await LembretesSaude.agendarAgendamento(a);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() {
        _erro = 'Não foi possível salvar: $e';
        _salvando = false;
      });
    }
  }

  Widget _secao(String texto) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final periodo = _editando ? null : _periodo;
    final vezes = int.tryParse(_vezes.text.trim());
    final datas = (periodo != null && vezes != null && vezes >= 2 && vezes <= maximoOcorrencias)
        ? ocorrenciasAgendamento(_quando, periodo.$1, periodo.$2, vezes)
        : null;
    final a = widget.agendamento;
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar agendamento' : 'Novo agendamento')),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('campo_tipo_ag'),
                  initialValue: _tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [for (final e in tiposAgendamento.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _tipo = v ?? _tipo),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_titulo_ag'),
                  controller: _titulo,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _tipo == 'exame' ? 'Nome do exame' : (_tipo == 'vacina' ? 'Vacina' : 'Descrição'),
                    helperText: _tipo == 'exame'
                        ? 'Ex.: Hemograma completo, Ultrassom de abdômen'
                        : (_tipo == 'vacina' ? 'Ex.: Gripe, Reforço da tétano' : 'Ex.: Consulta de rotina, Revisão do tratamento'),
                    helperMaxLines: 2,
                  ),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Informe a descrição' : null,
                ),
                if (_ehConsulta) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('campo_especialidade_ag'),
                    controller: _especialidade,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Especialidade (opcional)', helperText: 'Ex.: Cardiologia'),
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_profissional_ag'),
                  controller: _profissional,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: _tipo == 'exame' ? 'Médico solicitante (opcional)' : 'Médico/profissional (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_local_ag'),
                  controller: _local,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: _tipo == 'exame' ? 'Laboratório/clínica (opcional)' : 'Local (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  key: const Key('campo_data_ag'),
                  onTap: _escolherQuando,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Data e hora', suffixIcon: Icon(Icons.event_outlined)),
                    child: Text(formatarDataHora(_quando), key: const Key('texto_data_ag')),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  key: const Key('campo_lembrete_ag'),
                  initialValue: _lembrete,
                  decoration: const InputDecoration(labelText: 'Lembrete'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Sem lembrete')),
                    for (final e in antecedenciasLembrete.entries) DropdownMenuItem<int?>(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _lembrete = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_preparo_ag'),
                  controller: _preparo,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Preparo (opcional)', helperText: 'Ex.: Jejum de 8 horas, levar exames anteriores'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_observacao_ag'),
                  controller: _observacao,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Observação (opcional)'),
                ),
                if (!_editando) ...[
                  _secao('Repetir'),
                  DropdownButtonFormField<String>(
                    key: const Key('campo_repetir_ag'),
                    initialValue: _repetir,
                    decoration: const InputDecoration(labelText: 'Agendamento periódico'),
                    items: [
                      const DropdownMenuItem(value: 'nao', child: Text('Não repetir')),
                      for (final e in repeticoesProntas.keys)
                        DropdownMenuItem(value: e, child: Text(e[0].toUpperCase() + e.substring(1))),
                      const DropdownMenuItem(value: 'personalizado', child: Text('Personalizado...')),
                    ],
                    onChanged: (v) => setState(() => _repetir = v ?? 'nao'),
                  ),
                  if (_repetir == 'personalizado') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const Key('campo_intervalo_ag'),
                            controller: _intervalo,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'A cada'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: const Key('campo_unidade_ag'),
                            initialValue: _unidade,
                            decoration: const InputDecoration(labelText: 'Unidade'),
                            items: [for (final e in unidadesRepeticao.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                            onChanged: (v) => setState(() => _unidade = v ?? _unidade),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_repetir != 'nao') ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('campo_vezes_ag'),
                      controller: _vezes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Total de agendamentos', helperText: 'Contando o primeiro (2 a $maximoOcorrencias)'),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 2 || n > maximoOcorrencias ? 'Use de 2 a $maximoOcorrencias' : null;
                      },
                    ),
                    if (datas != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${datas.length} agendamentos: de ${formatarData(datas.first)} a ${formatarData(datas.last)}',
                          key: const Key('previa_serie_ag'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ],
                if (_editando && a?.grupoSerie != null) ...[
                  const SizedBox(height: 8),
                  Text('Faz parte de uma série (${a!.serieNumero} de ${a.serieTotal}).', key: const Key('info_serie_ag')),
                  if (_seguintes > 0)
                    CheckboxListTile(
                      key: const Key('campo_aplicar_seguintes_ag'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _aplicarSeguintes,
                      onChanged: (v) => setState(() => _aplicarSeguintes = v ?? false),
                      title: Text('Aplicar descrição, local, profissional, preparo, observação e lembrete também aos $_seguintes seguintes'),
                    ),
                ],
                if (_erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_erro!, key: const Key('erro_agendamento'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('botao_salvar_ag'),
                  onPressed: _salvando ? null : _salvar,
                  child: Text(_salvando ? 'Salvando...' : 'Salvar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
