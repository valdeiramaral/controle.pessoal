import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icones_modulo.dart';
import '../admin/modulos_page.dart';
import '../admin/perfis_grupos_page.dart';
import '../admin/usuarios_page.dart';
import '../aparencia/aparencia_page.dart';
import '../auth/meus_dados_page.dart';
import '../auth/sessao.dart';
import '../auth/widgets_auth.dart';
import 'modulos_menu.dart';

/// Abaixo desta largura o menu fica sempre suspenso (some e abre por cima).
const larguraMinimaMenuFixo = 760.0;

/// Menu recolhido (so icones) quando fixo.
final menuRecolhidoProvider = StateProvider<bool>((_) => false);

/// Preferencia, em telas largas, por deixar o menu suspenso em vez de fixo.
final menuSuspensoProvider = StateProvider<bool>((_) => false);

/// Navegador da area de conteudo (ao lado do menu): telas de cadastro abrem aqui
/// dentro, sem cobrir o menu lateral.
final chaveConteudo = GlobalKey<NavigatorState>();

/// Abre uma tela na area de conteudo, mantendo o menu visivel.
Future<T?> abrirNoConteudo<T>(BuildContext context, Widget pagina) {
  final nav = chaveConteudo.currentState ?? Navigator.of(context);
  return nav.push<T>(MaterialPageRoute<T>(builder: (_) => pagina));
}

/// Chave do Scaffold principal, para as paginas abrirem o menu suspenso.
final chaveCasca = GlobalKey<ScaffoldState>();

bool menuEmModoSuspenso(BuildContext context, bool preferencia) =>
    MediaQuery.sizeOf(context).width < larguraMinimaMenuFixo || preferencia;

/// Barra de titulo das paginas principais; mostra o botao do menu quando ele esta suspenso.
class BarraPagina extends ConsumerWidget implements PreferredSizeWidget {
  const BarraPagina({super.key, required this.title, this.actions});

  final Widget title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suspenso = menuEmModoSuspenso(context, ref.watch(menuSuspensoProvider));
    return AppBar(
      automaticallyImplyLeading: false,
      leading: suspenso
          ? IconButton(
              key: const Key('botao_menu'),
              tooltip: 'Menu',
              icon: const Icon(Icons.menu),
              onPressed: () => chaveCasca.currentState?.openDrawer(),
            )
          : null,
      titleSpacing: suspenso ? null : 20,
      title: title,
      actions: actions,
    );
  }
}

/// Menu lateral: modulos, administracao (por permissao) e conta.
/// Fixo (expandido ou so com icones) ou dentro do Drawer, quando suspenso.
class MenuLateral extends ConsumerWidget {
  const MenuLateral({super.key, required this.indice, required this.aoIr, this.emDrawer = false});

