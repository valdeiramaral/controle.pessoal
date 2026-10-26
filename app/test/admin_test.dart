import 'dart:convert';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/admin/usuarios_page.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object corpo) => http.Response.bytes(
    utf8.encode(jsonEncode(corpo)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// Sessao pronta (logado como administrador), sem rede.
class _SessaoFalsa extends SessaoNotifier {
  _SessaoFalsa(this.estado);
  final EstadoSessao estado;
  @override
  EstadoSessao build() => estado;
}

const _permissoes = [
  'acesso.usuario.ver',
  'acesso.usuario.cadastrar',
  'acesso.usuario.editar',
  'acesso.perfil.gerenciar',
  'licencas.licenca.conceder',
  'administracao.liberacao.gerenciar',
];

const _catalogo = {
  'planos': [
    {'codigo': 'gratuito', 'nome': 'Gratuito', 'periodo': 'gratuito'},
    {'codigo': 'mensal', 'nome': 'Mensal', 'periodo': 'mensal'},
    {'codigo': 'anual', 'nome': 'Anual', 'periodo': 'anual'},
  ],
  'modulos': [
    {'codigo': 'financas', 'nome': 'Finanças', 'descricao': null, 'liberado_para_todos': false},
    {'codigo': 'saude', 'nome': 'Saúde', 'descricao': null, 'liberado_para_todos': false},
    {'codigo': 'agenda', 'nome': 'Agenda e compromissos', 'descricao': null, 'liberado_para_todos': false},
  ],
  'perfis': [
    {'codigo': 'administrador', 'nome': 'Administrador'},
    {'codigo': 'usuario', 'nome': 'Usuário'},
    {'codigo': 'leitura', 'nome': 'Somente leitura'},
  ],
};

Map<String, dynamic> _detalhe() => {
      'usuario': {
        'id': 'u1', 'nome': 'Ana Lima', 'email': 'ana@x.com', 'cpf': '52998224725', 'telefone': '11987654321',
        'ativo': true, 'endereco': {'cidade': 'Recife', 'uf': 'PE'},
      },
      'licenca': {'plano': 'gratuito'},
      'perfis': ['usuario'],
      'modulos': [
        {'codigo': 'financas', 'nome': 'Finanças', 'liberacao': 'padrao', 'efetivo': true},
        {'codigo': 'saude', 'nome': 'Saúde', 'liberacao': 'bloqueado', 'efetivo': false},
        {'codigo': 'agenda', 'nome': 'Agenda e compromissos', 'liberacao': 'padrao', 'efetivo': true},
      ],
    };

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

Widget _app(List<_Pedido> pedidos, {List<String> permissoes = _permissoes}) {
  final cliente = MockClient((r) async {
    pedidos.add(_Pedido(r.method, r.url.path, r.body.isEmpty ? null : jsonDecode(r.body) as Map<String, dynamic>));
    final p = r.url.path;
    if (p == '/catalogo') return _json(200, _catalogo);
    if (p == '/grupos') return _json(200, {'itens': []});
    if (p == '/permissoes') return _json(200, {'permissoes': []});
    if (p == '/usuarios' && r.method == 'GET') {
      return _json(200, {
        'total': 2,
        'itens': [
          {'id': 'u1', 'nome': 'Ana Lima', 'email': 'ana@x.com', 'cpf': '52998224725', 'plano': 'gratuito', 'ativo': true},
          {'id': 'u2', 'nome': 'Bruno Dias', 'email': 'bruno@x.com', 'plano': 'anual', 'ativo': false},
        ],
      });
    }
    if (p == '/usuarios' && r.method == 'POST') return _json(201, _detalhe());
    if (p == '/usuarios/u1' && r.method == 'GET') return _json(200, _detalhe());
    if (p == '/usuarios/u1' && r.method == 'PATCH') return _json(200, {'id': 'u1'});
    if (p.startsWith('/usuarios/u1/')) return _json(200, _detalhe());
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
            perfil: PerfilApi(usuario: const UsuarioApi(id: 'admin', nome: 'Admin'), permissoes: permissoes, superusuario: true),
          ))),
    ],
    child: const MaterialApp(home: UsuariosPage()),
  );
}

Finder _segmento(String modulo, String texto) =>
    find.descendant(of: find.byKey(Key('modulo_$modulo')), matching: find.text(texto));

