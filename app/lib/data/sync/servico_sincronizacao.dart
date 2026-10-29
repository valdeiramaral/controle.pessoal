import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../api/cliente_api.dart';
import '../local/banco.dart';

/// Resultado de uma rodada de sincronizacao.
class ResultadoSync {
  const ResultadoSync({this.enviados = 0, this.recebidos = 0, this.aplicados = 0, this.conflitos = 0});

  final int enviados;
  final int recebidos;

  /// Registros do servidor que mudaram algo neste aparelho.
  final int aplicados;

  /// Edicoes deste aparelho que o servidor recusou (existia versao mais nova ou excluida).
  final int conflitos;
}

/// Sincronizacao entre o banco local (Drift/SQLite) e o servidor (PostgreSQL).
///
/// Regras (contrato-sincronizacao.md, versao 2):
///  - cada linha das tabelas do app viaja como JSON "cru" (nome da coluna -> valor), com o id (UUID)
///    gerado no aparelho; nenhum campo se perde;
///  - envia o que mudou desde o ultimo envio (atualizado_em >= envio_desde) e recebe o que mudou no
///    servidor depois do cursor (hora do servidor);
///  - conflito: a ultima edicao vence; exclusao (excluido_em) vence edicao; nada e apagado de verdade;
///  - o cofre de senhas (credenciais) NAO sincroniza: a chave de cifra fica so em cada aparelho.
class ServicoSincronizacao {
  ServicoSincronizacao({required this.banco, required this.api, required this.token});

  final Banco banco;
  final ClienteApi api;
  final String token;

  /// Tabelas que ficam so neste aparelho.
  static const apenasLocais = {'usuarios', 'anexos', 'documentos', 'credenciais'};

  static const _tamanhoLote = 25;

  final _colunas = <String, List<String>>{};

  Future<List<String>> _colunasDe(String tabela) async =>
      _colunas[tabela] ??= (await banco.customSelect('PRAGMA table_info($tabela)').get())
          .map((l) => l.read<String>('name'))
          .toList();

  List<String> get _tabelas => [
        for (final t in banco.allTables)
          if (!apenasLocais.contains(t.actualTableName)) t.actualTableName,
      ];

  Future<void> _garantirControle() => banco.customStatement(
      'CREATE TABLE IF NOT EXISTS sinc_controle (chave TEXT NOT NULL PRIMARY KEY, valor TEXT)');

  Future<String?> _ler(String chave) async {
    final r = await banco.customSelect('SELECT valor FROM sinc_controle WHERE chave = ?',
        variables: [Variable.withString(chave)]).get();
    return r.isEmpty ? null : r.first.readNullable<String>('valor');
  }

  Future<void> _gravar(String chave, String valor) => banco.customStatement(
      'INSERT INTO sinc_controle (chave, valor) VALUES (?, ?) ON CONFLICT(chave) DO UPDATE SET valor = excluded.valor',
      [chave, valor]);

  /// Esquece o cursor e o ultimo envio: a proxima rodada reenvia e rebaixa tudo (seguro: e idempotente).
  Future<void> recomecar() async {
    await _garantirControle();
    await banco.customStatement('DELETE FROM sinc_controle');
  }

