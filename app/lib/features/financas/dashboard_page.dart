import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard.dart';
import '../../core/formatos.dart';
import '../../data/local/banco.dart';
import 'contas_page.dart';

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String nomeDoMes(DateTime m) => '${_meses[m.month - 1]} de ${m.year}';

/// Cores usadas quando a categoria nao tem cor propria.
const paletaCategorias = <String>[
  '#009688', '#5E35B1', '#FB8C00', '#1E88E5', '#43A047', '#E53935', '#8E24AA', '#00ACC1',
];

Color corDe(String? hex, int indice) {
  final h = (hex != null && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) ? hex : paletaCategorias[indice % paletaCategorias.length];
  return Color(int.parse('FF${h.substring(1)}', radix: 16));
}

String _pct(num v) => '${v.toStringAsFixed(1).replaceAll('.', ',')}%';

/// Dashboard de Financas: saldo, ranking de categorias, visao geral, contas, orcamentos e recorrencia.
class DashboardFinancas extends ConsumerStatefulWidget {
  const DashboardFinancas({super.key, this.hoje});

  /// Data de "hoje" (injetavel nos testes).
  final DateTime? hoje;

  @override
  ConsumerState<DashboardFinancas> createState() => _DashboardFinancasState();
}

class _DashboardFinancasState extends ConsumerState<DashboardFinancas> {
  late DateTime _mes;

