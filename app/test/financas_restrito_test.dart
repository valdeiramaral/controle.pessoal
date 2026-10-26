import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:controle_pessoal/features/financas/financas_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

Future<void> _abrir(WidgetTester tester, {required bool superusuario}) async {
  final banco = Banco.paraTeste(NativeDatabase.memory());
  addTearDown(banco.close);
  await banco.inserirLancamento(descricao: 'Aluguel', valorCentavos: 100000, tipo: 'despesa');
  const u = UsuarioApi(id: 'u', nome: 'Bia');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      bancoProvider.overrideWithValue(banco),
      armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
      sessaoProvider.overrideWith(() => _SessaoFalsa(EstadoSessao(FaseSessao.logado,
          token: 't', usuario: u, perfil: PerfilApi(usuario: u, superusuario: superusuario)))),
    ],
    child: MaterialApp(theme: temaApp(), home: const FinancasPage()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('usuario comum nao ve nem cria lancamentos', (tester) async {
    await _abrir(tester, superusuario: false);
    expect(find.byKey(const Key('financas_restrito')), findsOneWidget);
    expect(find.text('Aluguel'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('SuperUsuario ve os lancamentos', (tester) async {
    await _abrir(tester, superusuario: true);
    expect(find.byKey(const Key('financas_restrito')), findsNothing);
    expect(find.text('Aluguel'), findsOneWidget);
  });
}
