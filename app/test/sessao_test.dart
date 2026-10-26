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
    await c.read(sessaoProvider.notifier).cadastrar('Bia', 'a@b.com', 'segredo123',
        cpf: '52998224725', telefone: '11987654321');
    expect(caminhos, ['/cadastro', '/login', '/me']);
    expect(c.read(sessaoProvider).fase, FaseSessao.logado);
  });

  test('login com senha errada nao muda o estado e mostra o erro', () async {
    final c = _montar((r) async => _json(401, {'erro': 'credenciais_invalidas'}), ArmazenamentoMemoria());
    await _aguardarFim(c);
    await expectLater(c.read(sessaoProvider.notifier).entrar('a@b.com', 'x'), throwsA(isA<ErroApi>()));
    expect(c.read(sessaoProvider).fase, FaseSessao.deslogado);
  });

  test('lembrar de mim guarda e-mail e senha; sair apaga so a senha e o token', () async {
    final guarda = ArmazenamentoMemoria();
    final c = _montar((r) async => _json(200, {'token': 'tok', 'expira_em_segundos': 3600, 'usuario': _usuario}), guarda);
    await _aguardarFim(c);
    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123', lembrar: true);
    expect(guarda.valor?.emailLembrado, 'a@b.com');
    expect(guarda.valor?.senhaLembrada, 'segredo123');

    await c.read(sessaoProvider.notifier).sair();
    expect(guarda.valor?.token, isNull);
    expect(guarda.valor?.senhaLembrada, isNull);
    expect(guarda.valor?.emailLembrado, 'a@b.com');
    expect(c.read(sessaoProvider).emailLembrado, 'a@b.com');
  });

  test('sem lembrar, nada de e-mail ou senha fica guardado', () async {
    final guarda = ArmazenamentoMemoria();
    final c = _montar((r) async => _json(200, {'token': 'tok', 'expira_em_segundos': 3600, 'usuario': _usuario}), guarda);
    await _aguardarFim(c);
    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123');
    expect(guarda.valor?.emailLembrado, isNull);
    expect(guarda.valor?.senhaLembrada, isNull);
  });

  test('apos entrar, o perfil traz plano, modulos e permissoes', () async {
    final c = _montar((r) async {
      if (r.url.path == '/login') {
        return _json(200, {'token': 'tok', 'expira_em_segundos': 3600, 'usuario': _usuario});
      }
      return _json(200, {
        'usuario': _usuario,
        'licenca': {'plano': 'anual'},
        'modulos': ['financas'],
        'permissoes': ['acesso.usuario.ver'],
      });
    }, ArmazenamentoMemoria());
    await _aguardarFim(c);
    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123');
    final s = c.read(sessaoProvider);
    expect(s.perfil?.plano, 'anual');
    expect(s.pode('acesso.usuario.ver'), isTrue);
    expect(s.pode('acesso.usuario.editar'), isFalse);
  });

  test('ao abrir, o login e obrigatorio mesmo com sessao valida guardada', () async {
    final guarda = ArmazenamentoMemoria()
      ..valor = SessaoSalva(
          token: 'tok', usuario: UsuarioApi.deJson(_usuario), emailLembrado: 'a@b.com', senhaLembrada: 'segredo123');
    final c = _montar((r) async => _json(200, {'usuario': _usuario}), guarda);
    await _aguardarFim(c);
    final s = c.read(sessaoProvider);
    expect(s.fase, FaseSessao.deslogado);
    expect(s.token, isNull);
    expect(s.emailLembrado, 'a@b.com');
    expect(guarda.valor?.token, isNull);
    expect(guarda.valor?.senhaLembrada, isNull);
  });

  test('ao abrir sem lembrar de mim, nada fica guardado e vai ao login', () async {
    final guarda = ArmazenamentoMemoria()..valor = SessaoSalva(token: 'tok', usuario: UsuarioApi.deJson(_usuario));
    final c = _montar((r) async => _json(200, {'usuario': _usuario}), guarda);
    await _aguardarFim(c);
    expect(c.read(sessaoProvider).fase, FaseSessao.deslogado);
    expect(guarda.valor, isNull);
  });
}
