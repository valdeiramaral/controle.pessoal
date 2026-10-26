import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sessao.dart';

/// Painel da conta: quem esta logado e o botao Sair.
void mostrarConta(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _ContaSheet(),
  );
}

class _ContaSheet extends ConsumerWidget {
  const _ContaSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessaoProvider);
    final logado = s.fase == FaseSessao.logado;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(logado ? (s.usuario?.nome ?? 'Conta') : 'Sem conta neste aparelho',
                style: Theme.of(context).textTheme.titleMedium),
            if (logado && s.usuario?.email != null) Text(s.usuario!.email!),
            if (!logado)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Seus dados ficam só neste aparelho.'),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: Text(logado ? 'Sair' : 'Entrar ou criar conta'),
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(sessaoProvider.notifier).sair();
              },
            ),
          ],
        ),
      ),
    );
  }
}
