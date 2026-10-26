import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin/perfis_grupos_page.dart';
import '../admin/usuarios_page.dart';
import 'meus_dados_page.dart';
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
            if (logado)
              ListTile(
                key: const Key('menu_meus_dados'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Meus dados'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute<void>(builder: (_) => const MeusDadosPage()));
                },
              ),
            if (logado && s.pode('acesso.usuario.ver'))
              ListTile(
                key: const Key('menu_usuarios'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Usuários e acessos'),
                subtitle: const Text('Cadastrar, liberar módulos e planos'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute<void>(builder: (_) => const UsuariosPage()));
                },
              ),
            if (logado &&
                s.pode('acesso.usuario.ver') &&
                (s.pode('acesso.perfil.gerenciar') || s.pode('acesso.grupo.gerenciar')))
              ListTile(
                key: const Key('menu_perfis_grupos'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Perfis e grupos'),
                subtitle: const Text('Permissões detalhadas por perfil e grupo'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute<void>(builder: (_) => const PerfisGruposPage()));
                },
              ),
            const SizedBox(height: 8),
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
