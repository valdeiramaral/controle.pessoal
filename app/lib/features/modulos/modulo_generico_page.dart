import 'package:flutter/material.dart';

import '../../core/icones_modulo.dart';
import '../../data/api/cliente_api.dart';
import '../nav/menu_lateral.dart';

/// Tela de um modulo cadastrado pelo administrador (os recursos dele chegam nas proximas versoes).
class ModuloGenericoPage extends StatelessWidget {
  const ModuloGenericoPage({super.key, required this.modulo});

  final ModuloMenu modulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: BarraPagina(title: Text(modulo.nome)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(iconeDoModulo(modulo.icone), size: 36, color: tema.colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(modulo.nome, style: tema.textTheme.titleLarge),
                    if ((modulo.descricao ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(modulo.descricao!),
                    ],
                    const SizedBox(height: 12),
                    Text('Este módulo já está liberado para você. Os recursos dele serão adicionados nas próximas versões.',
                        key: const Key('modulo_em_breve'), style: tema.textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
