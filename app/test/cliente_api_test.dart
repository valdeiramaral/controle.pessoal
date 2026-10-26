import 'dart:convert';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object corpo) => http.Response.bytes(
    utf8.encode(jsonEncode(corpo)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

ClienteApi _api(MockClientHandler h) => ClienteApi(baseUrl: 'http://api.teste', cliente: MockClient(h));

Future<ErroApi> _erroDe(Future<void> Function() f) async {
  try {
    await f();
  } on ErroApi catch (e) {
    return e;
  }
  fail('era esperado um ErroApi');
}

void main() {
  group('ClienteApi', () {
    test('login ok devolve token, validade e usuario', () async {
      late http.Request visto;
      final api = _api((r) async {
        visto = r;
        return _json(200, {
          'token': 'abc',
          'expira_em_segundos': 3600,
          'usuario': {'id': 'u1', 'nome': 'Bia', 'idioma': 'pt-BR', 'pais': 'BR'},
        });
      });
      final r = await api.entrar(email: ' Bia@Exemplo.com ', senha: 'segredo123');
      expect(r.token, 'abc');
      expect(r.usuario.nome, 'Bia');
      expect(r.expiraEm.isAfter(DateTime.now().add(const Duration(minutes: 59))), isTrue);
      expect(visto.url.toString(), 'http://api.teste/login');
      expect(jsonDecode(visto.body), {'email': 'Bia@Exemplo.com', 'senha': 'segredo123'});
    });

    test('senha errada vira mensagem em portugues', () async {
      final api = _api((r) async => _json(401, {'erro': 'credenciais_invalidas'}));
      final e = await _erroDe(() => api.entrar(email: 'a@b.com', senha: 'x'));
      expect(e.mensagem, 'E-mail ou senha incorretos.');
      expect(e.status, 401);
    });

    test('conta bloqueada informa a hora', () async {
      final api = _api((r) async => _json(423, {'erro': 'conta_bloqueada', 'ate': '2026-10-26T15:30:00.000Z'}));
      final e = await _erroDe(() => api.entrar(email: 'a@b.com', senha: 'x'));
      expect(e.codigo, 'conta_bloqueada');
      expect(e.mensagem, contains('bloqueada'));
      expect(e.mensagem, contains(' às '));
    });

    test('cadastro: e-mail repetido (409) e sucesso (201)', () async {
      final repetido = _api((r) async => _json(409, {'erro': 'email_ja_cadastrado'}));
      final e = await _erroDe(() => repetido.cadastrar(nome: 'Bia', email: 'a@b.com', senha: '12345678'));
      expect(e.mensagem, 'Já existe uma conta com este e-mail.');

      final ok = _api((r) async => _json(201, {'id': 'u1'}));
      await ok.cadastrar(nome: 'Bia', email: 'a@b.com', senha: '12345678');
    });

    test('GET /me manda o token e le o usuario', () async {
      late http.Request visto;
      final api = _api((r) async {
        visto = r;
        return _json(200, {'usuario': {'id': 'u1', 'nome': 'Bia', 'email': 'a@b.com'}});
      });
      final p = await api.eu('tok');
      expect(visto.headers['authorization'], 'Bearer tok');
      expect(p.usuario.email, 'a@b.com');
      expect(p.pode('acesso.usuario.ver'), isFalse);
    });

    test('GET /me traz dados pessoais, plano, modulos e permissoes', () async {
      final api = _api((r) async => _json(200, {
            'usuario': {
              'id': 'u1', 'nome': 'Bia', 'email': 'a@b.com', 'cpf': '52998224725', 'telefone': '11987654321',
              'nascimento': '1990-05-17',
              'endereco': {'cep': '01310100', 'cidade': 'Sao Paulo', 'uf': 'SP'},
            },
            'licenca': {'plano': 'anual'},
            'modulos': ['financas', 'saude'],
            'permissoes': ['acesso.usuario.ver'],
          }));
      final p = await api.eu('tok');
      expect(p.usuario.cpf, '52998224725');
      expect(p.usuario.endereco.uf, 'SP');
      expect(p.usuario.nascimento, '1990-05-17');
      expect(p.plano, 'anual');
      expect(p.modulos, ['financas', 'saude']);
      expect(p.pode('acesso.usuario.ver'), isTrue);
    });

    test('cadastro envia CPF, telefone e endereco; CPF repetido tem mensagem propria', () async {
      late http.Request visto;
      final api = _api((r) async {
        visto = r;
        return _json(409, {'erro': 'cpf_ja_cadastrado'});
      });
      final e = await _erroDe(() => api.cadastrar(
            nome: 'Bia', email: 'a@b.com', senha: '12345678', cpf: '52998224725', telefone: '11987654321',
            nascimento: '1990-05-17', endereco: {'cidade': 'Sao Paulo'}));
      expect(e.mensagem, 'Já existe uma conta com este CPF.');
      final corpo = jsonDecode(visto.body) as Map<String, dynamic>;
      expect(corpo['cpf'], '52998224725');
      expect(corpo['telefone'], '11987654321');
      expect(corpo['nascimento'], '1990-05-17');
      expect(corpo['endereco'], {'cidade': 'Sao Paulo'});
    });

    test('erro de campo da API (dados_invalidos) mostra o texto e o campo', () async {
      final api = _api((r) async => _json(400, {'erro': 'dados_invalidos', 'campo': 'cpf', 'detalhe': 'CPF inválido.'}));
      final e = await _erroDe(() => api.cadastrar(
          nome: 'Bia', email: 'a@b.com', senha: '12345678', cpf: '1', telefone: '11987654321'));
      expect(e.campo, 'cpf');
      expect(e.mensagem, 'CPF inválido.');
    });

    test('administracao: catalogo, lista, detalhe, plano, modulos e perfis', () async {
      final pedidos = <String>[];
      final api = _api((r) async {
        pedidos.add('${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''} ${r.body}');
        if (r.url.path == '/catalogo') {
          return _json(200, {
            'planos': [{'codigo': 'gratuito', 'nome': 'Gratuito'}],
            'modulos': [{'codigo': 'saude', 'nome': 'Saúde'}],
            'perfis': [{'codigo': 'usuario', 'nome': 'Usuário'}],
          });
        }
        if (r.url.path == '/usuarios' && r.method == 'GET') {
          return _json(200, {'total': 1, 'itens': [{'id': 'u1', 'nome': 'Ana', 'email': 'a@x.com', 'plano': 'anual', 'ativo': true}]});
        }
        return _json(200, {
          'usuario': {'id': 'u1', 'nome': 'Ana', 'email': 'a@x.com', 'ativo': true},
          'licenca': {'plano': 'anual'},
          'perfis': ['usuario'],
          'modulos': [{'codigo': 'saude', 'nome': 'Saúde', 'liberacao': 'bloqueado', 'efetivo': false}],
        });
      });
      expect((await api.catalogo('t')).modulos.single.nome, 'Saúde');
      final lista = await api.listarUsuarios('t', busca: 'ana lima');
      expect(lista.itens.single.plano, 'anual');
      final d = await api.detalheUsuario('t', 'u1');
      expect(d.modulos.single.liberacao, 'bloqueado');
      expect(d.plano, 'anual');
      await api.definirPlano('t', 'u1', 'mensal');
      await api.definirModulos('t', 'u1', {'saude': null, 'agenda': true});
      await api.definirPerfis('t', 'u1', ['leitura']);
      expect(pedidos[1], contains('GET /usuarios?'));
      expect(pedidos[1], contains('busca=ana+lima'));
      expect(pedidos[3], 'PUT /usuarios/u1/plano {"plano":"mensal"}');
      expect(pedidos[4], 'PUT /usuarios/u1/modulos {"modulos":{"saude":null,"agenda":true}}');
      expect(pedidos[5], 'PUT /usuarios/u1/perfis {"perfis":["leitura"]}');
    });

    test('403 vira mensagem de permissao', () async {
      final api = _api((r) async => _json(403, {'erro': 'sem_permissao', 'permissao': 'acesso.usuario.ver'}));
      final e = await _erroDe(() => api.catalogo('t'));
      expect(e.mensagem, 'Você não tem permissão para isso.');
    });

    test('token recusado e identificado como nao autenticado', () async {
      final api = _api((r) async => _json(401, {'erro': 'nao_autenticado'}));
      final e = await _erroDe(() => api.eu('velho'));
      expect(e.naoAutenticado, isTrue);
    });

    test('429 e 500 tem mensagem propria; falha de rede vira sem_conexao', () async {
      final e429 = await _erroDe(() => _api((r) async => _json(429, {'erro': 'requisicao_invalida'}))
          .entrar(email: 'a@b.com', senha: 'x'));
      expect(e429.mensagem, contains('Muitas tentativas'));

      final e500 = await _erroDe(() => _api((r) async => _json(500, {'erro': 'erro_interno'}))
          .entrar(email: 'a@b.com', senha: 'x'));
      expect(e500.mensagem, contains('servidor'));

      final rede = await _erroDe(() => _api((r) async => throw http.ClientException('sem rede'))
          .entrar(email: 'a@b.com', senha: 'x'));
      expect(rede.semConexao, isTrue);
    });
  });
}
