import 'dart:convert';

import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/admin/modulo_form_page.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'util_testes.dart';

class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

Future<List<Map<String, dynamic>>> _abrir(WidgetTester tester, ModuloAdmin m) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final enviados = <Map<String, dynamic>>[];
  http.Response json(Object c) =>
      http.Response.bytes(utf8.encode(jsonEncode(c)), 200, headers: {'content-type': 'application/json'});
  final cliente = MockClient((r) async {
    if (r.method == 'PUT' && r.url.path.startsWith('/modulos/')) {
      enviados.add(jsonDecode(r.body) as Map<String, dynamic>);
      return json({'codigo': m.codigo, 'nome': m.nome});
    }
    if (r.url.path == '/catalogo') return json({'planos': [], 'modulos': [], 'perfis': []});
    return json({});
  });
  const u = UsuarioApi(id: 'a', nome: 'Admin');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: cliente)),
      armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
      sessaoProvider.overrideWith(() => _SessaoFalsa(EstadoSessao(FaseSessao.logado,
          token: 't',
          usuario: u,
          perfil: const PerfilApi(usuario: u, permissoes: ['administracao.modulo.gerenciar'], superusuario: true)))),
    ],
    child: MaterialApp(theme: temaApp(), home: ModuloFormPage(modulo: m)),
  ));
  await tester.pumpAndSettle();
  return enviados;
}

void main() {
  testWidgets('modulo do pacote: sem liberacao; o SuperUsuario pode tirar do pacote', (tester) async {
    const m = ModuloAdmin(codigo: 'financas', nome: 'Finanças', ordem: 1, sistema: true, noPacote: true);
    final enviados = await _abrir(tester, m);
    expect(find.byKey(const Key('aviso_pacote')), findsOneWidget);
    expect(find.byKey(const Key('botao_add_usuario')), findsNothing);

    await tester.tap(find.byKey(const Key('campo_no_pacote')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aviso_pacote')), findsNothing);
    expect(find.byKey(const Key('botao_add_usuario')), findsOneWidget);

    await tocarRolando(tester, find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();
    expect(enviados.single['no_pacote'], false);
    expect(enviados.single['liberacoes'], isEmpty);
  });

  testWidgets('liberacao por usuario: vitalicio esconde as datas; validade exige inicio e fim; desativar', (tester) async {
    final m = ModuloAdmin(
      codigo: 'academia',
      nome: 'Academia',
      ordem: 10,
      liberacoes: [
        LiberacaoModulo(usuarioId: 'u1', nome: 'Maria', email: 'maria@x.com'),
        LiberacaoModulo(
            usuarioId: 'u2',
            nome: 'Joao',
            vitalicio: false,
            inicio: DateTime(2026, 1, 1),
            fim: DateTime(2026, 1, 31),
            vigente: false),
      ],
    );
    final enviados = await _abrir(tester, m);
    expect(find.byKey(const Key('inicio_u1')), findsNothing); // vitalicio
    expect(find.byKey(const Key('inicio_u2')), findsOneWidget);
    expect(find.byKey(const Key('fim_u2')), findsOneWidget);
    expect(find.text('Vencida'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ativa_u1')));
    await tester.pumpAndSettle();
    expect(find.text('Desativada'), findsOneWidget);

    await tocarRolando(tester, find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();
    final libs = (enviados.single['liberacoes'] as List).cast<Map<String, dynamic>>();
    expect(libs[0]['usuario_id'], 'u1');
    expect(libs[0]['ativa'], false);
    expect(libs[0]['vitalicio'], true);
    expect(libs[0].containsKey('inicio'), false);
    expect(libs[1]['vitalicio'], false);
    expect(libs[1]['inicio'], isNotNull);
    expect(libs[1]['fim'], isNotNull);
  });
}
