import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/agenda/agenda_page.dart';
import 'features/auth/login_page.dart';
import 'core/tema.dart';
import 'features/auth/sessao.dart';
import 'features/auth/widgets_auth.dart';
import 'features/nav/menu_lateral.dart';
import 'features/financas/financas_page.dart';
import 'features/hoje/hoje_page.dart';
import 'features/saude/saude_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle Pessoal',
      debugShowCheckedModeBanner: false,
      theme: temaApp(),
      darkTheme: temaApp(),
      themeMode: ThemeMode.dark,
      builder: (context, child) => FundoAzul(child: child ?? const SizedBox.shrink()),
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
        return const _Casca();
    }
  }
}

/// Navegacao principal: menu a esquerda (fixo, recolhido ou suspenso) e as paginas.
class _Casca extends ConsumerStatefulWidget {
  const _Casca();

  @override
  ConsumerState<_Casca> createState() => _CascaState();
}

class _CascaState extends ConsumerState<_Casca> {
  int _indice = 0;

  static const _paginas = <Widget>[
    HojePage(),
    FinancasPage(),
    SaudePage(),
    AgendaPage(),
  ];

  void _ir(int i, {bool fecharMenu = false}) {
    setState(() => _indice = i);
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
                child: MenuLateral(emDrawer: true, indice: _indice, aoIr: (i) => _ir(i, fecharMenu: true)),
              ),
            )
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!suspenso)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
              child: MenuLateral(indice: _indice, aoIr: _ir),
            ),
          Expanded(child: IndexedStack(index: _indice, children: _paginas)),
        ],
      ),
    );
  }
}
