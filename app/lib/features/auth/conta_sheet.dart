import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin/perfis_grupos_page.dart';
import '../admin/usuarios_page.dart';
import '../nav/menu_lateral.dart';
import '../sync/sincronizacao.dart';
import 'alterar_senha_page.dart';
import 'meus_dados_page.dart';
import 'sessao.dart';

/// Painel da conta: quem esta logado e o botao Sair.
void mostrarConta(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
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
      child: SingleChildScrollView(
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
            if (logado && s.perfil == null)
              const _AvisoPermissoes(),
            if (logado)
              ListTile(
                key: const Key('menu_meus_dados'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Meus dados'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final destino = chaveConteudo.currentState ?? Navigator.of(context);
                  Navigator.of(context).pop();
                  destino.push(MaterialPageRoute<void>(builder: (_) => const MeusDadosPage()));
                },
              ),
            if (logado)
              ListTile(
                key: const Key('menu_sincronizar'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync),
                title: const Text('Sincronizar agora'),
                subtitle: Text(ref.watch(sessaoProvider.select((x) => x.offline))
                    ? 'Sem internet: trabalhando só neste aparelho. Sincroniza sozinho quando a rede voltar.'
                    : textoSincronizacao(ref.watch(sincronizacaoProvider))),
                onTap: () => sincronizarAgora(context, ref),
              ),
            if (logado)
              ListTile(
                key: const Key('menu_alterar_senha'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_reset),
                title: const Text('Alterar senha'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final destino = chaveConteudo.currentState ?? Navigator.of(context);
                  Navigator.of(context).pop();
                  destino.push(MaterialPageRoute<void>(builder: (_) => const AlterarSenhaPage()));
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
                  final destino = chaveConteudo.currentState ?? Navigator.of(context);
                  Navigator.of(context).pop();
                  destino.push(MaterialPageRoute<void>(builder: (_) => const UsuariosPage()));
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
                  final destino = chaveConteudo.currentState ?? Navigator.of(context);
                  Navigator.of(context).pop();
                  destino.push(MaterialPageRoute<void>(builder: (_) => const PerfisGruposPage()));
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

/// Aparece quando o login deu certo mas as permissoes nao foram carregadas.
class _AvisoPermissoes extends ConsumerStatefulWidget {
  const _AvisoPermissoes();

  @override
  ConsumerState<_AvisoPermissoes> createState() => _AvisoPermissoesState();
}

class _AvisoPermissoesState extends ConsumerState<_AvisoPermissoes> {
  String? _erro;
  bool _carregando = false;

  Future<void> _tentar() async {
    setState(() => _carregando = true);
    final e = await ref.read(sessaoProvider.notifier).recarregarPerfil();
    if (mounted) {
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('aviso_permissoes'),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Não foi possível carregar suas permissões.'),
            if (_erro != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_erro!)),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('botao_recarregar_permissoes'),
              onPressed: _carregando ? null : _tentar,
              child: Text(_carregando ? 'Carregando...' : 'Tentar de novo'),
            ),
          ]),
        ),
      ),
    );
  }
}
