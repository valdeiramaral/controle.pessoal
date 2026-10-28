import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/api/cliente_api.dart';
import 'features/agenda/agenda_page.dart';
import 'features/auth/login_page.dart';
import 'core/tema.dart';
import 'features/auth/sessao.dart';
import 'features/auth/widgets_auth.dart';
import 'features/modulos/modulo_generico_page.dart';
import 'features/nav/menu_lateral.dart';
import 'features/nav/modulos_menu.dart';
import 'features/financas/financas_page.dart';
import 'features/hoje/hoje_page.dart';
import 'features/biblioteca/biblioteca_page.dart';
import 'features/leitura/leitura_page.dart';
import 'features/saude/saude_page.dart';
import 'features/senha/senha_page.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aparencia = ref.watch(aparenciaProvider);
    final cor = aparencia.corSistema;
    return MaterialApp(
      title: 'Central Vida Pessoal',
      debugShowCheckedModeBanner: false,
      theme: temaApp(brilho: Brightness.light, cor: cor),
      darkTheme: temaApp(brilho: Brightness.dark, cor: cor),
      themeMode: aparencia.modo.themeMode,
      builder: (context, child) => MediaQuery(
        // Tamanho da letra escolhido pelo usuario, aplicado a todo o app.
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(aparencia.escala)),
        child: FundoAzul(child: child ?? const SizedBox.shrink()),
      ),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Portao(),
    );
  }
}

/// Decide a tela inicial: carregando, login ou o app.
class _Portao extends ConsumerWidget {
  const _Portao();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fase = ref.watch(sessaoProvider).fase;
    switch (fase) {
      case FaseSessao.iniciando:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case FaseSessao.deslogado:
        return const LoginPage();
      case FaseSessao.logado:
      case FaseSessao.local:
        return const Casca();
    }
  }
}

/// Navegacao principal: menu a esquerda (fixo, recolhido ou suspenso) e as paginas.
/// As telas de cadastro abrem na area de conteudo, sem cobrir o menu.
class Casca extends ConsumerStatefulWidget {
  const Casca({super.key});

  @override
  ConsumerState<Casca> createState() => _CascaState();
}

class _CascaState extends ConsumerState<Casca> {
  final _indice = ValueNotifier<int>(0);

  @override
  void dispose() {
    _indice.dispose();
    super.dispose();
  }

  void _ir(int i, {bool fecharMenu = false}) {
    // Volta da tela de cadastro (se houver) e troca de modulo.
    chaveConteudo.currentState?.popUntil((r) => r.isFirst);
    _indice.value = i;
    if (fecharMenu) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final suspenso = menuEmModoSuspenso(context, ref.watch(menuSuspensoProvider));
    return Scaffold(
      key: chaveCasca,
      drawer: suspenso
          ? Drawer(
              backgroundColor: Colors.transparent,
              elevation: 0,
              width: 292,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ValueListenableBuilder<int>(
                  valueListenable: _indice,
                  builder: (_, i, __) => MenuLateral(emDrawer: true, indice: i, aoIr: (n) => _ir(n, fecharMenu: true)),
                ),
              ),
            )
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!suspenso)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
              child: ValueListenableBuilder<int>(
                valueListenable: _indice,
                builder: (_, i, __) => MenuLateral(indice: i, aoIr: _ir),
              ),
            ),
          Expanded(
            child: NavigatorPopHandler(
              onPop: () => chaveConteudo.currentState?.maybePop(),
              child: Navigator(
                key: chaveConteudo,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Consumer(builder: (context, ref, _) {
                    final itens = modulosDoMenu(ref.watch(modulosMenuProvider));
                    if (itens.isEmpty) return const _SemModulos();
                    final paginas = <Widget>[for (final m in itens) _paginaDoModulo(m)];
                    return ValueListenableBuilder<int>(
                      valueListenable: _indice,
                      builder: (_, i, __) => IndexedStack(index: i < paginas.length ? i : 0, children: paginas),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tela do modulo: as que ja existem no app, ou a tela generica do modulo cadastrado.
Widget _paginaDoModulo(ModuloMenu m) => switch (m.codigo) {
      'painel' => HojePage(key: const ValueKey('painel'), titulo: m.nome),
      'financas' => FinancasPage(key: const ValueKey('financas'), titulo: m.nome),
      'saude' => SaudePage(key: const ValueKey('saude'), titulo: m.nome),
      'agenda' => AgendaPage(key: const ValueKey('agenda'), titulo: m.nome),
      'senha' => SenhaPage(key: const ValueKey('senha'), titulo: m.nome),
      'biblioteca' => BibliotecaPage(key: const ValueKey('biblioteca'), titulo: m.nome),
      'leitura' => LeituraPage(key: const ValueKey('leitura'), titulo: m.nome),
      _ => ModuloGenericoPage(key: ValueKey(m.codigo), modulo: m),
    };

/// Usuario sem nenhum modulo liberado (ou ainda carregando).
class _SemModulos extends StatelessWidget {
  const _SemModulos();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const BarraPagina(title: Text('Central Vida Pessoal')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum módulo liberado para você ainda. Fale com o administrador.',
                key: Key('sem_modulos'), textAlign: TextAlign.center),
          ),
        ),
      );
}