  DateTime get _hoje => widget.hoje ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _mes = DateTime(_hoje.year, _hoje.month, 1);
  }

  void _mudarMes(int delta) => setState(() => _mes = DateTime(_mes.year, _mes.month + delta, 1));

  @override
  Widget build(BuildContext context) {
    final banco = ref.watch(bancoProvider);
    return StreamBuilder<List<Conta>>(
      stream: banco.observarContas(),
      builder: (context, sc) => StreamBuilder<List<Categoria>>(
        stream: banco.observarCategorias(),
        builder: (context, scat) => StreamBuilder<List<Lancamento>>(
          stream: banco.observarLancamentos(),
          builder: (context, sl) => StreamBuilder<List<Orcamento>>(
            stream: banco.observarOrcamentos(),
            builder: (context, so) {
              final categorias = scat.data ?? const <Categoria>[];
              final dados = calcularDashboard(
                contas: sc.data ?? const <Conta>[],
                categorias: categorias,
                lancamentos: sl.data ?? const <Lancamento>[],
                orcamentos: so.data ?? const <Orcamento>[],
                mes: _mes,
                hoje: _hoje,
              );
              return SingleChildScrollView(
                key: const Key('dashboard_financas'),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cabecalho(context, banco, categorias),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, c) {
                      final largo = c.maxWidth >= 900;
                      final esquerda = <Widget>[
                        if (largo)
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(flex: 2, child: _CartaoSaldos(dados: dados)),
                            const SizedBox(width: 12),
                            Expanded(flex: 3, child: _CartaoRanking(dados: dados)),
                          ])
                        else ...[
                          _CartaoSaldos(dados: dados),
                          const SizedBox(height: 12),
                          _CartaoRanking(dados: dados),
                        ],
                        const SizedBox(height: 12),
                        _VisaoGeral(dados: dados),
                        const SizedBox(height: 12),
                        _CartaoContas(dados: dados),
                      ];
                      final direita = <Widget>[
                        _CartaoOrcamentos(dados: dados),
                        const SizedBox(height: 12),
                        _CartaoRecorrencia(dados: dados),
                      ];
                      if (!largo) {
                        return Column(children: [...esquerda, const SizedBox(height: 12), ...direita]);
                      }
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 2, child: Column(children: esquerda)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(children: direita)),
                      ]);
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _cabecalho(BuildContext context, Banco banco, List<Categoria> categorias) {
    return Row(children: [
      IconButton(
        key: const Key('mes_anterior'),
        tooltip: 'Mês anterior',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => _mudarMes(-1),
      ),
      Text(nomeDoMes(_mes), key: const Key('mes_titulo'), style: Theme.of(context).textTheme.titleMedium),
      IconButton(
        key: const Key('mes_seguinte'),
        tooltip: 'Próximo mês',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => _mudarMes(1),
      ),
      const Spacer(),
      PopupMenuButton<String>(
        key: const Key('menu_dashboard'),
        tooltip: 'Opções do dashboard',
        onSelected: (v) {
          switch (v) {
            case 'conta':
              abrirFormularioConta(context);
            case 'categoria':
              _novaCategoria(context, banco);
            case 'orcamento':
              _definirOrcamento(context, banco, categorias);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'conta', child: Text('Nova conta')),
          PopupMenuItem(value: 'categoria', child: Text('Nova categoria')),
          PopupMenuItem(value: 'orcamento', child: Text('Definir orçamento do mês')),
        ],
      ),
    ]);
  }

  Future<void> _novaCategoria(BuildContext context, Banco banco) async {
    final nome = TextEditingController();
    var tipo = 'despesa';
    var cor = paletaCategorias.first;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nova categoria'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'despesa', label: Text('Despesa')),
                ButtonSegment(value: 'receita', label: Text('Receita')),
              ],
              selected: {tipo},
              onSelectionChanged: (s) => setState(() => tipo = s.first),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in paletaCategorias)
                InkWell(
                  onTap: () => setState(() => cor = h),
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: corDe(h, 0),
                    child: cor == h ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (nome.text.trim().isEmpty) return;
                await banco.inserirCategoria(nome: nome.text.trim(), tipo: tipo, cor: cor);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _definirOrcamento(BuildContext context, Banco banco, List<Categoria> categorias) async {
    final despesas = categorias.where((c) => c.tipo == 'despesa').toList();
    if (despesas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crie uma categoria de despesa primeiro.')));
      return;
    }
    final valor = TextEditingController();
    var escolhida = despesas.first.id;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Orçamento de ${nomeDoMes(_mes)}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: escolhida,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: [for (final c in despesas) DropdownMenuItem(value: c.id, child: Text(c.nome))],
              onChanged: (v) => setState(() => escolhida = v ?? escolhida),
            ),
            TextField(
              controller: valor,
              keyboardType: TextInputType.number,
              inputFormatters: const [MoedaFormatter()],
              decoration: const InputDecoration(labelText: 'Limite do mês (R\$)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final centavos = centavosDeTexto(valor.text);
                if (centavos == null || centavos <= 0) return;
                await banco.definirOrcamento(categoriaId: escolhida, mes: _mes, valorLimiteCentavos: centavos);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------------------------

class _Cartao extends StatelessWidget {
  const _Cartao({required this.titulo, required this.child, this.chave});

  final String? titulo;
  final Widget child;
  final Key? chave;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: chave,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titulo != null) ...[
              Text(titulo!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _CartaoSaldos extends StatelessWidget {
  const _CartaoSaldos({required this.dados});
  final DadosDashboard dados;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget linha(IconData icone, Color cor, String valor, String rotulo, {bool destaque = false, Key? chave}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icone, color: cor, size: destaque ? 26 : 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(valor,
                    key: chave,
                    style: (destaque ? t.headlineSmall : t.titleMedium)?.copyWith(fontWeight: FontWeight.w600)),
                Text(rotulo, style: t.bodySmall),
              ]),
            ),
          ]),
        );
    return _Cartao(
      titulo: null,
      chave: const Key('cartao_saldos'),
      child: Column(children: [
        linha(Icons.check_circle, cs.primary, formatarCentavos(dados.saldoInicialMesCentavos), 'Inicial',
            chave: const Key('saldo_inicial')),
        linha(Icons.circle, cs.primary, formatarCentavos(dados.saldoAtualCentavos), 'Saldo atual',
            destaque: true, chave: const Key('saldo_atual')),
        linha(Icons.schedule, cs.outline, formatarCentavos(dados.previstoCentavos), 'Previsto',
            chave: const Key('saldo_previsto')),
      ]),
    );
  }
}

class _CartaoRanking extends StatelessWidget {
  const _CartaoRanking({required this.dados});
  final DadosDashboard dados;

