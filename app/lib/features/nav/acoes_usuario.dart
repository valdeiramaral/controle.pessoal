import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/conta_sheet.dart';
import '../auth/sessao.dart';

/// Acoes fixas no canto da barra de titulo de todas as telas: nome e e-mail de quem
/// esta logado, o icone da conta e o botao Sair. Em telas estreitas so ficam os icones.
class AcoesUsuario extends ConsumerWidget {
  const AcoesUsuario({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessaoProvider);
    if (s.fase != FaseSessao.logado) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final nome = s.usuario?.nome ?? 'Conta';
    final email = s.usuario?.email;
    final largo = MediaQuery.sizeOf(context).width >= 760;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (largo)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Column(
              key: const Key('usuario_topo'),
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(nome,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: tema.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                if (email != null)
                  Text(email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        IconButton(
          key: const Key('botao_conta_topo'),
          tooltip: largo ? 'Conta' : '$nome${email == null ? '' : '\n$email'}',
          icon: Icon(Icons.account_circle_outlined, color: corConta(context)),
          onPressed: () => mostrarConta(context),
        ),
        IconButton(
          key: const Key('botao_sair_topo'),
          tooltip: 'Sair',
          icon: Icon(Icons.logout, color: Colors.red.shade300),
          onPressed: () => ref.read(sessaoProvider.notifier).sair(),
        ),
      ]),
    );
  }

  static Color corConta(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.cyan.shade200 : Colors.cyan.shade700;
}
