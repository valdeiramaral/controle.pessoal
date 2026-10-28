import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nav/menu_lateral.dart';

import '../../core/formatos.dart';
import '../../core/notificacoes.dart';
import '../../core/tarefas_calculo.dart';
import '../../data/local/banco.dart';
import 'quadro_aba.dart';
import 'tarefa_form_page.dart';
import 'tarefas_aba.dart';

class AgendaPage extends ConsumerStatefulWidget {
  const AgendaPage({super.key, this.titulo = 'Agenda'});

  /// Nome do modulo como esta no cadastro de modulos.
  final String titulo;

  @override
  ConsumerState<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends ConsumerState<AgendaPage> with SingleTickerProviderStateMixin {
  late final TabController _abas = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));

  @override
  void dispose() {
    _abas.dispose();
    super.dispose();
  }

  Widget _compromissos(Banco banco) => StreamBuilder<List<Evento>>(
        stream: banco.observarEventosFuturos(),
        builder: (context, snap) {
          final itens = snap.data ?? const <Evento>[];
          if (itens.isEmpty) {
            return const Center(child: Text('Nenhum compromisso à frente.'));
          }
          return ListView.separated(
            itemCount: itens.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = itens[i];
              return Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) {
                  ServicoNotificacoes.instancia.cancelar(ServicoNotificacoes.idNumerico(e.id));
                  banco.excluirEvento(e.id);
                },
                child: ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: Text(e.titulo),
                  subtitle: Text(formatarDataHora(e.inicio)),
                ),
              );
            },
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final banco = ref.watch(bancoProvider);
    final aba = _abas.index; // 0 quadro | 1 tarefas | 2 compromissos
    return Scaffold(
      appBar: BarraPagina(title: Text(widget.titulo)),
      body: Column(children: [
        TabBar(
          controller: _abas,
          tabs: const [
            Tab(key: Key('aba_quadro'), icon: Icon(Icons.view_week_outlined), text: 'Quadro'),
            Tab(key: Key('aba_tarefas'), icon: Icon(Icons.task_alt_outlined), text: 'Tarefas'),
            Tab(key: Key('aba_compromissos'), icon: Icon(Icons.event_outlined), text: 'Compromissos'),
          ],
        ),
        Expanded(
          child: TabBarView(controller: _abas, children: [
            const QuadroAba(),
            const TarefasAba(),
            _compromissos(banco),
          ]),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        key: Key(aba == 2 ? 'fab_novo_compromisso' : aba == 1 ? 'fab_nova_tarefa' : 'fab_novo_quadro'),
        tooltip: aba == 2 ? 'Novo compromisso' : aba == 1 ? 'Nova tarefa' : 'Novo',
        onPressed: () => aba == 2
            ? _novoEvento(context, banco)
            : aba == 1
                ? abrirFormularioTarefa(context)
                : _escolherNovo(context, banco),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// No quadro, o + pergunta o que cadastrar: tarefa ou compromisso.
  Future<void> _escolherNovo(BuildContext context, Banco banco) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('novo_tarefa'),
            leading: const Icon(Icons.task_alt_outlined, color: corTarefaQuadro),
            title: const Text('Nova tarefa'),
            onTap: () => Navigator.pop(ctx, 'tarefa'),
          ),
          ListTile(
            key: const Key('novo_compromisso'),
            leading: const Icon(Icons.event_outlined, color: corCompromissoQuadro),
            title: const Text('Novo compromisso'),
            onTap: () => Navigator.pop(ctx, 'compromisso'),
          ),
        ]),
      ),
    );
    if (!context.mounted || r == null) return;
    if (r == 'tarefa') {
      await abrirFormularioTarefa(context);
    } else {
      await _novoEvento(context, banco);
    }
  }

  Future<void> _novoEvento(BuildContext context, Banco banco) async {
    final titulo = TextEditingController();
    var quando = DateTime.now().add(const Duration(hours: 1));

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Novo compromisso'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titulo,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(formatarDataHora(quando)),
                onPressed: () async {
                  final data = await showDatePicker(
                    context: context,
                    initialDate: quando,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (data == null || !context.mounted) return;
                  final hora = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(quando),
                  );
                  if (hora == null) return;
                  setState(() => quando = DateTime(
                      data.year, data.month, data.day, hora.hour, hora.minute));
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (titulo.text.trim().isEmpty) return;
                final id = await banco.inserirEvento(
                    titulo: titulo.text.trim(), inicio: quando);
                // Lembrete local 30 minutos antes.
                await ServicoNotificacoes.instancia.agendar(
                  id: ServicoNotificacoes.idNumerico(id),
                  titulo: titulo.text.trim(),
                  corpo: 'Começa às ${formatarDataHora(quando)}',
                  quando: quando.subtract(const Duration(minutes: 30)),
                );
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
