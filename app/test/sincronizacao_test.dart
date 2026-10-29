import 'dart:convert';
import 'dart:typed_data';

import 'package:controle_pessoal/data/api/cliente_api.dart';
import 'package:controle_pessoal/data/auth/armazenamento_sessao.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/data/sync/servico_sincronizacao.dart';
import 'package:drift/drift.dart' show Value;
import 'package:controle_pessoal/features/auth/sessao.dart';
import 'package:controle_pessoal/features/sync/sincronizacao.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Servidor de mentira com as mesmas regras da API: ultima edicao vence, exclusao vence edicao,
/// cursor = ordem de gravacao no servidor.
class _Servidor {
  final registros = <String, Map<String, dynamic>>{}; // 'tabela|id' -> registro
  final tabelasRecebidas = <String>{};
  var _seq = 0;
  var chamadas = 0;

  Future<http.Response> responder(http.Request r) async {
    chamadas++;
    expect(r.url.path, '/sincronizar');
    expect(r.headers['authorization'], 'Bearer tok');
    final corpo = jsonDecode(r.body) as Map<String, dynamic>;
    final cursor = corpo['cursor'] == null ? 0 : int.parse(corpo['cursor'] as String);
    final conflitos = <Map<String, dynamic>>[];
    final alteracoes = (corpo['alteracoes'] as Map).cast<String, dynamic>();
    for (final e in alteracoes.entries) {
      tabelasRecebidas.add(e.key);
      for (final reg in (e.value as List).cast<Map<String, dynamic>>()) {
        final chave = '${e.key}|${reg['id']}';
        final atual = registros[chave];
        final aceita = atual == null ||
            (atual['excluido_em'] == null &&
                (reg['excluido_em'] != null ||
                    DateTime.parse(reg['editado_em'] as String).isAfter(DateTime.parse(atual['editado_em'] as String))));
        if (aceita) {
          registros[chave] = {...reg, 'tabela': e.key, 'seq': ++_seq};
        } else {
          conflitos.add({'tabela': e.key, 'id': reg['id']});
        }
      }
    }
    final saida = <String, List<Map<String, dynamic>>>{};
    var novo = cursor;
    for (final reg in registros.values) {
      final seq = reg['seq'] as int;
      if (seq > cursor || conflitos.any((c) => c['tabela'] == reg['tabela'] && c['id'] == reg['id'])) {
        (saida[reg['tabela'] as String] ??= []).add({
          'id': reg['id'], 'editado_em': reg['editado_em'], 'excluido_em': reg['excluido_em'], 'dados': reg['dados'],
        });
      }
      if (seq > novo) novo = seq;
    }
    return http.Response.bytes(
        utf8.encode(jsonEncode({'cursor': '$novo', 'tem_mais': false, 'alteracoes': saida, 'conflitos': conflitos})), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

ServicoSincronizacao _servico(Banco banco, _Servidor s) => ServicoSincronizacao(
      banco: banco,
      api: ClienteApi(baseUrl: 'http://api.teste', cliente: MockClient(s.responder)),
      token: 'tok',
    );

void main() {
  late Banco a, b;
  late _Servidor servidor;

  setUp(() {
    a = Banco.paraTeste(NativeDatabase.memory());
    b = Banco.paraTeste(NativeDatabase.memory());
    servidor = _Servidor();
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  test('o que se cadastra num aparelho aparece no outro, com o mesmo id e a capa', () async {
    final capa = Uint8List.fromList([1, 2, 3, 250, 255]);
    final idEvento = await a.inserirEvento(titulo: 'Dentista', inicio: DateTime(2026, 11, 3, 9), tags: 'saude');
    final idLeitura = await a.inserirLeitura(titulo: 'Dom Casmurro', autor: 'Machado', capa: capa, notaDrama: 4);

    final r = await _servico(a, servidor).sincronizar();
    expect(r.enviados, greaterThanOrEqualTo(2));
    final rb = await _servico(b, servidor).sincronizar();
    expect(rb.aplicados, greaterThanOrEqualTo(2));

    final eventos = await b.select(b.eventos).get();
    expect(eventos.single.id, idEvento);
    expect(eventos.single.titulo, 'Dentista');
    expect(eventos.single.tags, 'saude');
    final leituras = await b.select(b.leituras).get();
    expect(leituras.single.id, idLeitura);
    expect(leituras.single.autor, 'Machado');
    expect(leituras.single.notaDrama, 4);
    expect(leituras.single.capa, capa);
  });

  test('sincronizar de novo sem mudancas nao reenvia nem duplica nada', () async {
    await a.inserirEvento(titulo: 'Um', inicio: DateTime(2026, 11, 3, 9));
    final s = _servico(a, servidor);
    await s.sincronizar();
    final antes = servidor.registros.length;
    final r2 = await s.sincronizar();
    expect(r2.aplicados, 0);
    expect(servidor.registros.length, antes);
    await _servico(b, servidor).sincronizar();
    await _servico(b, servidor).sincronizar();
    expect((await b.select(b.eventos).get()), hasLength(1));
  });

  test('edicao mais nova num aparelho chega ao outro; edicao mais antiga e ignorada', () async {
    final id = await a.inserirEvento(titulo: 'Reuniao', inicio: DateTime(2026, 11, 3, 9));
    await _servico(a, servidor).sincronizar();
    await _servico(b, servidor).sincronizar();

    // B edita (5 min depois) e sincroniza; A recebe.
    await (b.update(b.eventos)..where((t) => t.id.equals(id))).write(EventosCompanion(
        titulo: const Value('Reuniao com o time'), atualizadoEm: Value(DateTime.now().add(const Duration(minutes: 5)))));
    await _servico(b, servidor).sincronizar();
    await _servico(a, servidor).sincronizar();
    expect((await a.select(a.eventos).get()).single.titulo, 'Reuniao com o time');

    // A edita com data ANTIGA (relogio atrasado): o servidor recusa e A volta para a versao do servidor.
    await (a.update(a.eventos)..where((t) => t.id.equals(id))).write(EventosCompanion(
        titulo: const Value('Edicao velha'), atualizadoEm: Value(DateTime.now().subtract(const Duration(hours: 2)))));
    // (o envio so leva o que mudou depois do ultimo envio; forca reenviar tudo)
    final sa = _servico(a, servidor);
    await sa.recomecar();
    final r = await sa.sincronizar();
    expect(r.conflitos, greaterThanOrEqualTo(1));
    expect((await a.select(a.eventos).get()).single.titulo, 'Reuniao com o time');
  });

  test('exclusao propaga e o registro continua gravado (exclusao logica)', () async {
    final id = await a.inserirTarefa(titulo: 'Pagar conta');
    await _servico(a, servidor).sincronizar();
    await _servico(b, servidor).sincronizar();
    expect((await b.select(b.tarefas).get()).single.excluidoEm, isNull);

    await a.excluirTarefa(id);
    await _servico(a, servidor).sincronizar();
    await _servico(b, servidor).sincronizar();
    final tb = await b.select(b.tarefas).get();
    expect(tb.single.id, id);
    expect(tb.single.excluidoEm, isNotNull);
  });

  test('o cofre de senhas nao sai do aparelho', () async {
    await a.inserirCredencial(CredenciaisCompanion.insert(titulo: 'Banco'));
    await a.inserirLeitura(titulo: 'Livro');
    await _servico(a, servidor).sincronizar();
    expect(servidor.tabelasRecebidas, contains('leituras'));
    expect(servidor.tabelasRecebidas, isNot(contains('credenciais')));
    await _servico(b, servidor).sincronizar();
    expect(await b.select(b.credenciais).get(), isEmpty);
  });

  test('sem internet o erro sobe e nada se perde; na proxima vez envia', () async {
    await a.inserirLeitura(titulo: 'Livro offline');
    final falha = ServicoSincronizacao(
      banco: a,
      api: ClienteApi(baseUrl: 'http://api.teste', cliente: MockClient((_) async => throw http.ClientException('sem rede'))),
      token: 'tok',
    );
    await expectLater(falha.sincronizar(), throwsA(isA<ErroApi>()));
    expect(servidor.registros, isEmpty);
    await _servico(a, servidor).sincronizar();
    expect(servidor.registros.keys.any((k) => k.startsWith('leituras|')), isTrue);
  });

  test('o botao "Sincronizar agora" (provider): sem conta nao faz nada; logado sincroniza e guarda a hora', () async {
    final c = ProviderContainer(overrides: [
      bancoProvider.overrideWithValue(a),
      armazenamentoSessaoProvider.overrideWithValue(ArmazenamentoMemoria()),
      clienteApiProvider.overrideWithValue(ClienteApi(
          baseUrl: 'http://api.teste',
          cliente: MockClient((r) async {
            if (r.url.path == '/login') {
              return http.Response.bytes(
                  utf8.encode(jsonEncode({
                    'token': 'tok',
                    'expira_em_segundos': 3600,
                    'usuario': {'id': 'u1', 'nome': 'Bia', 'email': 'a@b.com'},
                  })),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }
            if (r.url.path == '/sincronizar') return servidor.responder(r);
            return http.Response('{}', 404);
          }))),
    ]);
    addTearDown(c.dispose);
    final n = c.read(sincronizacaoProvider.notifier);
    expect(await n.sincronizar(), isNull); // ainda sem login
    expect(servidor.chamadas, 0);

    await c.read(sessaoProvider.notifier).entrar('a@b.com', 'segredo123');
    await a.inserirLeitura(titulo: 'Livro do botao');
    final r = await n.sincronizar();
    expect(r, isNotNull);
    expect(c.read(sincronizacaoProvider).ultimaVez, isNotNull);
    expect(c.read(sincronizacaoProvider).erro, isNull);
    expect(servidor.registros.keys.any((k) => k.startsWith('leituras|')), isTrue);
  });
}
