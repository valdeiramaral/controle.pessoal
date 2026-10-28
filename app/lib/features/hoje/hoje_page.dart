import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/aparencia.dart';
import '../../core/formatos.dart';
import '../../data/local/banco.dart';
import '../nav/menu_lateral.dart';

/// Intervalo (inclusivo) de um atalho de periodo.
DateTimeRange periodoRapido(String nome, DateTime hoje) {
  final h = DateTime(hoje.year, hoje.month, hoje.day);
  switch (nome) {
    case 'Hoje':
      return DateTimeRange(start: h, end: h);
    case 'Amanhã':
      final a = h.add(const Duration(days: 1));
      return DateTimeRange(start: a, end: a);
    case 'Esta semana':
      final ini = h.subtract(Duration(days: h.weekday - 1));
      return DateTimeRange(start: ini, end: ini.add(const Duration(days: 6)));
    case 'Semana passada':
      final ini = h.subtract(Duration(days: h.weekday - 1 + 7));
      return DateTimeRange(start: ini, end: ini.add(const Duration(days: 6)));
    case 'Este mês':
      return DateTimeRange(start: DateTime(h.year, h.month, 1), end: DateTime(h.year, h.month + 1, 0));
    case 'Mês passado':
      return DateTimeRange(start: DateTime(h.year, h.month - 1, 1), end: DateTime(h.year, h.month, 0));
    case 'Próximos 15 dias':
      return DateTimeRange(start: h, end: h.add(const Duration(days: 15)));
    case 'Próximos 30 dias':
      return DateTimeRange(start: h, end: h.add(const Duration(days: 30)));
    default:
      return DateTimeRange(start: h, end: h.add(const Duration(days: 7)));
  }
}

const atalhosPeriodo = [
  'Hoje',
  'Amanhã',
  'Esta semana',
  'Semana passada',
  'Este mês',
  'Mês passado',
  'Próximos 15 dias',
  'Próximos 30 dias',
];

/// Painel inicial: filtros de periodo, indicadores e abas (Agenda, Contas, Remedios, Resumo).
class HojePage extends ConsumerStatefulWidget {
  const HojePage({super.key});

  @override
  ConsumerState<HojePage> createState() => _HojePageState();
}

class _HojePageState extends ConsumerState<HojePage> {
  late DateTime _de;
  late DateTime _ate;
  late DateTime _deAplicado;
  late DateTime _ateAplicado;
  final _busca = TextEditingController();
  String _buscaAplicada = '';
  bool _incluirAbertas = true;
  bool _incluirAbertasAplicado = true;
  int _aba = 0;
  String _statusConta = 'Todas';

