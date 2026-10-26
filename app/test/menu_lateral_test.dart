import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:controle_pessoal/features/nav/menu_lateral.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

const _admin = UsuarioApi(id: 'a', nome: 'Admin');

EstadoSessao _logado(List<String> permissoes) => EstadoSessao(
      FaseSessao.logado,
      token: 't',
      usuario: _admin,
      perfil: PerfilApi(usuario: _admin, permissoes: permissoes, superusuario: true),
    );

Widget _app(EstadoSessao estado, Widget home) => ProviderScope(
      overrides: [
        armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
        sessaoProvider.overrideWith(() => _SessaoFalsa(estado)),
      ],
      child: MaterialApp(theme: temaApp(), home: home),
    );

void _tela(WidgetTester tester, double largura) {
  tester.view.physicalSize = Size(largura, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('menu mostra modulos, administracao por permissao e conta; recolhe para icones', (tester) async {
    _tela(tester, 1200);
    var escolhido = -1;
    await tester.pumpWidget(_app(
      _logado(['acesso.usuario.ver', 'acesso.perfil.gerenciar']),
      Scaffold(body: Row(children: [MenuLateral(indice: 0, aoIr: (i) => escolhido = i), const Expanded(child: SizedBox())])),
    ));
    await tester.pumpAndSettle();
    for (final t in ['Hoje', 'Finanças', 'Saúde', 'Agenda', 'Usuários e acessos', 'Perfis e grupos', 'Meus dados', 'Aparência', 'Sair']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.tap(find.text('Finanças'));
    expect(escolhido, 1);

    await tester.tap(find.byKey(const Key('menu_recolher')));
    await tester.pumpAndSettle();
    expect(find.text('Finanças'), findsNothing);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);

    await tester.tap(find.byKey(const Key('menu_recolher')));
    await tester.pumpAndSettle();
    expect(find.text('Finanças'), findsOneWidget);
  });

  testWidgets('sem permissao de administracao, o menu nao mostra essas opcoes', (tester) async {
    _tela(tester, 1200);
    await tester.pumpWidget(_app(
      _logado(const []),
      Scaffold(body: Row(children: [MenuLateral(indice: 0, aoIr: (_) {}), const Expanded(child: SizedBox())])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Usuários e acessos'), findsNothing);
    expect(find.text('Perfis e grupos'), findsNothing);
    expect(find.text('Hoje'), findsOneWidget);
  });

  testWidgets('em tela estreita a barra mostra o botao do menu suspenso; em tela larga, nao', (tester) async {
    _tela(tester, 500);
    await tester.pumpWidget(_app(_logado(const []), const Scaffold(appBar: BarraPagina(title: Text('Agenda')))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('botao_menu')), findsOneWidget);

    _tela(tester, 1200);
    await tester.pumpWidget(_app(_logado(const []), const Scaffold(appBar: BarraPagina(title: Text('Agenda')))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('botao_menu')), findsNothing);
  });

  testWidgets('menu suspenso em tela larga: botao Ocultar liga o modo suspenso', (tester) async {
    _tela(tester, 1200);
    late WidgetRef refCapturado;
    await tester.pumpWidget(_app(
      _logado(const []),
      Consumer(builder: (context, ref, _) {
        refCapturado = ref;
        return Scaffold(
          appBar: const BarraPagina(title: Text('Agenda')),
          body: Row(children: [MenuLateral(indice: 0, aoIr: (_) {}), const Expanded(child: SizedBox())]),
        );
      }),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_suspender')));
    await tester.pumpAndSettle();
    expect(refCapturado.read(menuSuspensoProvider), isTrue);
    expect(find.byKey(const Key('botao_menu')), findsOneWidget);
  });
}
