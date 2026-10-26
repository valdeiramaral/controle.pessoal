import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/aparencia.dart';
import '../auth/sessao.dart';
import '../nav/menu_lateral.dart';

/// Cada usuario escolhe o proprio padrao: tema (claro, escuro ou do sistema), tamanho da letra
/// e cor do sistema. A mudanca vale na hora e fica guardada na conta.
class AparenciaPage extends ConsumerStatefulWidget {
  const AparenciaPage({super.key});

  @override
  ConsumerState<AparenciaPage> createState() => _AparenciaPageState();
}

class _AparenciaPageState extends ConsumerState<AparenciaPage> {
  String? _erro;

  Future<void> _definir(Aparencia nova) async {
    final erro = await ref.read(sessaoProvider.notifier).definirAparencia(nova);
    if (mounted) setState(() => _erro = erro == null ? null : 'Não foi possível guardar na conta: $erro');
  }

  @override
  Widget build(BuildContext context) {
    final atual = ref.watch(aparenciaProvider);
    final tema = Theme.of(context);

    Widget secao(String titulo, String? ajuda, Widget filho) => Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: tema.textTheme.titleMedium),
              if (ajuda != null) ...[
                const SizedBox(height: 4),
                Text(ajuda, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              filho,
            ]),
          ),
        );

    return Scaffold(
      appBar: const BarraPagina(title: Text('Aparência')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                secao(
                  'Tema',
                  'Sistema segue o claro/escuro do seu aparelho.',
                  SegmentedButton<ModoAparencia>(
                    key: const Key('seletor_modo'),
                    showSelectedIcon: false,
                    segments: [
                      for (final m in ModoAparencia.values)
                        ButtonSegment(value: m, label: Text(m.nome), icon: Icon(m.icone, size: 18)),
                    ],
                    selected: {atual.modo},
                    onSelectionChanged: (v) => _definir(atual.copiarCom(modo: v.first)),
                  ),
                ),
                secao(
                  'Tamanho da letra',
                  null,
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final e in escalasLetra)
                        ChoiceChip(
                          key: Key('letra_${e.$1}'),
                          label: Text(e.$1),
                          selected: atual.escala == e.$2,
                          onSelected: (_) => _definir(atual.copiarCom(escala: e.$2)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Text('Assim fica o texto do aplicativo.', style: tema.textTheme.bodyLarge),
                  ]),
                ),
                secao(
                  'Cor do sistema',
                  'Muda o fundo, o menu e os botões.',
                  Wrap(spacing: 14, runSpacing: 14, children: [
                    for (final c in coresSistema)
                      Tooltip(
                        message: c.nome,
                        child: InkWell(
                          key: Key('cor_${c.codigo}'),
                          customBorder: const CircleBorder(),
                          onTap: () => _definir(atual.copiarCom(cor: c.codigo)),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: c.fundo),
                              border: Border.all(
                                  color: atual.cor == c.codigo ? tema.colorScheme.onSurface : Colors.transparent, width: 3),
                            ),
                            child: atual.cor == c.codigo ? const Icon(Icons.check, color: Colors.white) : null,
                          ),
                        ),
                      ),
                  ]),
                ),
                if (_erro != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_erro!, style: TextStyle(color: tema.colorScheme.error))),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('restaurar_aparencia'),
                    onPressed: atual == Aparencia.padrao ? null : () => _definir(Aparencia.padrao),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restaurar padrão'),
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
