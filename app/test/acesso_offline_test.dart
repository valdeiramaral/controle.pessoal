import 'dart:convert';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/acesso_offline.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object corpo) => http.Response.bytes(utf8.encode(jsonEncode(corpo)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

const _usuario = {'id': 'u1', 'nome': 'Bia', 'email': 'a@b.com'};

void main() {
  late bool internet;
  late CofreOfflineMemoria cofre;
  late ProviderContainer c;

  setUp(() {
    internet = true;
    cofre = CofreOfflineMemoria();
    c = ProviderContainer(overrides: [
      clienteApiProvider.overrideWithValue(ClienteApi(
        baseUrl: 'http://api.teste',
        cliente: MockClient((r) async {
          if (!internet) throw http.ClientException('sem rede');
          if (r.url.path == '/login') {
            final senha = (jsonDecode(r.body) as Map)['senha'];
            if (senha != 'segredo123') return _json(401, {'erro': 'credenciais_invalidas', 'mensagem': 'Senha incorreta'});
            return _json(200, {'token': 'tok', 'expira_em_segundos': 3600, 'usuario': _usuario});
          }
          if (r.url.path == '/me') {
            return _json(200, {
              'usuario': _usuario,
              'licenca': {'plano': 'Completo'},
              'modulos': ['financas'],
              'permissoes': ['financas.ver'],
              'superusuario': false,
              'preferencias': {},
            });
          }
          return _json(404, {});
        }),
      )),
      armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
      cofreOfflineProvider.overrideWithValue(cofre),
    ]);
    addTearDown(c.dispose);
  });

  Future<void> aguardar() async {
    c.read(sessaoProvider);
    for (var i = 0; i < 50 && c.read(sessaoProvider).fase == FaseSessao.iniciando; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> esperarCofre(String email) async {
    for (var i = 0; i < 100 && !await cofre.existe(email); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('entrar com internet prepara o acesso offline', () async {
    await aguardar();
    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123');
    await esperarCofre('a@b.com');
    final a = await cofre.verificar('A@B.com', 'segredo123'); // e-mail sem diferenciar maiusculas
    expect(a?.usuario.nome, 'Bia');
    expect(a?.perfil?.pode('financas.ver'), isTrue);
    expect(await cofre.verificar('a@b.com', 'errada'), isNull);
    expect(cofre.texto, isNot(contains('segredo123'))); // a senha nunca e guardada
  });

  test('sem internet, abre com a senha conferida no aparelho e religa quando a rede volta', () async {
    await aguardar();
    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123');
    await esperarCofre('a@b.com');
    await c.read(sessaoProvider.notifier).sair();

    internet = false;
    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123');
    var s = c.read(sessaoProvider);
    expect(s.fase, FaseSessao.logado);
    expect(s.offline, isTrue);
    expect(s.token, isNull);
    expect(s.usuario?.id, 'u1');
    expect(s.pode('financas.ver'), isTrue);

    expect(await c.read(sessaoProvider.notifier).religarConta(), isFalse); // ainda sem rede
    expect(c.read(sessaoProvider).offline, isTrue);

    internet = true;
    expect(await c.read(sessaoProvider.notifier).religarConta(), isTrue);
    s = c.read(sessaoProvider);
    expect(s.offline, isFalse);
    expect(s.token, 'tok');
  });

  test('sem internet: senha errada e e-mail desconhecido sao recusados', () async {
    await aguardar();
    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123');
    await esperarCofre('a@b.com');
    await c.read(sessaoProvider.notifier).sair();

    internet = false;
    await expectLater(c.read(sessaoProvider.notifier).entrar('a@b.com', 'errada'),
        throwsA(isA<ErroApi>().having((e) => e.codigo, 'codigo', 'credenciais_invalidas')));
    await expectLater(c.read(sessaoProvider.notifier).entrar('outro@b.com', 'segredo123'),
        throwsA(isA<ErroApi>().having((e) => e.semConexao, 'semConexao', isTrue)));
    expect(c.read(sessaoProvider).fase, isNot(FaseSessao.logado));
  });
}
