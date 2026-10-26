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
      final u = await api.eu('tok');
      expect(visto.headers['authorization'], 'Bearer tok');
      expect(u.email, 'a@b.com');
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