  @override
  Widget build(BuildContext context) {
    final itens = dados.ranking;
    final maior = itens.isEmpty ? 1 : itens.first.valorCentavos;
    return _Cartao(
      titulo: 'Ranking categorias',
      chave: const Key('cartao_ranking'),
      child: itens.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Sem despesas neste mês.'))
          : Column(children: [
              for (var i = 0; i < itens.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                      width: 96,
                      child: Text(itens[i].nome, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(
                      child: Stack(alignment: Alignment.centerLeft, children: [
                        Container(height: 20, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .4), borderRadius: BorderRadius.circular(10))),
                        FractionallySizedBox(
                          widthFactor: (itens[i].valorCentavos / maior).clamp(0.04, 1.0).toDouble(),
                          child: Container(
                            height: 20,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(color: corDe(itens[i].cor, i), borderRadius: BorderRadius.circular(10)),
                            child: Text(_pct(itens[i].percentual),
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),
              Text(
                'Essas categorias totalizam ${formatarCentavos(dados.despesasCentavos)}. '
                'Elas representam 100% de ${formatarCentavos(dados.despesasCentavos)}.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
    );
  }
}

class _VisaoGeral extends StatelessWidget {
  const _VisaoGeral({required this.dados});
  final DadosDashboard dados;

  @override
  Widget build(BuildContext context) {
    final itens = <_Indicador>[
      _Indicador(Icons.account_balance, Colors.blue, dados.saldoAtualCentavos, 'Saldo nas contas', dados.varSaldo, true, 'ind_saldo'),
      _Indicador(Icons.add, Colors.green, dados.receitasCentavos, 'Total recebido', dados.varReceitas, true, 'ind_recebido'),
      _Indicador(Icons.remove, Colors.red, dados.despesasCentavos, 'Total gasto', dados.varDespesas, false, 'ind_gasto'),
      _Indicador(Icons.credit_card, Colors.indigo, dados.faturasCentavos, 'Total faturas', dados.varFaturas, false, 'ind_faturas'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('Visão geral', style: Theme.of(context).textTheme.titleMedium),
      ),
      LayoutBuilder(builder: (context, c) {
        final n = c.maxWidth >= 700 ? 4 : 2;
        final w = (c.maxWidth - 12 * (n - 1)) / n;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final i in itens) SizedBox(width: w, child: _CartaoIndicador(i)),
        ]);
      }),
    ]);
  }
}

class _Indicador {
  const _Indicador(this.icone, this.cor, this.centavos, this.rotulo, this.variacao, this.altaEBoa, this.chave);
  final IconData icone;
  final Color cor;
  final int centavos;
  final String rotulo;
  final int? variacao;
  final bool altaEBoa;
  final String chave;
}

class _CartaoIndicador extends StatelessWidget {
  const _CartaoIndicador(this.i);
  final _Indicador i;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final v = i.variacao;
    final subiu = (v ?? 0) >= 0;
    final bom = subiu == i.altaEBoa;
    final corVar = bom ? Colors.green.shade700 : Colors.red.shade700;
    return _Cartao(
      titulo: null,
      child: Row(children: [
        CircleAvatar(backgroundColor: i.cor, child: Icon(i.icone, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatarCentavos(i.centavos),
                key: Key(i.chave), style: t.titleMedium?.copyWith(color: i.cor, fontWeight: FontWeight.w600)),
            Text(i.rotulo, style: t.bodySmall),
            const SizedBox(height: 6),
            if (v != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: corVar.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(subiu ? Icons.north_east : Icons.south_east, size: 13, color: corVar),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('${v.abs()}% vs. mês anterior',
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: corVar)),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _CartaoContas extends StatelessWidget {
  const _CartaoContas({required this.dados});
  final DadosDashboard dados;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    TableRow cabecalho() => TableRow(children: [
          for (final h in ['Descrição', 'Receitas', 'Despesas', 'Saldo', 'Previsto'])
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(h, style: t.bodySmall)),
        ]);
    TableRow linha(LinhaConta c) => TableRow(children: [
          for (final v in [c.nome, formatarCentavos(c.receitasCentavos), formatarCentavos(c.despesasCentavos), formatarCentavos(c.saldoCentavos), formatarCentavos(c.previstoCentavos)])
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(v, style: t.bodyMedium)),
        ]);
    return _Cartao(
      titulo: 'Contas',
      chave: const Key('cartao_contas'),
      child: LayoutBuilder(builder: (context, c) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(c.maxWidth, 560),
            child: Table(
              columnWidths: const {0: FlexColumnWidth(1.6)},
              border: TableBorder(horizontalInside: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .5))),
              children: [cabecalho(), for (final conta in dados.contas) linha(conta)],
            ),
          ),
        );
      }),
    );
  }
}

class _CartaoOrcamentos extends StatelessWidget {
  const _CartaoOrcamentos({required this.dados});
  final DadosDashboard dados;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final itens = dados.orcamentos;
    final prog = dados.progressoDoMes;
    return _Cartao(
      titulo: 'Orçamentos de despesas',
      chave: const Key('cartao_orcamentos'),
      child: itens.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Nenhum orçamento neste mês. Use o menu ⋮ para definir.'),
            )
          : Column(children: [
              for (var i = 0; i < itens.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: corDe(itens[i].cor, i),
                      child: Text(itens[i].categoria.isEmpty ? '?' : itens[i].categoria[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(itens[i].categoria, style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
                          Text(formatarCentavos(itens[i].gastoCentavos),
                              style: t.bodyMedium?.copyWith(color: itens[i].estourou ? Colors.red : null, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 14,
                          child: Stack(children: [
                            Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(7))),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (itens[i].percentual / 100).clamp(0.02, 1.0).toDouble(),
                              child: Container(decoration: BoxDecoration(color: itens[i].estourou ? Colors.red : corDe(itens[i].cor, i), borderRadius: BorderRadius.circular(7))),
                            ),
                            if (prog != null)
                              Align(
                                alignment: Alignment(prog * 2 - 1, 0),
                                child: Container(width: 2, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5)),
                              ),
                          ]),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text('${itens[i].percentual}% de ${formatarCentavos(itens[i].limiteCentavos)}', style: t.labelSmall),
                        ),
                      ]),
                    ),
                  ]),
                ),
              if (prog != null)
                Align(
                  alignment: Alignment(prog * 2 - 1, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
                    child: Text('Hoje', style: t.labelSmall),
                  ),
                ),
            ]),
    );
  }
}