  Future<ResultadoSync> sincronizar() async {
    await _garantirControle();
    final inicio = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    var cursor = await _ler('cursor');
    final desde = int.tryParse(await _ler('envio_desde') ?? '');

    // Tudo que mudou neste aparelho desde o ultimo envio.
    final pendentes = <(String, Map<String, dynamic>)>[];
    for (final t in _tabelas) {
      final linhas = desde == null
          ? await banco.customSelect('SELECT * FROM $t').get()
          : await banco.customSelect('SELECT * FROM $t WHERE atualizado_em >= ?',
              variables: [Variable.withInt(desde)]).get();
      for (final l in linhas) {
        pendentes.add((t, l.data));
      }
    }

    var enviados = 0, recebidos = 0, aplicados = 0, conflitos = 0;
    var posicao = 0;
    bool temMais;
    do {
      final lote = pendentes.skip(posicao).take(_tamanhoLote).toList();
      posicao += lote.length;
      final alteracoes = <String, List<Map<String, dynamic>>>{};
      for (final (t, linha) in lote) {
        (alteracoes[t] ??= []).add(_paraRegistro(linha));
      }
      final r = await api.sincronizar(token, cursor: cursor, alteracoes: alteracoes);
      enviados += lote.length;
      conflitos += (r['conflitos'] as List? ?? const []).length;
      final recebido = (r['alteracoes'] as Map?)?.cast<String, dynamic>() ?? const {};
      for (final e in recebido.entries) {
        for (final reg in (e.value as List).cast<Map<String, dynamic>>()) {
          recebidos++;
          if (await _aplicar(e.key, reg)) aplicados++;
        }
      }
      cursor = (r['cursor'] as String?) ?? cursor;
      if (cursor != null) await _gravar('cursor', cursor);
      temMais = r['tem_mais'] == true;
    } while (posicao < pendentes.length || temMais);

    await _gravar('envio_desde', '${inicio - 1}');
    if (aplicados > 0) {
      banco.markTablesUpdated(banco.allTables);
    }
    return ResultadoSync(enviados: enviados, recebidos: recebidos, aplicados: aplicados, conflitos: conflitos);
  }

  // ------------------------------------------------------------------ conversao

  static String _iso(int segundos) =>
      DateTime.fromMillisecondsSinceEpoch(segundos * 1000, isUtc: true).toIso8601String();

  Map<String, dynamic> _paraRegistro(Map<String, dynamic> linha) {
    final dados = <String, dynamic>{
      for (final e in linha.entries) e.key: e.value is Uint8List ? {'__b64': base64Encode(e.value as Uint8List)} : e.value,
    };
    final editado = linha['atualizado_em'];
    final excluido = linha['excluido_em'];
    return {
      'id': linha['id'],
      'editado_em': _iso(editado is int ? editado : 0),
      'excluido_em': excluido is int ? _iso(excluido) : null,
      'dados': dados,
    };
  }

  dynamic _doJson(dynamic v) {
    if (v is Map && v['__b64'] is String) return base64Decode(v['__b64'] as String);
    if (v is bool) return v ? 1 : 0;
    return v;
  }

  /// Aplica um registro vindo do servidor. Devolve true se mudou algo neste aparelho.
  Future<bool> _aplicar(String tabela, Map<String, dynamic> reg) async {
    final colunasLocais = await _colunasDe(tabela);
    if (colunasLocais.isEmpty) return false; // tabela que este aparelho ainda nao conhece
    final dados = (reg['dados'] as Map).cast<String, dynamic>();
    final id = reg['id'] as String;
    final entrada = (reg['excluido_em'] as String?) != null;

    final local = await banco.customSelect('SELECT atualizado_em, excluido_em FROM $tabela WHERE id = ?',
        variables: [Variable.withString(id)]).get();
    if (local.isNotEmpty) {
      final l = local.first;
      if (l.readNullable<int>('excluido_em') != null) return false; // exclusao vence edicao
      final meu = l.readNullable<int>('atualizado_em') ?? 0;
      final dele = dados['atualizado_em'];
      if (!entrada && dele is int && meu >= dele) return false; // a ultima edicao vence (empate: nada a fazer)
    }

    final cols = [for (final c in colunasLocais) if (dados.containsKey(c)) c];
    if (!cols.contains('id')) return false;
    final marcas = List.filled(cols.length, '?').join(', ');
    final atualiza = [for (final c in cols) if (c != 'id') '$c = excluded.$c'].join(', ');
    await banco.customStatement(
      'INSERT INTO $tabela (${cols.join(', ')}) VALUES ($marcas)'
      '${atualiza.isEmpty ? '' : ' ON CONFLICT(id) DO UPDATE SET $atualiza'}',
      [for (final c in cols) _doJson(dados[c])],
    );
    return true;
  }
}
