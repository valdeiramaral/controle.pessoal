import 'dart:convert';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object corpo) => http.Response.bytes(
    utf8.encode(jsonEncode(corpo)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

const _usuario = {'id': 'u1', 'nome': 'Bia', 'email': 'a@b.com'};

ProviderContainer _montar(MockClientHandler h, ArmazenamentoMemoria guarda) {
  final c = ProviderContainer(overrides: [
    clienteApiProvider.overrideWithValue(ClienteApi(baseUrl: 'http://api.teste', cliente: MockClient(h))),
    armazenamentoSessaoProvider.overrideWithValue(guarda),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _aguardarFim(ProviderContainer c) async {
  c.read(sessaoProvider); // dispara build/restaurar
  for (var i = 0; i < 50 && c.read(sessaoProvider).fase == FaseSessao.iniciando; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('sem nada guardado, abre no login', () async {
    final c = _montar((r) async => _json(500, {}), ArmazenamentoMemoria());
    await _aguardarFim(c);
    expect(c.read(sessaoProvider).fase, FaseSessao.deslogado);
  });

  test('entrar guarda a sessao e sair apaga', () async {
    final guarda = ArmazenamentoMemoria();
    final c = _montar((r) async {
      if (r.url.path == '/login') {
        return _json(200, {'token': 'tok', 'expira_em_segundos': 3600, 'usuario': _usuario});
      }
      return _json(404, {});
    }, guarda);
    await _aguardarFim(c);

    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123');
    expect(c.read(sessaoProvider).fase, FaseSessao.logado);
    expect(c.read(sessaoProvider).usuario?.nome, 'Bia');
    expect(guarda.valor?.token, 'tok');

    await c.read(sessaoProvider.notifier).sair();
    expect(c.read(sessaoProvider).fase, FaseSessao.deslogado);
    expect(guarda.valor, isNull);
  });

  test('cadastrar cria a conta e ja entra', () async {
    final caminhos = <String>[];
    final c = _montar((r) async {
      caminhos.add(r.url.path);
      if (r.url.path == '/cadastro') return _json(201, {'id': 'u1'});
      return _json(200, {'token': 'tok', 'expira_em_segundos': 3600, 'usuario': _usuario});
    }, ArmazenamentoMemoria());
    await _aguardarFim(c);
    await c.read(sessaoProvider.notifier).cadastrar('Bia', 'a@b.com', 'segredo123');
    expect(caminhos, ['/cadastro', '/login']);
    expect(c.read(sessaoProvider).fase, FaseSessao.logado);
  });

  test('login com senha errada nao muda o estado e mostra o erro', () async {
    final c = _montar((r) async => _json(401, {'erro': 'credenciais_invalidas'}), ArmazenamentoMemoria());
    await _aguardarFim(c);
    await expectLater(c.read(sessaoProvider.notifier).entrar('a@b.com', 'x'), throwsA(isA<ErroApi>()));
    expect(c.read(sessaoProvider).fase, FaseSessao.deslogado);
  });

  test('reabrir com sessao valida confirma no servidor', () async {
    final guarda = ArmazenamentoMemoria()
      ..valor = SessaoSalva(token: 'tok', usuario: UsuarioApi.deJson(_usuario));
    final c = _montar((r) async => _json(200, {'usuario': {..._usuario, 'nome': 'Bia Nova'}}), guarda);
    await _aguardarFim(c);
    expect(c.read(sessaoProvider).fase, FaseSessao.logado);
    expect(c.read(sessaoProvider).usuario?.nome, 'Bia Nova');
  });

  test('reabrir sem internet continua logado com os dados guardados', () async {
    final guarda = ArmazenamentoMemoria()
      ..valor = SessaoSalva(token: 'tok', usuario: UsuarioApi.deJson(_usuario));
    final c = _montar((r) async => throw http.ClientException('sem rede'), guarda);
    await _aguardarFim(c);
    expect(c.read(sessaoProvider).fase, FaseSessao.logado);
    expect(c.read(sessaoProvider).usuario?.nome, 'Bia');
  });

  test('reabrir com token recusado volta ao login com aviso e apaga a sessao', () async {
    final guarda = ArmazenamentoMemoria()
      ..valor = SessaoSalva(token: 'velho', usuario: UsuarioApi.deJson(_usuario));
    final c = _montar((r) async => _json(401, {'erro': 'nao_autenticado'}), guarda);
    await _aguardarFim(c);
    expect(c.read(sessaoProvider).fase, FaseSessao.deslogado);
    expect(c.read(sessaoProvider).aviso, contains('expirou'));
    expect(guarda.valor, isNull);
  });

  test('usar sem conta fica guardado', () async {
    final guarda = ArmazenamentoMemoria();
    final c = _montar((r) async => _json(500, {}), guarda);
    await _aguardarFim(c);
    await c.read(sessaoProvider.notifier).continuarSemConta();
    expect(c.read(sessaoProvider).fase, FaseSessao.local);

    final c2 = _montar((r) async => _json(500, {}), guarda);
    await _aguardarFim(c2);
    expect(c2.read(sessaoProvider).fase, FaseSessao.local);
  });
}
