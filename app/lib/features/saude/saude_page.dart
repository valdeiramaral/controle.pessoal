import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lembretes_saude.dart';
import '../../data/local/banco.dart';
import '../nav/menu_lateral.dart';
import 'agendamento_form_page.dart';
import 'agendamentos_aba.dart';
import 'medicacao_aba.dart';
import 'medicamento_form_page.dart';

/// Modulo Saude: controle de medicacao (posologia, doses do dia, estoque) e
/// agenda de consultas, exames e retornos (unicos ou periodicos).
class SaudePage extends ConsumerStatefulWidget {
  const SaudePage({super.key, this.agora});
  final DateTime? agora; // para testes

  @override
  ConsumerState<SaudePage> createState() => _SaudePageState();
}

class _SaudePageState extends ConsumerState<SaudePage> with SingleTickerProviderStateMixin {
  late final TabController _abas = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    // Renova os lembretes de doses avulsas (medicamentos "a cada N dias" ou com data final).
    ref.read(bancoProvider).listarMedicamentos().then(LembretesSaude.renovar);
  }

  @override
  void dispose() {
    _abas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final medicacao = _abas.index == 0;
    return Scaffold(
      appBar: const BarraPagina(title: Text('Saúde')),
      body: Column(
        children: [
          TabBar(
            controller: _abas,
            tabs: const [
              Tab(key: Key('aba_medicacao'), icon: Icon(Icons.medication_outlined), text: 'Medicação'),
              Tab(key: Key('aba_agendamentos'), icon: Icon(Icons.event_available_outlined), text: 'Consultas e exames'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _abas,
              children: [
                MedicacaoAba(agora: widget.agora),
                AgendamentosAba(agora: widget.agora),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: Key(medicacao ? 'fab_novo_medicamento' : 'fab_novo_agendamento'),
        icon: const Icon(Icons.add),
        label: Text(medicacao ? 'Medicamento' : 'Agendar'),
        onPressed: () => medicacao
            ? abrirFormularioMedicamento(context, hoje: widget.agora)
            : abrirFormularioAgendamento(context, agora: widget.agora),
      ),
    );
  }
}
