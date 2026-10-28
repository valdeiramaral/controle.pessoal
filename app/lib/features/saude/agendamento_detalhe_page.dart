import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatos.dart';
import '../../core/lembretes_saude.dart';
import '../../core/saude_calculo.dart';
import '../../data/local/banco.dart';
import 'agendamento_form_page.dart';

/// Abre o detalhe do agendamento. Devolve true se algo mudou.
Future<bool?> abrirDetalheAgendamento(BuildContext context, String id) =>
    Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AgendamentoDetalhePage(id: id)));

/// Detalhe de consulta/exame: dados, resultado e acoes (realizado, cancelar, faltei, editar, excluir).
class AgendamentoDetalhePage extends ConsumerStatefulWidget {
  const AgendamentoDetalhePage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<AgendamentoDetalhePage> createState() => _AgendamentoDetalhePageState();
}

class _AgendamentoDetalhePageState extends ConsumerState<AgendamentoDetalhePage> {
  AgendamentoSaude? _a;
  bool _carregado = false;
  bool _mudou = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final a = await ref.read(bancoProvider).agendamentoPorId(widget.id);
    if (!mounted) return;
    if (a == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _a = a;
      _carregado = true;
    });
  }

  Future<void> _mudarStatus(String status, {String? resultado}) async {
    final banco = ref.read(bancoProvider);
    await banco.definirStatusAgendamento(_a!, status, resultado: resultado);
    final novo = await banco.agendamentoPorId(widget.id);
    if (novo != null) await LembretesSaude.agendarAgendamento(novo);
    _mudou = true;
    await _carregar();
  }

  Future<void> _realizado() async {
    final c = TextEditingController(text: _a!.resultado ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como realizado'),
        content: TextField(
          key: const Key('campo_resultado_ag'),
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Resultado ou anotações (opcional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(key: const Key('confirmar_realizado'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    // Nao descartar o controller aqui: o dialogo ainda esta sumindo e usa o campo de texto.
    final texto = c.text.trim();
    if (ok == true) await _mudarStatus('realizado', resultado: texto);
  }

  Future<void> _confirmarStatus(String status, String titulo, String texto, Key chave) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(key: chave, onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) await _mudarStatus(status);
  }

  Future<void> _editar() async {
    final salvou = await abrirFormularioAgendamento(context, agendamento: _a);
    if (salvou == true) {
      _mudou = true;
      await _carregar();
    }
  }

  Future<void> _excluir() async {
    final banco = ref.read(bancoProvider);
    final a = _a!;
    final seguintes = await banco.contarSeguintesAgendamento(a);
    if (!mounted) return;
    final escolha = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir agendamento?'),
        content: Text(seguintes > 0
            ? 'Este agendamento faz parte de uma série com mais $seguintes depois dele.'
            : 'O agendamento será removido, inclusive da Agenda.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('excluir_so_este_ag'),
            onPressed: () => Navigator.pop(ctx, 'este'),
            child: Text(seguintes > 0 ? 'Só este' : 'Excluir'),
          ),
          if (seguintes > 0)
            FilledButton(
              key: const Key('excluir_este_e_seguintes_ag'),
              onPressed: () => Navigator.pop(ctx, 'seguintes'),
              child: const Text('Este e os seguintes'),
            ),
        ],
      ),
    );
    if (escolha == null) return;
    final removidos = await banco.excluirAgendamento(a, seguintes: escolha == 'seguintes');
    for (final r in removidos) {
      await LembretesSaude.cancelarAgendamento(r);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _linha(String chave, IconData icone, String rotulo, String? valor) {
    if (valor == null || valor.isEmpty) return const SizedBox.shrink();
    return ListTile(
      key: Key(chave),
      leading: Icon(icone),
      title: Text(valor),
      subtitle: Text(rotulo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _mudou);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(a == null ? 'Agendamento' : (tiposAgendamento[a.tipo] ?? 'Agendamento')),
          actions: a == null
              ? null
              : [
                  IconButton(key: const Key('botao_editar_ag'), tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: _editar),
                  IconButton(key: const Key('botao_excluir_ag'), tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
                ],
        ),
        body: !_carregado || a == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      ListTile(
                        title: Text(a.titulo, key: const Key('det_ag_titulo'), style: Theme.of(context).textTheme.titleLarge),
                        subtitle: Text(statusAgendamento[a.status] ?? a.status, key: const Key('det_ag_status')),
                      ),
                      _linha('det_ag_quando', Icons.event_outlined, 'Data e hora', formatarDataHora(a.dataHora)),
                      _linha('det_ag_especialidade', Icons.local_hospital_outlined, 'Especialidade', a.especialidade),
                      _linha('det_ag_profissional', Icons.person_outline, 'Médico/profissional', a.profissional),
                      _linha('det_ag_local', Icons.place_outlined, 'Local', a.local),
                      _linha('det_ag_lembrete', Icons.notifications_outlined, 'Lembrete',
                          a.lembreteMin == null ? 'Sem lembrete' : antecedenciasLembrete[a.lembreteMin] ?? '${a.lembreteMin} minutos antes'),
                      _linha('det_ag_preparo', Icons.rule_outlined, 'Preparo', a.preparo),
                      _linha('det_ag_obs', Icons.notes_outlined, 'Observação', a.observacao),
                      _linha('det_ag_resultado', Icons.assignment_turned_in_outlined, 'Resultado/anotações', a.resultado),
                      if (a.grupoSerie != null)
                        _linha('det_ag_serie', Icons.repeat, 'Série periódica',
                            '${rotuloRepeticao(a.repeticao)} · ${a.serieNumero} de ${a.serieTotal}'),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (a.status != 'realizado')
                              FilledButton.icon(
                                key: const Key('botao_ag_realizado'),
                                icon: const Icon(Icons.check),
                                label: const Text('Realizado'),
                                onPressed: _realizado,
                              ),
                            if (a.status == 'agendado') ...[
                              OutlinedButton(
                                key: const Key('botao_ag_faltei'),
                                onPressed: () => _confirmarStatus('faltou', 'Marcar como faltei?',
                                    'O agendamento sai da Agenda e fica no histórico.', const Key('confirmar_faltei')),
                                child: const Text('Faltei'),
                              ),
                              OutlinedButton(
                                key: const Key('botao_ag_cancelar'),
                                onPressed: () => _confirmarStatus('cancelado', 'Cancelar agendamento?',
                                    'O agendamento sai da Agenda e o lembrete é removido.', const Key('confirmar_cancelar_ag')),
                                child: const Text('Cancelar agendamento'),
                              ),
                            ] else
                              OutlinedButton(
                                key: const Key('botao_ag_reabrir'),
                                onPressed: () => _mudarStatus('agendado'),
                                child: const Text('Voltar para agendado'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