  @override
  void initState() {
    super.initState();
    final p = periodoRapido('', DateTime.now());
    _de = _deAplicado = p.start;
    _ate = _ateAplicado = p.end;
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _consultar() => setState(() {
        _deAplicado = _de;
        _ateAplicado = _ate;
        _buscaAplicada = _busca.text.trim().toLowerCase();
        _incluirAbertasAplicado = _incluirAbertas;
      });

  void _atalho(String nome) {
    final p = periodoRapido(nome, DateTime.now());
    setState(() {
      _de = p.start;
      _ate = p.end;
    });
    _consultar();
  }

  Future<void> _escolherData(bool inicio) async {
    final atual = inicio ? _de : _ate;
    final d = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (inicio) {
        _de = d;
        if (_ate.isBefore(d)) _ate = d;
      } else {
        _ate = d;
        if (_de.isAfter(d)) _de = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final banco = ref.watch(bancoProvider);
    return Scaffold(
      appBar: BarraPagina(
        title: Text('Hoje · ${formatarData(DateTime.now())}'),
      ),
      body: StreamBuilder<List<Evento>>(
        stream: banco.observarEventosEntre(_deAplicado, _ateAplicado),
        builder: (context, snapEv) => StreamBuilder<List<Lancamento>>(
          stream: banco.observarLancamentos(),
          builder: (context, snapLan) => StreamBuilder<List<Medicamento>>(
            stream: banco.observarMedicamentos(),
            builder: (context, snapMed) {
              final dados = _Dados(
                eventos: (snapEv.data ?? const <Evento>[]).where(_casaEvento).toList(),
                lancamentos: snapLan.data ?? const <Lancamento>[],
                medicamentos: (snapMed.data ?? const <Medicamento>[]).where((m) => m.ativo && _casaTexto(m.nome)).toList(),
                de: _deAplicado,
                ate: _ateAplicado,
                incluirAbertas: _incluirAbertasAplicado,
                busca: _buscaAplicada,
              );
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _filtros(context),
                  const SizedBox(height: 16),
                  _Indicadores(dados: dados),
                  const SizedBox(height: 16),
                  _painelAbas(context, dados),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  bool _casaTexto(String t) => _buscaAplicada.isEmpty || t.toLowerCase().contains(_buscaAplicada);
  bool _casaEvento(Evento e) => _casaTexto(e.titulo) || _casaTexto(e.local ?? '');

  Widget _filtros(BuildContext context) {
    final tema = Theme.of(context);
    Widget data(String rotulo, DateTime v, bool inicio) => SizedBox(
          width: 170,
          child: InkWell(
            key: Key(inicio ? 'campo_de' : 'campo_ate'),
            onTap: () => _escolherData(inicio),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: rotulo,
                isDense: true,
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
              ),
              child: Text(formatarData(v)),
            ),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                data('Período de', _de, true),
                data('até', _ate, false),
                SizedBox(
                  width: 220,
                  child: TextField(
                    key: const Key('campo_filtro'),
                    controller: _busca,
                    decoration: const InputDecoration(labelText: 'Filtro (opcional)', hintText: 'Ex.: dentista', isDense: true),
                    onSubmitted: (_) => _consultar(),
                  ),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                    key: const Key('incluir_abertas'),
                    value: _incluirAbertas,
                    onChanged: (v) => setState(() => _incluirAbertas = v ?? true),
                  ),
                  const Text('Incluir contas em aberto fora do período'),
                ]),
                FilledButton(key: const Key('botao_consultar'), onPressed: _consultar, child: const Text('Consultar')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in atalhosPeriodo)
                ActionChip(
                  key: Key('atalho_$a'),
                  label: Text(a, style: tema.textTheme.bodySmall),
                  onPressed: () => _atalho(a),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _painelAbas(BuildContext context, _Dados d) {
    final tema = Theme.of(context);
    const nomes = ['Agenda', 'Contas', 'Remédios', 'Resumo e gráficos'];
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              for (var i = 0; i < nomes.length; i++)
                InkWell(
                  key: Key('aba_$i'),
                  onTap: () => setState(() => _aba = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: _aba == i ? tema.colorScheme.primary : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      nomes[i],
                      style: tema.textTheme.titleSmall?.copyWith(
                        color: _aba == i ? tema.colorScheme.primary : tema.colorScheme.onSurfaceVariant,
                        fontWeight: _aba == i ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: switch (_aba) {
              0 => _abaAgenda(context, d),
              1 => _abaContas(context, d),
              2 => _abaRemedios(context, d),
              _ => _abaResumo(context, d),
            },
          ),
        ],
      ),
    );
  }

  Widget _titulo(BuildContext context, String t) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: Theme.of(context).textTheme.titleLarge));

  Widget _vazio(String t) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t));

  Widget _cabecalho(BuildContext context, List<(String, int)> cols) {
    final estilo = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: .6);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .06),
      child: Row(children: [
        for (final c in cols) Expanded(flex: c.$2, child: Text(c.$1.toUpperCase(), style: estilo)),
      ]),
    );
  }

