import 'dart:convert';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/admin/perfis_grupos_page.dart';
import 'package:controle_pessoal/features/admin/usuario_form_page.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'util_testes.dart';

http.Response _json(int status, Object corpo) => http.Response.bytes(
    utf8.encode(jsonEncode(corpo)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

const _todas = [
  'acesso.usuario.ver',
  'acesso.usuario.editar',
  'acesso.perfil.gerenciar',
  'acesso.grupo.gerenciar',
  'licencas.licenca.conceder',
  'administracao.liberacao.gerenciar',
];

const _permissoesCatalogo = [
  {'codigo': 'financas.conta.ver', 'nome': 'Ver contas', 'modulo_codigo': 'financas', 'modulo_nome': 'Finanças'},
  {'codigo': 'financas.conta.gerenciar', 'nome': 'Gerenciar contas', 'modulo_codigo': 'financas', 'modulo_nome': 'Finanças'},
  {'codigo': 'saude.registro.ver', 'nome': 'Ver registros', 'modulo_codigo': 'saude', 'modulo_nome': 'Saúde'},
];

class _Pedido {
  _Pedido(this.metodo, this.caminho, this.corpo);
  final String metodo;
  final String caminho;
  final Map<String, dynamic>? corpo;
}

void _tela(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, List<_Pedido> pedidos, {Map<String, http.Response> fixas = const {}}) {
  final cliente = MockClient((r) async {
    pedidos.add(_Pedido(r.method, r.url.path, r.body.isEmpty ? null : jsonDecode(r.body) as Map<String, dynamic>));
    final chave = '${r.method} ${r.url.path}';
    if (fixas.containsKey(chave)) return fixas[chave]!;
    final p = r.url.path;
    if (p == '/permissoes') return _json(200, {'permissoes': _permissoesCatalogo});
    if (p == '/perfis' && r.method == 'GET') {
      return _json(200, {
        'itens': [
          {'id': 'p1', 'codigo': 'administrador', 'nome': 'Administrador', 'descricao': null, 'sistema': true, 'total_permissoes': 3, 'total_usuarios': 1},
          {'id': 'p2', 'codigo': 'usuario', 'nome': 'Usuário', 'descricao': null, 'sistema': true, 'total_permissoes': 1, 'total_usuarios': 5},
          {'id': 'p3', 'codigo': 'contador', 'nome': 'Contador', 'descricao': 'So financas', 'sistema': false, 'total_permissoes': 2, 'total_usuarios': 0},
        ],
      });
    }
    if (p == '/perfis' && r.method == 'POST') {
      return _json(201, {'id': 'p9', 'codigo': 'novo', 'nome': 'Novo', 'sistema': false, 'permissoes': []});
    }
    if (p == '/perfis/p1') {
      return _json(200, {'id': 'p1', 'codigo': 'administrador', 'nome': 'Administrador', 'sistema': true, 'permissoes': []});
    }
    if (p == '/perfis/p3' && r.method == 'GET') {
      return _json(200, {
        'id': 'p3', 'codigo': 'contador', 'nome': 'Contador', 'descricao': 'So financas', 'sistema': false,
        'permissoes': ['financas.conta.ver'],
      });
    }
    if (p == '/perfis/p3') return _json(200, {'id': 'p3', 'codigo': 'contador', 'nome': 'Contador', 'sistema': false, 'permissoes': []});
    if (p == '/grupos' && r.method == 'GET') {
      return _json(200, {
        'itens': [
          {'id': 'g1', 'nome': 'Familia', 'descricao': null, 'total_membros': 2, 'perfis': ['usuario']},
        ],
      });
    }
    if (p == '/grupos' && r.method == 'POST') return _json(201, {'id': 'g9', 'nome': 'Novo', 'perfis': [], 'membros': []});
    if (p == '/usuarios' && r.method == 'GET') {
      return _json(200, {
        'total': 2,
        'itens': [
          {'id': 'u1', 'nome': 'Ana Lima', 'email': 'ana@x.com', 'ativo': true},
          {'id': 'u2', 'nome': 'Bruno Dias', 'email': 'bruno@x.com', 'ativo': true},
        ],
      });
    }
    if (p == '/usuarios/u1' && r.method == 'GET') return _json(200, _detalheUsuario());
    if (p.startsWith('/usuarios/u1/')) return _json(200, _detalheUsuario());
    if (p == '/catalogo') {
      return _json(200, {
        'planos': [{'codigo': 'gratuito', 'nome': 'Gratuito'}],
        'modulos': [{'codigo': 'financas', 'nome': 'Finanças'}],
        'perfis': [{'codigo': 'usuario', 'nome': 'Usuário'}],
      });
    }
    return _json(404, {'erro': 'nao_encontrado'});
  });
  return ProviderScope(
    overrides: [
      clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: cliente)),
      armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
      sessaoProvider.overrideWith(() => _SessaoFalsa(EstadoSessao(
            FaseSessao.logado,
            token: 'tok',
            usuario: const UsuarioApi(id: 'admin', nome: 'Admin'),
            perfil: PerfilApi(usuario: const UsuarioApi(id: 'admin', nome: 'Admin'), permissoes: _todas, superusuario: true),
          ))),
    ],
    child: MaterialApp(home: home),
  );
}

