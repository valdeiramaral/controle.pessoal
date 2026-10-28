import 'package:flutter/material.dart';

import '../../core/leitura_calculo.dart';

/// Cinco simbolos tocaveis (bolinha, estrela, coracao ou triangulo) para dar a nota de um tema.
class NotaTema extends StatelessWidget {
  const NotaTema({super.key, required this.tema, required this.nota, this.onChanged, this.tamanho = 28});

  final TemaLeitura tema;
  final int nota;
  final ValueChanged<int>? onChanged;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.primary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= notaMaximaTema; i++)
        InkResponse(
          key: Key('nota_${tema.codigo}_$i'),
          onTap: onChanged == null ? null : () => onChanged!(novaNota(nota, i)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(i <= nota ? tema.cheio : tema.vazio, size: tamanho, color: cor),
          ),
        ),
    ]);
  }
}