void main() {
  testWidgets('lista mostra nome, plano e situacao de cada usuario', (tester) async {
    _tela(tester);
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();
    expect(find.text('Ana Lima'), findsOneWidget);
    expect(find.text('Bruno Dias'), findsOneWidget);
    expect(find.text('Anual'), findsOneWidget);
    expect(find.text('Desativado'), findsOneWidget);
    expect(find.textContaining('529.982.247-25'), findsOneWidget);
    expect(find.byKey(const Key('botao_novo_usuario')), findsOneWidget);
  });

  testWidgets('sem permissao de cadastrar, nao ha botao Novo usuario', (tester) async {
    _tela(tester);
    await tester.pumpWidget(_app([], permissoes: const ['acesso.usuario.ver']));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('botao_novo_usuario')), findsNothing);
  });

  testWidgets('cadastra usuario novo com plano, perfil e modulos liberados/bloqueados', (tester) async {
    _tela(tester);
    final pedidos = <_Pedido>[];
    await tester.pumpWidget(_app(pedidos));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_novo_usuario')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('campo_nome')), 'Carla Nova');
    await tester.enterText(find.byKey(const Key('campo_email')), 'carla@x.com');
    await tester.enterText(find.byKey(const Key('campo_cpf')), '11144477735');
    await tester.enterText(find.byKey(const Key('campo_telefone')), '11987654321');
    await tester.enterText(find.byKey(const Key('campo_senha')), 'segredo123');

    await tester.tap(_segmento('saude', 'Bloqueado'));
    await tester.tap(_segmento('agenda', 'Liberado'));
    await tester.tap(find.byKey(const Key('perfil_leitura')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();

    final post = pedidos.firstWhere((p) => p.metodo == 'POST' && p.caminho == '/usuarios');
    expect(post.corpo!['nome'], 'Carla Nova');
    expect(post.corpo!['cpf'], '11144477735');
    expect(post.corpo!['telefone'], '11987654321');
    expect(post.corpo!['senha'], 'segredo123');
    expect(post.corpo!['plano'], 'gratuito');
    expect(post.corpo!['perfis'], containsAll(['usuario', 'leitura']));
    expect(post.corpo!['modulos'], {'saude': false, 'agenda': true});
    expect(find.text('Usuários'), findsOneWidget); // voltou para a lista
  });

  testWidgets('formulario novo recusa CPF invalido e senha curta', (tester) async {
    _tela(tester);
    final pedidos = <_Pedido>[];
    await tester.pumpWidget(_app(pedidos));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_novo_usuario')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_nome')), 'Carla');
    await tester.enterText(find.byKey(const Key('campo_email')), 'carla@x.com');
    await tester.enterText(find.byKey(const Key('campo_cpf')), '11111111111');
    await tester.enterText(find.byKey(const Key('campo_telefone')), '11987654321');
    await tester.enterText(find.byKey(const Key('campo_senha')), '123');
    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pump();
    expect(find.text('CPF inválido.'), findsOneWidget);
    expect(find.text('Use ao menos 8 caracteres.'), findsOneWidget);
    expect(pedidos.where((p) => p.metodo == 'POST'), isEmpty);
  });

  testWidgets('edita usuario: carrega os dados e so envia o que mudou', (tester) async {
    _tela(tester);
    final pedidos = <_Pedido>[];
    await tester.pumpWidget(_app(pedidos));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('usuario_u1')));
    await tester.pumpAndSettle();

    expect(find.text('Ana Lima'), findsOneWidget); // campo nome preenchido
    expect(find.text('529.982.247-25'), findsOneWidget);
    expect(find.text('(11) 98765-4321'), findsOneWidget);
    expect(find.text('Inativo'), findsOneWidget); // saude bloqueada

    // libera Saude para este usuario e muda o plano para Mensal
    await tester.tap(_segmento('saude', 'Liberado'));
    await tester.tap(find.byKey(const Key('campo_plano')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mensal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_salvar')));
    await tester.pumpAndSettle();

    final patch = pedidos.firstWhere((p) => p.metodo == 'PATCH' && p.caminho == '/usuarios/u1');
    expect(patch.corpo!['nome'], 'Ana Lima');
    expect(patch.corpo!['cpf'], '52998224725');
    expect(patch.corpo!['ativo'], true);
    final plano = pedidos.firstWhere((p) => p.caminho == '/usuarios/u1/plano');
    expect(plano.corpo, {'plano': 'mensal'});
    final modulos = pedidos.firstWhere((p) => p.caminho == '/usuarios/u1/modulos');
    expect(modulos.corpo, {'modulos': {'saude': true}});
    expect(pedidos.where((p) => p.caminho == '/usuarios/u1/perfis'), isEmpty);
  });

  testWidgets('sem permissao de liberar modulos, os controles ficam desligados', (tester) async {
    _tela(tester);
    await tester.pumpWidget(_app([], permissoes: const ['acesso.usuario.ver', 'acesso.usuario.editar']));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('usuario_u1')));
    await tester.pumpAndSettle();
    final seg = tester.widget<SegmentedButton<String>>(find.byKey(const Key('modulo_saude')));
    expect(seg.onSelectionChanged, isNull);
  });
}