  Widget _linha(BuildContext context, List<Widget> cels, List<int> flex) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
        child: Row(children: [for (var i = 0; i < cels.length; i++) Expanded(flex: flex[i], child: cels[i])]),
      );

  Widget _abaAgenda(BuildContext context, _Dados d) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titulo(context, 'Compromissos (${d.eventos.length})'),
      if (d.eventos.isEmpty)
        _vazio('Nada agendado no período.')
      else ...[
        _cabecalho(context, const [('Data', 2), ('Hora', 1), ('Compromisso', 4), ('Local', 2)]),
        for (final e in d.eventos)
          _linha(context, [
            Text(formatarData(e.inicio)),
            Text(e.diaInteiro ? 'Dia todo' : formatarDataHora(e.inicio).substring(11)),
            Text(e.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(e.local ?? '—'),
          ], const [2, 1, 4, 2]),
      ],
    ]);
  }

  Widget _abaContas(BuildContext context, _Dados d) {
    const filtros = ['Todas', 'Pendentes', 'Atrasadas', 'Pagas'];
    final base = d.contasVisiveis;
    final itens = base.where((l) {
      switch (_statusConta) {
        case 'Pendentes':
          return l.status == 'pendente';
        case 'Atrasadas':
          return d.atrasada(l);
        case 'Pagas':
          return l.status == 'pago';
        default:
          return true;
      }
    }).toList();
    int n(String f) => f == 'Todas'
        ? base.length
        : base.where((l) => f == 'Pendentes' ? l.status == 'pendente' : f == 'Atrasadas' ? d.atrasada(l) : l.status == 'pago').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titulo(context, 'Contas (${itens.length})'),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('STATUS', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        for (final f in filtros)
          ChoiceChip(
            key: Key('status_$f'),
            label: Text('$f  ${n(f)}'),
            selected: _statusConta == f,
            onSelected: (_) => setState(() => _statusConta = f),
          ),
      ]),
      const SizedBox(height: 12),
      if (itens.isEmpty)
        _vazio('Nenhuma conta para este filtro.')
      else ...[
        _cabecalho(context, const [('Vencimento', 2), ('Descrição', 4), ('Status', 2), ('Valor', 2)]),
        for (final l in itens)
          _linha(context, [
            Text(formatarData(l.dia)),
            Text(l.descricao, style: const TextStyle(fontWeight: FontWeight.w600)),
            Align(alignment: Alignment.centerLeft, child: _Etiqueta(d.atrasada(l) ? 'ATRASADA' : l.status.toUpperCase(),
                corIcone(context, d.atrasada(l) ? Colors.red : (l.status == 'pago' ? Colors.green : Colors.amber)))),
            Text(formatarCentavos(l.valorCentavos), textAlign: TextAlign.right,
                style: TextStyle(color: l.tipo == 'receita' ? corIcone(context, Colors.green) : null)),
          ], const [2, 4, 2, 2]),
      ],
    ]);
  }

  Widget _abaRemedios(BuildContext context, _Dados d) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titulo(context, 'Remédios (${d.medicamentos.length})'),
      if (d.medicamentos.isEmpty)
        _vazio('Nenhum medicamento cadastrado.')
      else ...[
        _cabecalho(context, const [('Medicamento', 4), ('Dose', 2), ('Horários', 3)]),
        for (final m in d.medicamentos)
          _linha(context, [
            Text(m.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(m.dose),
            Text(m.frequencia == 'necessario' ? 'Se necessário' : m.horarios.replaceAll(',', '  ')),
          ], const [4, 2, 3]),
      ],
    ]);
  }

  Widget _abaResumo(BuildContext context, _Dados d) {
    final rec = d.somaPeriodo('receita');
    final desp = d.somaPeriodo('despesa');
    // Sem clamp(1, 1 << 40): na web `1 << 40` vira 0 e clamp lancava "Invalid argument: 1".
    final maior = rec > desp ? rec : desp;
    Widget barra(String rotulo, int v, Color cor) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(rotulo), Text(formatarCentavos(v))]),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: maior <= 0 ? 0 : v / maior, minHeight: 10, color: cor, backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(6)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titulo(context, 'Resumo do período'),
      barra('Receitas', rec, corIcone(context, Colors.green)),
      barra('Despesas', desp, corIcone(context, Colors.red)),
      Text('Saldo do período: ${formatarCentavos(rec - desp)}', style: Theme.of(context).textTheme.titleMedium),
    ]);
  }
}