  final int indice;
  final ValueChanged<int> aoIr;
  final bool emDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessaoProvider);
    final logado = s.fase == FaseSessao.logado;
    final recolhido = !emDrawer && ref.watch(menuRecolhidoProvider);
    final largo = MediaQuery.sizeOf(context).width >= larguraMinimaMenuFixo;

    void abrir(Widget pagina) {
      final destino = chaveConteudo.currentState ?? Navigator.of(context);
      if (emDrawer) Navigator.of(context).pop();
      destino.push(MaterialPageRoute<void>(builder: (_) => pagina));
    }

    // Modulos de fabrica + os cadastrados pelo administrador (aparecem aqui assim que criados).
    final extras = ref.watch(modulosMenuProvider).valueOrNull ?? const [];
    // O menu e sempre escuro, entao os icones usam o tom claro (shade300) de cada cor.
    final modulos = <(IconData, String, Color)>[
      (Icons.today_outlined, 'Hoje', Colors.amber.shade300),
      (Icons.account_balance_wallet_outlined, 'Finanças', Colors.lightGreen.shade300),
      (Icons.favorite_border, 'Saúde', Colors.pink.shade200),
      (Icons.event_outlined, 'Agenda', Colors.lightBlue.shade300),
      for (final m in extras)
        (iconeDoModulo(m.icone), m.donoNome == null ? m.nome : '${m.nome} · ${m.donoNome}', corBaseDoModulo(m.icone).shade300),
    ];
    final admin = <(IconData, String, Widget, Color)>[
      if (logado && s.pode('acesso.usuario.ver'))
        (Icons.manage_accounts_outlined, 'Usuários e acessos', const UsuariosPage(), Colors.teal.shade200),
      if (logado &&
          s.superusuario &&
          s.pode('acesso.usuario.ver') &&
          (s.pode('acesso.perfil.gerenciar') || s.pode('acesso.grupo.gerenciar')))
        (Icons.admin_panel_settings_outlined, 'Perfis e grupos', const PerfisGruposPage(), Colors.deepPurple.shade200),
      if (logado && s.superusuario && s.pode('administracao.modulo.gerenciar'))
        (Icons.extension_outlined, 'Módulos', const ModulosPage(), Colors.orange.shade300),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: emDrawer ? 280 : (recolhido ? 76 : 250),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: ref.watch(aparenciaProvider).corSistema.menu,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cabecalho(recolhido: recolhido, emDrawer: emDrawer, largo: largo),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (var i = 0; i < modulos.length; i++)
                      _Item(
                        icone: modulos[i].$1,
                        cor: modulos[i].$3,
                        rotulo: modulos[i].$2,
                        selecionado: indice == i,
                        recolhido: recolhido,
                        aoTocar: () => aoIr(i),
                      ),
                    if (admin.isNotEmpty) ...[
                      const _Secao('Administração'),
                      for (final a in admin)
                        _Item(icone: a.$1, cor: a.$4, rotulo: a.$2, recolhido: recolhido, aoTocar: () => abrir(a.$3)),
                    ],
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(children: [
                  if (logado)
                    _Item(
                      icone: Icons.badge_outlined,
                      cor: Colors.cyan.shade200,
                      rotulo: 'Meus dados',
                      recolhido: recolhido,
                      aoTocar: () => abrir(const MeusDadosPage()),
                    ),
                  if (logado)
                    _Item(
                      chave: const Key('menu_aparencia'),
                      icone: Icons.palette_outlined,
                      cor: Colors.pinkAccent.shade100,
                      rotulo: 'Aparência',
                      recolhido: recolhido,
                      aoTocar: () => abrir(const AparenciaPage()),
                    ),
                  _Item(
                    chave: const Key('menu_sair'),
                    icone: logado ? Icons.logout : Icons.login,
                    cor: Colors.red.shade200,
                    rotulo: logado ? 'Sair' : 'Entrar ou criar conta',
                    recolhido: recolhido,
                    aoTocar: () {
                      if (emDrawer) Navigator.of(context).pop();
                      ref.read(sessaoProvider.notifier).sair();
                    },
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cabecalho extends ConsumerWidget {
  const _Cabecalho({required this.recolhido, required this.emDrawer, required this.largo});

  final bool recolhido;
  final bool emDrawer;
  final bool largo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recolher = IconButton(
      key: const Key('menu_recolher'),
      tooltip: recolhido ? 'Expandir menu' : 'Recolher menu',
      color: Colors.white70,
      icon: Icon(recolhido ? Icons.chevron_right : Icons.chevron_left),
      onPressed: () => ref.read(menuRecolhidoProvider.notifier).state = !recolhido,
    );
    if (recolhido) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(children: [
          Theme(data: temaAzul(context), child: const MarcaApp(tamanho: 38)),
          const SizedBox(height: 4),
          recolher,
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 6, 0),
      child: Row(children: [
        Theme(data: temaAzul(context), child: const MarcaApp(tamanho: 38)),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Controle Pessoal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        if (emDrawer && largo)
          IconButton(
            key: const Key('menu_fixar'),
            tooltip: 'Fixar menu',
            color: Colors.white70,
            icon: const Icon(Icons.push_pin_outlined),
            onPressed: () {
              ref.read(menuSuspensoProvider.notifier).state = false;
              Navigator.of(context).pop();
            },
          )
        else if (!emDrawer) ...[
          if (largo)
            IconButton(
              key: const Key('menu_suspender'),
              tooltip: 'Menu suspenso (ocultar)',
              color: Colors.white70,
              icon: const Icon(Icons.visibility_off_outlined),
              onPressed: () => ref.read(menuSuspensoProvider.notifier).state = true,
            ),
          recolher,
        ],
      ]),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
        child: Text(texto.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
      );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icone,
    required this.cor,
    required this.rotulo,
    required this.recolhido,
    required this.aoTocar,
    this.selecionado = false,
    this.chave,
  });

  final IconData icone;
  final Color cor;
  final String rotulo;
  final bool recolhido;
  final bool selecionado;
  final VoidCallback aoTocar;
  final Key? chave;

  @override
  Widget build(BuildContext context) {
    final corpo = Material(
      color: selecionado ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: chave,
        borderRadius: BorderRadius.circular(12),
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Icon(icone, size: 22, color: cor),
            if (!recolhido) ...[
              const SizedBox(width: 14),
              Expanded(
                child: Text(rotulo,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selecionado ? Colors.white : Colors.white70,
                        fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500)),
              ),
            ],
          ]),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: recolhido ? Tooltip(message: rotulo, child: corpo) : corpo,
    );
  }
}