const _coresRecorrencia = [Color(0xFFDB4437), Color(0xFFF4B400), Color(0xFF4285F4)];

class _CartaoRecorrencia extends StatelessWidget {
  const _CartaoRecorrencia({required this.dados});
  final DadosDashboard dados;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final total = dados.totalRecorrenciaCentavos;
    return _Cartao(
      titulo: 'Despesas por recorrência',
      chave: const Key('cartao_recorrencia'),
      child: Column(children: [
        SizedBox(
          width: 220,
          height: 220,
          child: CustomPaint(
            painter: _RoscaPainter(
              valores: [for (final f in dados.recorrencia) f.valorCentavos.toDouble()],
              cores: _coresRecorrencia,
              vazio: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Text(formatarCentavos(total), key: const Key('rosca_total'), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < dados.recorrencia.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.circle, size: 12, color: _coresRecorrencia[i]),
              const SizedBox(width: 8),
              Expanded(child: Text(dados.recorrencia[i].nome)),
              Text(formatarCentavos(dados.recorrencia[i].valorCentavos)),
              SizedBox(width: 56, child: Text(_pct(dados.recorrencia[i].percentual), textAlign: TextAlign.end, style: t.bodySmall)),
            ]),
          ),
      ]),
    );
  }
}

class _RoscaPainter extends CustomPainter {
  _RoscaPainter({required this.valores, required this.cores, required this.vazio});

  final List<double> valores;
  final List<Color> cores;
  final Color vazio;

  @override
  void paint(Canvas canvas, Size size) {
    final espessura = size.shortestSide * 0.16;
    final rect = (Offset(espessura / 2, espessura / 2) & Size(size.width - espessura, size.height - espessura));
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = espessura;
    final total = valores.fold<double>(0, (s, v) => s + v);
    if (total <= 0) {
      canvas.drawArc(rect, 0, 2 * math.pi, false, pincel..color = vazio);
      return;
    }
    var inicio = -math.pi / 2;
    for (var i = 0; i < valores.length; i++) {
      if (valores[i] <= 0) continue;
      final varredura = valores[i] / total * 2 * math.pi;
      canvas.drawArc(rect, inicio, varredura, false, pincel..color = cores[i % cores.length]);
      inicio += varredura;
    }
  }

  @override
  bool shouldRepaint(_RoscaPainter old) => old.valores != valores || old.cores != cores || old.vazio != vazio;
}