/// Dados ja filtrados para o painel.
class _Dados {
  _Dados({
    required this.eventos,
    required this.lancamentos,
    required this.medicamentos,
    required this.de,
    required this.ate,
    required this.incluirAbertas,
    required this.busca,
  });

  final List<Evento> eventos;
  final List<Lancamento> lancamentos;
  final List<Medicamento> medicamentos;
  final DateTime de;
  final DateTime ate;
  final bool incluirAbertas;
  final String busca;

  DateTime get _ini => DateTime(de.year, de.month, de.day);
  DateTime get _fim => DateTime(ate.year, ate.month, ate.day).add(const Duration(days: 1));
  DateTime get _hoje {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool noPeriodo(Lancamento l) => !l.dia.isBefore(_ini) && l.dia.isBefore(_fim);
  bool atrasada(Lancamento l) => l.status == 'pendente' && l.tipo == 'despesa' && l.dia.isBefore(_hoje);
  bool _texto(Lancamento l) => busca.isEmpty || l.descricao.toLowerCase().contains(busca);

  /// Contas do periodo, mais as em aberto fora dele quando pedido.
  List<Lancamento> get contasVisiveis {
    final r = lancamentos
        .where((l) => l.tipo != 'transferencia' && _texto(l))
        .where((l) => noPeriodo(l) || (incluirAbertas && l.status == 'pendente' && l.tipo == 'despesa'))
        .toList()
      ..sort((a, b) => a.dia.compareTo(b.dia));
    return r;
  }

  int somaPeriodo(String tipo) =>
      lancamentos.where((l) => l.tipo == tipo && noPeriodo(l) && _texto(l)).fold(0, (s, l) => s + l.valorCentavos);

  int get abertas => lancamentos.where((l) => l.status == 'pendente' && l.tipo == 'despesa' && _texto(l)).length;
  int get atrasadas => lancamentos.where((l) => atrasada(l) && _texto(l)).length;
  int get aPagarNoPeriodo => lancamentos
      .where((l) => l.status == 'pendente' && l.tipo == 'despesa' && noPeriodo(l) && _texto(l))
      .fold(0, (s, l) => s + l.valorCentavos);
}

class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.dados});

  final _Dados dados;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    Widget cartao(String chave, String rotulo, String valor, String nota, IconData icone, MaterialColor cor) => Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(rotulo.toUpperCase(),
                      style: tema.textTheme.labelSmall?.copyWith(color: tema.colorScheme.onSurfaceVariant, letterSpacing: .6)),
                ),
                Icon(icone, size: 20, color: corIcone(context, cor)),
              ]),
              const SizedBox(height: 8),
              Text(valor,
                  key: Key('kpi_$chave'),
                  style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: corIcone(context, cor))),
              const SizedBox(height: 4),
              Text(nota, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
            ]),
          ),
        );
    final itens = [
      cartao('compromissos', 'Compromissos', '${dados.eventos.length}', 'no período', Icons.event_outlined, Colors.lightBlue),
      cartao('abertas', 'Contas em aberto', '${dados.abertas}', 'despesas pendentes no total', Icons.receipt_long_outlined, Colors.amber),
      cartao('atrasadas', 'Atrasadas', '${dados.atrasadas}', 'vencidas e não pagas', Icons.warning_amber_outlined, Colors.red),
      cartao('a_pagar', 'A pagar no período', formatarCentavos(dados.aPagarNoPeriodo), 'despesas pendentes', Icons.payments_outlined, Colors.green),
      cartao('remedios', 'Remédios', '${dados.medicamentos.length}', 'cadastrados', Icons.medication_outlined, Colors.purple),
    ];
    return LayoutBuilder(builder: (context, c) {
      final colunas = c.maxWidth >= 1000 ? 5 : c.maxWidth >= 640 ? 3 : 2;
      final larg = (c.maxWidth - 12 * (colunas - 1)) / colunas;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final i in itens) SizedBox(width: larg, child: i)]);
    });
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, this.cor);

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: cor.withValues(alpha: .18), borderRadius: BorderRadius.circular(6)),
        child: Text(texto, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}