Map<String, dynamic> _detalheUsuario() => {
      'usuario': {'id': 'u1', 'nome': 'Ana Lima', 'email': 'ana@x.com', 'cpf': '52998224725', 'telefone': '11987654321', 'ativo': true},
      'licenca': {'plano': 'gratuito'},
      'perfis': ['usuario'],
      'modulos': [
        {'codigo': 'financas', 'nome': 'Finanças', 'liberacao': 'padrao', 'efetivo': true},
      ],
      'grupos': [
        {'id': 'g1', 'nome': 'Familia'},
      ],
      'excecoes': {'financas.conta.gerenciar': false},
      'permissoes': ['financas.conta.ver'],
    };

void main() {
  testWidgets('lista perfis e grupos nas duas abas', (tester) async {
    _tela(tester);
    await tester.pumpWidget(_app(const PerfisGruposPage(), []));
    await tester.pumpAndSettle();
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Contador'), findsOneWidget);
    expect(find.textContaining('2 permissões'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aba_grupos')));
    await tester.pumpAndSettle();
    expect(find.text('Familia'), findsOneWidget);
    expect(find.textContaining('2 membro(s)'), findsOneWidget);
  });

  testWidgets('cria perfil marcando permissoes (modulo inteiro e uma avulsa)', (tester) async {
    _tela(tester);
    final pedidos = <_Pedido>[];
    await tester.pumpWidget(_app(const PerfisGruposPage(), pedidos));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_novo_item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_nome_perfil')), 'Gerente de Contas');
    await tester.tap(find.byKey(const Key('todos_financas')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('perm_saude.registro.ver')));
    await tester.pump();
    await tocarRolando(tester, find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();
    final post = pedidos.firstWhere((p) => p.metodo == 'POST' && p.caminho == '/perfis');
    expect(post.corpo!['nome'], 'Gerente de Contas');
    expect(post.corpo!['permissoes'], ['financas.conta.gerenciar', 'financas.conta.ver', 'saude.registro.ver']);
    expect(find.text('Perfis e grupos'), findsOneWidget); // voltou para a lista
  });

  testWidgets('edita perfil: carrega as permissoes e envia a lista nova', (tester) async {
    _tela(tester);
    final pedidos = <_Pedido>[];
    await tester.pumpWidget(_app(const PerfisGruposPage(), pedidos));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item_perfil_contador')));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('perm_financas.conta.ver'))).value, isTrue);
    await tester.tap(find.byKey(const Key('perm_financas.conta.ver')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('perm_saude.registro.ver')));
    await tester.pump();
    await tocarRolando(tester, find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();
    final put = pedidos.firstWhere((p) => p.metodo == 'PUT' && p.caminho == '/perfis/p3');
    expect(put.corpo!['permissoes'], ['saude.registro.ver']);
  });

  testWidgets('perfil administrador e fixo: tudo marcado, travado e sem enviar permissoes', (tester) async {
    _tela(tester);
    final pedidos = <_Pedido>[];
    await tester.pumpWidget(_app(const PerfisGruposPage(), pedidos));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item_perfil_administrador')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aviso_fixo')), findsOneWidget);
    final cb = tester.widget<CheckboxListTile>(find.byKey(const Key('perm_saude.registro.ver')));
    expect(cb.value, isTrue);
    expect(cb.onChanged, isNull);
    expect(find.byKey(const Key('botao_excluir')), findsNothing);
    await tocarRolando(tester, find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();
    final put = pedidos.firstWhere((p) => p.metodo == 'PUT' && p.caminho == '/perfis/p1');
    expect(put.corpo!.containsKey('permissoes'), isFalse);
  });

  testWidgets('excluir perfil em uso mostra a mensagem da API', (tester) async {
    _tela(tester);
    await tester.pumpWidget(_app(const PerfisGruposPage(), [], fixas: {
      'DELETE /perfis/p3': _json(409, {'erro': 'perfil_em_uso', 'usuarios': 1, 'grupos': 0}),
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item_perfil_contador')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_excluir')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar_exclusao')));
    await tester.pumpAndSettle();
    expect(find.textContaining('está em uso'), findsOneWidget);
  });

  testWidgets('cria grupo com perfil e membros escolhidos', (tester) async {
    _tela(tester);
    final pedidos = <_Pedido>[];
    await tester.pumpWidget(_app(const PerfisGruposPage(), pedidos));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aba_grupos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_novo_item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_nome_grupo')), 'Contabilidade');
    await tester.tap(find.byKey(const Key('grupo_perfil_contador')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('botao_membros')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('escolher_u2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmar_membros')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('membro_u2')), findsOneWidget);
    await tocarRolando(tester, find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();
    final post = pedidos.firstWhere((p) => p.metodo == 'POST' && p.caminho == '/grupos');
    expect(post.corpo!['nome'], 'Contabilidade');
    expect(post.corpo!['perfis'], ['contador']);
    expect(post.corpo!['membros'], ['u2']);
  });

  testWidgets('usuario: troca de grupos e excecoes de permissao', (tester) async {
    _tela(tester);
    final pedidos = <_Pedido>[];
    await tester.pumpWidget(_app(const UsuarioFormPage(usuarioId: 'u1'), pedidos));
    await tester.pumpAndSettle();

    // grupo Familia ja marcado; tira
    expect(tester.widget<FilterChip>(find.byKey(const Key('grupo_g1'))).selected, isTrue);
    await tester.tap(find.byKey(const Key('grupo_g1')));
    await tester.pump();

    // financas ja tem excecao (negar) e vem aberto; permite uma e nega outra de saude
    await tester.ensureVisible(find.byKey(const Key('excecao_financas.conta.gerenciar')));
    final negar = find.descendant(of: find.byKey(const Key('excecao_financas.conta.gerenciar')), matching: find.text('Negar'));
    expect(tester.widget<SegmentedButton<String>>(find.byKey(const Key('excecao_financas.conta.gerenciar'))).selected, {'negar'});
    expect(negar, findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const Key('excecao_financas.conta.ver')), matching: find.text('Permitir')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('excecoes_saude')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byKey(const Key('excecao_saude.registro.ver')), matching: find.text('Negar')));
    await tester.pump();
    await tester.tap(find.descendant(of: find.byKey(const Key('excecao_financas.conta.gerenciar')), matching: find.text('Herdar')));
    await tester.pump();

    await tocarRolando(tester, find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();

    final grupos = pedidos.firstWhere((p) => p.metodo == 'PUT' && p.caminho == '/usuarios/u1/grupos');
    expect(grupos.corpo!['grupos'], isEmpty);
    final ex = pedidos.firstWhere((p) => p.metodo == 'PUT' && p.caminho == '/usuarios/u1/permissoes');
    expect(ex.corpo!['permissoes'], {
      'financas.conta.ver': true,
      'saude.registro.ver': false,
      'financas.conta.gerenciar': null,
    });
  });
}
