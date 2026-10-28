import 'package:flutter/material.dart';

/// Observacoes e comentarios informados ao concluir uma tarefa ou um compromisso.
typedef DadosConclusao = ({String? observacoes, String? comentarios});

/// Pergunta as observacoes e os comentarios antes de concluir; devolve null se a pessoa cancelar.
Future<DadosConclusao?> pedirDadosDeConclusao(BuildContext context,
    {required String titulo, String? observacoes, String? comentarios, String rotulo = 'Concluir'}) {
  final obs = TextEditingController(text: observacoes ?? '');
  final com = TextEditingController(text: comentarios ?? '');
  return showDialog<DadosConclusao>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$rotulo: $titulo', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('conclusao_observacoes'),
            controller: obs,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Observações', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('conclusao_comentarios'),
            controller: com,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Comentários', alignLabelWithHint: true),
          ),
        ]),
      ),
      actions: [
        TextButton(key: const Key('conclusao_cancelar'), onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('conclusao_confirmar'),
          onPressed: () => Navigator.pop(ctx, (
            observacoes: obs.text.trim().isEmpty ? null : obs.text.trim(),
            comentarios: com.text.trim().isEmpty ? null : com.text.trim(),
          )),
          child: Text(rotulo),
        ),
      ],
    ),
  );
}
