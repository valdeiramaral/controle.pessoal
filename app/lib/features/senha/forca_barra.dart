import 'package:flutter/material.dart';

import '../../core/senha_calculo.dart';

/// Quatro tracos coloridos + "Tempo para quebrar: ...", como no gerenciador de senhas.
class ForcaBarra extends StatelessWidget {
  const ForcaBarra({super.key, required this.senha});

  final String senha;

  @override
  Widget build(BuildContext context) {
    final f = avaliarSenha(senha);
    if (f.nivel == 0) return const SizedBox.shrink();
    final cor = corDaForca(f.nivel);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 240,
        child: Row(children: [
          for (var i = 1; i <= 4; i++)
            Expanded(
              child: Container(
                key: Key('forca_traco_$i'),
                height: 4,
                margin: const EdgeInsets.only(right: 3),
                color: i <= f.nivel ? cor : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
        ]),
      ),
      const SizedBox(height: 2),
      Text('Tempo para quebrar: ${f.tempo}', key: const Key('forca_tempo'), style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
