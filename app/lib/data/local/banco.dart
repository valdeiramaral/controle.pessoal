import '../../features/auth/sessao.dart';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/lancamento_calculo.dart';
import '../../core/pagamento.dart';
import '../../core/saude_calculo.dart';
import 'tabelas.dart';

part 'banco.g.dart';

/// Conta criada automaticamente na primeira abertura do app.
const contaPadraoId = 'conta-padrao';

/// Arquivo a anexar ao lancar (sem depender do seletor de arquivos).
class ArquivoParaAnexar {
  const ArquivoParaAnexar({required this.nome, required this.bytes, this.tipoMime});
  final String nome;
  final Uint8List bytes;
  final String? tipoMime;
}

List<int> _dividir(int total, int n) => dividirParcelas(total, n);
DateTime _somarMeses(DateTime d, int m) => adicionarMeses(d, m);

@DriftDatabase(tables: [
  Usuarios,
  Contas,
  Categorias,
  Eventos,
  Tarefas,
  Lancamentos,
  Anexos,
  Orcamentos,
  Metas,
  Consultas,
  Medicamentos,
  AgendamentosSaude,
  RegistrosTomada,
  Indicadores,
  Documentos,
  Lembretes,
])
class Banco extends _$Banco {
  // TODO (requisito de seguranca): trocar por SQLCipher para criptografar o
  // arquivo do banco no aparelho, com a chave guardada no Keychain/Keystore.
  /// Cada usuario tem o proprio arquivo de banco no aparelho: [usuarioId] entra no nome,
  /// entao quem entra depois nunca enxerga lancamentos, agenda ou remedios de outra pessoa.
  Banco({String? usuarioId}) : super(driftDatabase(
          name: 'controle_pessoal_${nomeSeguro(usuarioId)}',
          // Na web o SQLite roda em WebAssembly (arquivos em app/web/).
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ));

  /// Para testes (banco em memoria).
  Banco.paraTeste(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(contas).insert(ContasCompanion.insert(
            id: const Value(contaPadraoId),
            nome: 'Carteira',
            tipo: 'dinheiro',
          ));
        },
        onUpgrade: (m, de, para) async {
          if (de < 2) {
            // v2: dados bancarios na conta.
            await m.addColumn(contas, contas.titularidade);
            await m.addColumn(contas, contas.banco);
            await m.addColumn(contas, contas.agencia);
            await m.addColumn(contas, contas.numeroConta);
            await m.addColumn(contas, contas.documento);
            await m.addColumn(contas, contas.chavePix);
            await m.addColumn(contas, contas.apelido);
          }
          if (de < 3) {
            // v3: anexos dos lancamentos.
            await m.createTable(anexos);
          }
          if (de < 4) {
            // v4: dados do pagamento/recebimento no lancamento.
            await m.addColumn(lancamentos, lancamentos.dataPagamento);
            await m.addColumn(lancamentos, lancamentos.formaPagamento);
            await m.addColumn(lancamentos, lancamentos.contaPagamentoId);
            await m.addColumn(lancamentos, lancamentos.tipoPagamento);
            await m.addColumn(lancamentos, lancamentos.valorPagoCentavos);
            await m.addColumn(lancamentos, lancamentos.descontoCentavos);
          }
          if (de < 5) {
            // v5: posologia/estoque dos medicamentos e agendamentos de saude.
            await m.addColumn(medicamentos, medicamentos.formato);
            await m.addColumn(medicamentos, medicamentos.tratamento);
            await m.addColumn(medicamentos, medicamentos.instrucoes);
            await m.addColumn(medicamentos, medicamentos.quantidade);
            await m.addColumn(medicamentos, medicamentos.frequencia);
            await m.addColumn(medicamentos, medicamentos.diasSemana);
            await m.addColumn(medicamentos, medicamentos.intervaloDias);
            await m.addColumn(medicamentos, medicamentos.ativo);
            await m.addColumn(medicamentos, medicamentos.lembreteReabastecer);
            await m.createTable(agendamentosSaude);
          }
          if (de < 6) {
            // v6: tipo (referencia/generico/similar), fabricante, validade, posologia e informacoes do medicamento.
            await m.addColumn(medicamentos, medicamentos.tipoMedicamento);
            await m.addColumn(medicamentos, medicamentos.fabricante);
            await m.addColumn(medicamentos, medicamentos.validade);
            await m.addColumn(medicamentos, medicamentos.posologia);
            await m.addColumn(medicamentos, medicamentos.informacoes);
          }
          if (de < 7) {
            // v7: periodo de uso do medicamento (continuo, diario, semanal ou mensal) e por quanto tempo.
            await m.addColumn(medicamentos, medicamentos.periodoUso);
            await m.addColumn(medicamentos, medicamentos.duracaoUso);
          }
        },
      );

  static const _uuid = Uuid();

  // ------------------------- Financas -------------------------

  Stream<List<Conta>> observarContas() => (select(contas)
        ..where((c) => c.excluidoEm.isNull())
        ..orderBy([(c) => OrderingTerm.asc(c.nome)]))
      .watch();

  Stream<List<Lancamento>> observarLancamentos() => (select(lancamentos)
        ..where((l) => l.excluidoEm.isNull())
        ..orderBy([(l) => OrderingTerm.desc(l.dia)]))
      .watch();

  Stream<List<Lancamento>> observarContasPendentes({required DateTime ate}) =>
      (select(lancamentos)
            ..where((l) =>
                l.excluidoEm.isNull() &
                l.status.equals('pendente') &
                l.dia.isSmallerOrEqualValue(ate))
            ..orderBy([(l) => OrderingTerm.asc(l.dia)]))
          .watch();

  Future<String> inserirLancamento({
    required String descricao,
    required int valorCentavos,
    required String tipo,
    bool pago = false,
    DateTime? dia,
    String? contaId,
    String? categoriaId,
    String? recorrencia,
    int? parcelaNumero,
    int? parcelaTotal,
    String? grupoParcelas,
    String tags = '',
    String? observacao,
    DadosPagamento? pagamento,
  }) async {
    final id = _uuid.v4();
    await into(lancamentos).insert(LancamentosCompanion.insert(
      id: Value(id),
      contaId: contaId ?? contaPadraoId,
      categoriaId: Value(categoriaId),
      descricao: descricao,
      valorCentavos: valorCentavos,
      dia: dia ?? DateTime.now(),
      tipo: tipo,
      status: Value(pago || (pagamento?.quita ?? false) ? 'pago' : 'pendente'),
      recorrencia: Value(recorrencia),
      parcelaNumero: Value(parcelaNumero),
      parcelaTotal: Value(parcelaTotal),
      grupoParcelas: Value(grupoParcelas),
      tags: Value(tags),
      observacao: Value(observacao),
      dataPagamento: Value(pagamento?.data),
      formaPagamento: Value(pagamento?.forma),
      contaPagamentoId: Value(pagamento?.contaId),
      tipoPagamento: Value(pagamento?.tipo),
      valorPagoCentavos: Value(pagamento?.valorPagoCentavos),
      descontoCentavos: Value(pagamento?.descontoCentavos),
    ));
    return id;
  }

  /// Lanca uma despesa/receita completa, como o formulario envia.
  /// [repeticao]: 'unica' | 'fixa' | 'parcelada'.
  /// - unica: um lancamento ([pago] vale).
  /// - fixa: [vezes] lancamentos mensais (recorrencia mensal), todos pendentes.
  /// - parcelada: [valorCentavos] e o TOTAL, dividido em [vezes] parcelas que somam o total.
  /// Os anexos ficam no primeiro lancamento da serie. Devolve os ids criados.
  Future<List<String>> lancar({
    required String descricao,
    required int valorCentavos,
    required String tipo,
    required DateTime vencimento,
    required String contaId,
    String? categoriaId,
    String repeticao = 'unica',
    int vezes = 1,
    bool pago = false,
    String tags = '',
    String? observacao,
    DadosPagamento? pagamento,
    List<ArquivoParaAnexar> anexos = const [],
  }) async {
    final ids = <String>[];
    await transaction(() async {
      if (repeticao == 'parcelada') {
        final valores = _dividir(valorCentavos, vezes);
        final grupo = _uuid.v4();
        for (var i = 0; i < vezes; i++) {
          ids.add(await inserirLancamento(
            descricao: '$descricao (${i + 1}/$vezes)',
            valorCentavos: valores[i],
            tipo: tipo,
            dia: _somarMeses(vencimento, i),
            contaId: contaId,
            categoriaId: categoriaId,
            parcelaNumero: i + 1,
            parcelaTotal: vezes,
            grupoParcelas: grupo,
            tags: tags,
            observacao: observacao,
          ));
        }
      } else if (repeticao == 'fixa') {
        final grupo = _uuid.v4();
        for (var i = 0; i < vezes; i++) {
          ids.add(await inserirLancamento(
            descricao: descricao,
            valorCentavos: valorCentavos,
            tipo: tipo,
            dia: _somarMeses(vencimento, i),
            contaId: contaId,
            categoriaId: categoriaId,
            recorrencia: 'FREQ=MONTHLY',
            grupoParcelas: grupo,
            tags: tags,
            observacao: observacao,
          ));
        }
      } else {
        ids.add(await inserirLancamento(
          descricao: descricao,
          valorCentavos: valorCentavos,
          tipo: tipo,
          pago: pago,
          dia: vencimento,
          contaId: contaId,
          categoriaId: categoriaId,
          tags: tags,
          observacao: observacao,
          pagamento: pagamento,
        ));
      }
      for (final a in anexos) {
        await inserirAnexo(lancamentoId: ids.first, nome: a.nome, bytes: a.bytes, tipoMime: a.tipoMime);
      }
    });
    return ids;
  }

  Future<String> inserirAnexo({
    required String lancamentoId,
    required String nome,
    required Uint8List bytes,
    String? tipoMime,
  }) async {
    final id = _uuid.v4();
    await into(anexos).insert(AnexosCompanion.insert(
      id: Value(id),
      lancamentoId: lancamentoId,
      nomeArquivo: nome,
      tipoMime: Value(tipoMime),
      tamanhoBytes: bytes.length,
      dados: bytes,
    ));
    return id;
  }

  Stream<Lancamento?> observarLancamento(String id) =>
      (select(lancamentos)..where((l) => l.id.equals(id) & l.excluidoEm.isNull())).watchSingleOrNull();

  Future<Lancamento?> lancamentoPorId(String id) =>
      (select(lancamentos)..where((l) => l.id.equals(id))).getSingleOrNull();

  /// Conteudo (bytes) de um anexo, lido so quando o usuario abre/baixa.
  Future<Uint8List?> conteudoDoAnexo(String id) async =>
      (await (select(anexos)..where((a) => a.id.equals(id))).getSingleOrNull())?.dados;

  Future<void> excluirAnexo(String id) => (update(anexos)..where((a) => a.id.equals(id))).write(
        AnexosCompanion(excluidoEm: Value(DateTime.now()), atualizadoEm: Value(DateTime.now())),
      );

  /// Lancamentos da mesma serie (fixa/parcelada) com vencimento depois de [l].
  Future<List<Lancamento>> _seguintesDaSerie(Lancamento l) async {
    final g = l.grupoParcelas;
    if (g == null) return const [];
    return (select(lancamentos)
          ..where((t) => t.grupoParcelas.equals(g) & t.excluidoEm.isNull() & t.dia.isBiggerThanValue(l.dia)))
        .get();
  }

  /// Quantos lancamentos ativos vem depois deste na mesma serie.
  Future<int> contarSeguintesDaSerie(Lancamento l) async => (await _seguintesDaSerie(l)).length;

  /// Edita um lancamento. Valor, descricao, vencimento e situacao valem so para ele;
  /// conta, categoria, tags e observacao tambem vao para os seguintes da serie se [aplicarNosSeguintes].
  /// Anexos: [anexosRemovidos] saem (exclusao logica) e [novosAnexos] entram neste lancamento.
  Future<void> atualizarLancamento(
    Lancamento original, {
    required String descricao,
    required int valorCentavos,
    required DateTime dia,
    required String contaId,
    String? categoriaId,
    required String tags,
    String? observacao,
    required bool pago,
    DadosPagamento? pagamento,
    bool aplicarNosSeguintes = false,
    List<ArquivoParaAnexar> novosAnexos = const [],
    List<String> anexosRemovidos = const [],
  }) async {
    final agora = DateTime.now();
    await transaction(() async {
      final seguintes = aplicarNosSeguintes ? await _seguintesDaSerie(original) : const <Lancamento>[];
      await (update(lancamentos)..where((t) => t.id.equals(original.id))).write(LancamentosCompanion(
        descricao: Value(descricao),
        valorCentavos: Value(valorCentavos),
        dia: Value(dia),
        contaId: Value(contaId),
        categoriaId: Value(categoriaId),
        tags: Value(tags),
        observacao: Value(observacao),
        status: Value(pago || (pagamento?.quita ?? false) ? 'pago' : 'pendente'),
        dataPagamento: Value(pagamento?.data),
        formaPagamento: Value(pagamento?.forma),
        contaPagamentoId: Value(pagamento?.contaId),
        tipoPagamento: Value(pagamento?.tipo),
        valorPagoCentavos: Value(pagamento?.valorPagoCentavos),
        descontoCentavos: Value(pagamento?.descontoCentavos),
        atualizadoEm: Value(agora),
      ));
      for (final s in seguintes) {
        await (update(lancamentos)..where((t) => t.id.equals(s.id))).write(LancamentosCompanion(
          contaId: Value(contaId),
          categoriaId: Value(categoriaId),
          tags: Value(tags),
          observacao: Value(observacao),
          atualizadoEm: Value(agora),
        ));
      }
      for (final id in anexosRemovidos) {
        await excluirAnexo(id);
      }
      for (final a in novosAnexos) {
        await inserirAnexo(lancamentoId: original.id, nome: a.nome, bytes: a.bytes, tipoMime: a.tipoMime);
      }
    });
  }

  /// Exclusao logica do lancamento; com [seguintes] tambem os da serie com vencimento posterior.
  /// Os anexos dos excluidos tambem saem. Devolve quantos lancamentos foram excluidos.
  Future<int> excluirLancamentoDaSerie(Lancamento l, {bool seguintes = false}) async {
    final alvos = [l, if (seguintes) ...await _seguintesDaSerie(l)];
    final agora = DateTime.now();
    await transaction(() async {
      for (final a in alvos) {
        await (update(lancamentos)..where((t) => t.id.equals(a.id)))
            .write(LancamentosCompanion(excluidoEm: Value(agora), atualizadoEm: Value(agora)));
        await (update(anexos)..where((t) => t.lancamentoId.equals(a.id) & t.excluidoEm.isNull()))
            .write(AnexosCompanion(excluidoEm: Value(agora), atualizadoEm: Value(agora)));
      }
    });
    return alvos.length;
  }

  /// Consulta unica (sem stream) dos anexos ativos de um lancamento.
  Future<List<Anexo>> listarAnexos(String lancamentoId) => (select(anexos)
        ..where((a) => a.lancamentoId.equals(lancamentoId) & a.excluidoEm.isNull())
        ..orderBy([(a) => OrderingTerm.asc(a.criadoEm)]))
      .get();

  /// Consulta unica (sem stream) dos lancamentos ativos.
  Future<List<Lancamento>> listarLancamentos() =>
      (select(lancamentos)..where((l) => l.excluidoEm.isNull())..orderBy([(l) => OrderingTerm.desc(l.dia)])).get();

  /// Anexos ativos de um lancamento (sem o conteudo, so a lista).
  Stream<List<Anexo>> observarAnexos(String lancamentoId) => (select(anexos)
        ..where((a) => a.lancamentoId.equals(lancamentoId) & a.excluidoEm.isNull())
        ..orderBy([(a) => OrderingTerm.asc(a.criadoEm)]))
      .watch();

  /// Quantos anexos ativos cada lancamento tem (para o clipe na listagem).
  Stream<Map<String, int>> observarContagemAnexos() => (select(anexos)..where((a) => a.excluidoEm.isNull())).watch().map((l) {
        final m = <String, int>{};
        for (final a in l) {
          m[a.lancamentoId] = (m[a.lancamentoId] ?? 0) + 1;
        }
        return m;
      });

  /// Cria [parcelas] lancamentos mensais (a primeira em [primeiroDia]); [valorParcelaCentavos] e o valor de cada uma.
  Future<void> inserirParcelado({
    required String descricao,
    required int valorParcelaCentavos,
    required String tipo,
    required int parcelas,
    required DateTime primeiroDia,
    String? contaId,
    String? categoriaId,
  }) async {
    final grupo = _uuid.v4();
    for (var i = 0; i < parcelas; i++) {
      await inserirLancamento(
        descricao: '$descricao (${i + 1}/$parcelas)',
        valorCentavos: valorParcelaCentavos,
        tipo: tipo,
        pago: false,
        dia: adicionarMeses(primeiroDia, i),
        contaId: contaId,
        categoriaId: categoriaId,
        parcelaNumero: i + 1,
        parcelaTotal: parcelas,
        grupoParcelas: grupo,
      );
    }
  }

  Stream<List<Categoria>> observarCategorias() => (select(categorias)
        ..where((c) => c.excluidoEm.isNull())
        ..orderBy([(c) => OrderingTerm.asc(c.nome)]))
      .watch();

  Stream<List<Orcamento>> observarOrcamentos() =>
      (select(orcamentos)..where((o) => o.excluidoEm.isNull())).watch();

  Future<String> inserirCategoria({
    required String nome,
    String tipo = 'despesa',
    String? cor,
  }) async {
    final id = _uuid.v4();
    await into(categorias).insert(CategoriasCompanion.insert(
      id: Value(id),
      nome: nome,
      tipo: tipo,
      cor: Value(cor),
    ));
    return id;
  }

  /// Cria uma conta (bancaria ou nao). [titularidade]: 'propria' ou 'externa'.
  Future<String> inserirConta({
    required String nome,
    String tipo = 'corrente',
    int saldoInicialCentavos = 0,
    String titularidade = 'propria',
    String? banco,
    String? agencia,
    String? numeroConta,
    String? documento,
    String? chavePix,
    String? apelido,
  }) async {
    final id = _uuid.v4();
    await into(contas).insert(ContasCompanion.insert(
      id: Value(id),
      nome: nome,
      tipo: tipo,
      saldoInicialCentavos: Value(saldoInicialCentavos),
      titularidade: Value(titularidade),
      banco: Value(banco),
      agencia: Value(agencia),
      numeroConta: Value(numeroConta),
      documento: Value(documento),
      chavePix: Value(chavePix),
      apelido: Value(apelido),
    ));
    return id;
  }

  Future<void> atualizarConta(
    String id, {
    required String nome,
    required String tipo,
    required int saldoInicialCentavos,
    required String titularidade,
    String? banco,
    String? agencia,
    String? numeroConta,
    String? documento,
    String? chavePix,
    String? apelido,
  }) =>
      (update(contas)..where((c) => c.id.equals(id))).write(ContasCompanion(
        nome: Value(nome),
        tipo: Value(tipo),
        saldoInicialCentavos: Value(saldoInicialCentavos),
        titularidade: Value(titularidade),
        banco: Value(banco),
        agencia: Value(agencia),
        numeroConta: Value(numeroConta),
        documento: Value(documento),
        chavePix: Value(chavePix),
        apelido: Value(apelido),
        atualizadoEm: Value(DateTime.now()),
      ));

  /// Ja existe outra conta (ativa) com o mesmo banco, agencia e numero?
  Future<bool> existeContaBancaria({
    required String banco,
    required String agencia,
    required String numeroConta,
    String? ignorarId,
  }) async {
    final q = select(contas)
      ..where((c) =>
          c.excluidoEm.isNull() &
          c.banco.equals(banco) &
          c.agencia.equals(agencia) &
          c.numeroConta.equals(numeroConta));
    final achadas = await q.get();
    return achadas.any((c) => c.id != ignorarId);
  }

  Stream<Conta?> observarConta(String id) =>
      (select(contas)..where((c) => c.id.equals(id) & c.excluidoEm.isNull())).watchSingleOrNull();

  Future<int> contarLancamentosDaConta(String id) async {
    final n = countAll();
    final q = selectOnly(lancamentos)
      ..addColumns([n])
      ..where(lancamentos.contaId.equals(id) & lancamentos.excluidoEm.isNull());
    return (await q.getSingle()).read(n) ?? 0;
  }

  /// Exclusao logica. Recusa (retorna o motivo) a conta padrao e contas com lancamentos; null = excluida.
  Future<String?> excluirConta(String id) async {
    if (id == contaPadraoId) return 'A conta padrão (Carteira) não pode ser excluída.';
    final n = await contarLancamentosDaConta(id);
    if (n > 0) return 'Esta conta tem $n lançamento(s). Exclua ou mude os lançamentos antes.';
    await (update(contas)..where((c) => c.id.equals(id))).write(
      ContasCompanion(excluidoEm: Value(DateTime.now()), atualizadoEm: Value(DateTime.now())),
    );
    return null;
  }

  /// Define (ou troca) o limite mensal de uma categoria; [mes] e normalizado para o dia 1.
  Future<void> definirOrcamento({
    required String categoriaId,
    required DateTime mes,
    required int valorLimiteCentavos,
  }) async {
    final m = DateTime(mes.year, mes.month, 1);
    final existente = await (select(orcamentos)
          ..where((o) =>
              o.excluidoEm.isNull() &
              o.categoriaId.equals(categoriaId) &
              o.mes.equals(m)))
        .getSingleOrNull();
    if (existente == null) {
      await into(orcamentos).insert(OrcamentosCompanion.insert(
        categoriaId: categoriaId,
        mes: m,
        valorLimiteCentavos: valorLimiteCentavos,
      ));
    } else {
      await (update(orcamentos)..where((o) => o.id.equals(existente.id))).write(
        OrcamentosCompanion(
          valorLimiteCentavos: Value(valorLimiteCentavos),
          atualizadoEm: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<void> excluirOrcamento(String id) =>
      (update(orcamentos)..where((t) => t.id.equals(id))).write(
        OrcamentosCompanion(
          excluidoEm: Value(DateTime.now()),
          atualizadoEm: Value(DateTime.now()),
        ),
      );

  /// Marca como pago (total, hoje, sem detalhes) ou desfaz o pagamento (limpa os dados registrados).
  Future<void> alternarPagamento(Lancamento l) {
    final pagar = l.status != 'pago';
    return (update(lancamentos)..where((t) => t.id.equals(l.id))).write(
      LancamentosCompanion(
        status: Value(pagar ? 'pago' : 'pendente'),
        dataPagamento: Value(pagar ? DateTime.now() : null),
        formaPagamento: const Value(null),
        contaPagamentoId: const Value(null),
        tipoPagamento: Value(pagar ? 'total' : null),
        valorPagoCentavos: const Value(null),
        descontoCentavos: const Value(null),
        atualizadoEm: Value(DateTime.now()),
      ),
    );
  }

  /// Desfaz o pagamento/recebimento (volta a pendente e limpa os dados registrados).
  Future<void> desfazerPagamento(Lancamento l) => (update(lancamentos)..where((t) => t.id.equals(l.id))).write(
        LancamentosCompanion(
          status: const Value('pendente'),
          dataPagamento: const Value(null),
          formaPagamento: const Value(null),
          contaPagamentoId: const Value(null),
          tipoPagamento: const Value(null),
          valorPagoCentavos: const Value(null),
          descontoCentavos: const Value(null),
          atualizadoEm: Value(DateTime.now()),
        ),
      );

  /// Exclusao logica (necessaria para a sincronizacao propagar a exclusao).
  Future<void> excluirLancamento(String id) =>
      (update(lancamentos)..where((t) => t.id.equals(id))).write(
        LancamentosCompanion(
          excluidoEm: Value(DateTime.now()),
          atualizadoEm: Value(DateTime.now()),
        ),
      );

  // --------------------------- Agenda ---------------------------

  Stream<List<Evento>> observarEventosFuturos() => (select(eventos)
        ..where((e) =>
            e.excluidoEm.isNull() &
            e.inicio.isBiggerOrEqualValue(
                DateTime.now().subtract(const Duration(hours: 1))))
        ..orderBy([(e) => OrderingTerm.asc(e.inicio)]))
      .watch();

  /// Eventos que comecam entre [de] e [ate] (dias inclusivos).
  Stream<List<Evento>> observarEventosEntre(DateTime de, DateTime ate) {
    final ini = DateTime(de.year, de.month, de.day);
    final fim = DateTime(ate.year, ate.month, ate.day).add(const Duration(days: 1));
    return (select(eventos)
          ..where((e) =>
              e.excluidoEm.isNull() &
              e.inicio.isBiggerOrEqualValue(ini) &
              e.inicio.isSmallerThanValue(fim))
          ..orderBy([(e) => OrderingTerm.asc(e.inicio)]))
        .watch();
  }

  Stream<List<Evento>> observarEventosDoDia(DateTime dia) {
    final ini = DateTime(dia.year, dia.month, dia.day);
    final fim = ini.add(const Duration(days: 1));
    return (select(eventos)
          ..where((e) =>
              e.excluidoEm.isNull() &
              e.inicio.isBiggerOrEqualValue(ini) &
              e.inicio.isSmallerThanValue(fim))
          ..orderBy([(e) => OrderingTerm.asc(e.inicio)]))
        .watch();
  }

  /// Retorna o id do evento criado.
  Future<String> inserirEvento({
    required String titulo,
    required DateTime inicio,
    String tipo = 'pessoal',
  }) async {
    final id = _uuid.v4();
    await into(eventos).insert(EventosCompanion.insert(
      id: Value(id),
      titulo: titulo,
      inicio: inicio,
      tipo: Value(tipo),
    ));
    return id;
  }

  Future<void> excluirEvento(String id) =>
      (update(eventos)..where((t) => t.id.equals(id))).write(
        EventosCompanion(
          excluidoEm: Value(DateTime.now()),
          atualizadoEm: Value(DateTime.now()),
        ),
      );

  // --------------------------- Saude ---------------------------

  Stream<List<Medicamento>> observarMedicamentos() => (select(medicamentos)
        ..where((m) => m.excluidoEm.isNull())
        ..orderBy([(m) => OrderingTerm.asc(m.nome)]))
      .watch();

  Future<List<Medicamento>> listarMedicamentos() => (select(medicamentos)
        ..where((m) => m.excluidoEm.isNull())
        ..orderBy([(m) => OrderingTerm.asc(m.nome)]))
      .get();

  Future<Medicamento?> medicamentoPorId(String id) =>
      (select(medicamentos)..where((m) => m.id.equals(id))).getSingleOrNull();

  /// [horarios] no formato "08:00,20:00" (vazio se for so "quando necessario"). Retorna o id do medicamento.
  Future<String> inserirMedicamento({
    required String nome,
    required String dose,
    required String horarios,
    String formato = 'comprimido',
    String? tratamento,
    String? instrucoes,
    int quantidade = 1,
    String frequencia = 'diaria',
    String diasSemana = '',
    int intervaloDias = 1,
    DateTime? inicio,
    DateTime? fim,
    int? estoque,
    int? estoqueMinimo,
    bool lembreteReabastecer = true,
    String? tipoMedicamento,
    String? fabricante,
    DateTime? validade,
    String? posologia,
    String? informacoes,
    String periodoUso = 'continuo',
    int? duracaoUso,
  }) async {
    final id = _uuid.v4();
    await into(medicamentos).insert(MedicamentosCompanion.insert(
      id: Value(id),
      nome: nome,
      dose: dose,
      horarios: horarios,
      inicio: inicio ?? DateTime.now(),
      formato: Value(formato),
      tratamento: Value(tratamento),
      instrucoes: Value(instrucoes),
      quantidade: Value(quantidade),
      frequencia: Value(frequencia),
      diasSemana: Value(diasSemana),
      intervaloDias: Value(intervaloDias),
      fim: Value(fim),
      estoque: Value(estoque),
      estoqueMinimo: Value(estoqueMinimo),
      lembreteReabastecer: Value(lembreteReabastecer),
      tipoMedicamento: Value(tipoMedicamento),
      fabricante: Value(fabricante),
      validade: Value(validade),
      posologia: Value(posologia),
      informacoes: Value(informacoes),
      periodoUso: Value(periodoUso),
      duracaoUso: Value(duracaoUso),
    ));
    return id;
  }

  /// Regrava todos os dados editaveis do medicamento.
  Future<void> atualizarMedicamento(
    String id, {
    required String nome,
    required String dose,
    required String horarios,
    required String formato,
    String? tratamento,
    String? instrucoes,
    required int quantidade,
    required String frequencia,
    required String diasSemana,
    required int intervaloDias,
    required DateTime inicio,
    DateTime? fim,
    int? estoque,
    int? estoqueMinimo,
    required bool lembreteReabastecer,
    String? tipoMedicamento,
    String? fabricante,
    DateTime? validade,
    String? posologia,
    String? informacoes,
    String periodoUso = 'continuo',
    int? duracaoUso,
  }) =>
      (update(medicamentos)..where((t) => t.id.equals(id))).write(MedicamentosCompanion(
        nome: Value(nome),
        dose: Value(dose),
        horarios: Value(horarios),
        formato: Value(formato),
        tratamento: Value(tratamento),
        instrucoes: Value(instrucoes),
        quantidade: Value(quantidade),
        frequencia: Value(frequencia),
        diasSemana: Value(diasSemana),
        intervaloDias: Value(intervaloDias),
        inicio: Value(inicio),
        fim: Value(fim),
        estoque: Value(estoque),
        estoqueMinimo: Value(estoqueMinimo),
        lembreteReabastecer: Value(lembreteReabastecer),
        tipoMedicamento: Value(tipoMedicamento),
        fabricante: Value(fabricante),
        validade: Value(validade),
        posologia: Value(posologia),
        informacoes: Value(informacoes),
        periodoUso: Value(periodoUso),
        duracaoUso: Value(duracaoUso),
        atualizadoEm: Value(DateTime.now()),
      ));

  /// Suspende ("nao estou tomando": sem doses nem lembretes) ou reativa o medicamento.
  Future<void> definirAtivoMedicamento(String id, bool ativo) =>
      (update(medicamentos)..where((t) => t.id.equals(id))).write(
        MedicamentosCompanion(ativo: Value(ativo), atualizadoEm: Value(DateTime.now())),
      );

  Future<void> ajustarEstoque(String id, int? estoque) =>
      (update(medicamentos)..where((t) => t.id.equals(id))).write(
        MedicamentosCompanion(estoque: Value(estoque), atualizadoEm: Value(DateTime.now())),
      );

  Future<void> _mexerEstoque(String id, int delta) async {
    final m = await medicamentoPorId(id);
    if (m == null || m.estoque == null) return;
    final novo = m.estoque! + delta;
    await ajustarEstoque(id, novo < 0 ? 0 : novo);
  }

  Stream<List<RegistroTomada>> observarTomadasDoDia(DateTime dia) {
    final ini = DateTime(dia.year, dia.month, dia.day);
    final fim = ini.add(const Duration(days: 1));
    return (select(registrosTomada)
          ..where((r) =>
              r.excluidoEm.isNull() & r.horarioPrevisto.isBiggerOrEqualValue(ini) & r.horarioPrevisto.isSmallerThanValue(fim))
          ..orderBy([(r) => OrderingTerm.asc(r.horarioPrevisto)]))
        .watch();
  }

  Future<List<RegistroTomada>> listarTomadasDoDia(DateTime dia) {
    final ini = DateTime(dia.year, dia.month, dia.day);
    final fim = ini.add(const Duration(days: 1));
    return (select(registrosTomada)
          ..where((r) =>
              r.excluidoEm.isNull() & r.horarioPrevisto.isBiggerOrEqualValue(ini) & r.horarioPrevisto.isSmallerThanValue(fim))
          ..orderBy([(r) => OrderingTerm.asc(r.horarioPrevisto)]))
        .get();
  }

  /// Marca a dose prevista como 'tomou', 'pulou' ou volta para 'pendente'.
  /// Tomar desconta [Medicamento.quantidade] do estoque; desfazer devolve (sem passar de zero).
  Future<void> registrarTomada(Medicamento m, DateTime previsto, {String status = 'tomou', DateTime? real}) =>
      transaction(() async {
        final existentes = await (select(registrosTomada)
              ..where((r) => r.medicamentoId.equals(m.id) & r.horarioPrevisto.equals(previsto) & r.excluidoEm.isNull()))
            .get();
        final antes = existentes.isEmpty ? null : existentes.first.status;
        final horarioReal = status == 'pendente' ? null : (real ?? DateTime.now());
        if (existentes.isEmpty) {
          await into(registrosTomada).insert(RegistrosTomadaCompanion.insert(
            medicamentoId: m.id,
            horarioPrevisto: previsto,
            status: Value(status),
            horarioReal: Value(horarioReal),
          ));
        } else {
          await (update(registrosTomada)..where((r) => r.id.equals(existentes.first.id))).write(RegistrosTomadaCompanion(
            status: Value(status),
            horarioReal: Value(horarioReal),
            atualizadoEm: Value(DateTime.now()),
          ));
        }
        final consumia = antes == 'tomou';
        final consome = status == 'tomou';
        if (consome && !consumia) await _mexerEstoque(m.id, -m.quantidade);
        if (!consome && consumia) await _mexerEstoque(m.id, m.quantidade);
      });

  /// Dose fora de horario ("somente quando necessario" ou extra): registra como tomada agora.
  Future<void> registrarDoseAvulsa(Medicamento m, {DateTime? agora}) {
    final a = agora ?? DateTime.now();
    final previsto = DateTime(a.year, a.month, a.day, a.hour, a.minute, a.second);
    return registrarTomada(m, previsto, real: previsto);
  }

  Future<void> excluirMedicamento(String id) =>
      (update(medicamentos)..where((t) => t.id.equals(id))).write(
        MedicamentosCompanion(
          excluidoEm: Value(DateTime.now()),
          atualizadoEm: Value(DateTime.now()),
        ),
      );

  // ----------------------- Consultas, exames e retornos -----------------------

  Stream<List<AgendamentoSaude>> observarAgendamentos() => (select(agendamentosSaude)
        ..where((a) => a.excluidoEm.isNull())
        ..orderBy([(a) => OrderingTerm.asc(a.dataHora)]))
      .watch();

  Future<List<AgendamentoSaude>> listarAgendamentos() => (select(agendamentosSaude)
        ..where((a) => a.excluidoEm.isNull())
        ..orderBy([(a) => OrderingTerm.asc(a.dataHora)]))
      .get();

  Future<AgendamentoSaude?> agendamentoPorId(String id) =>
      (select(agendamentosSaude)..where((a) => a.id.equals(id) & a.excluidoEm.isNull())).getSingleOrNull();

  /// Cria um agendamento ou, com [repeticaoUnidade] e [vezes] >= 2, uma serie periodica
  /// (uma linha por data, como nos lancamentos fixos). Cada data tambem vira compromisso na Agenda.
  Future<List<AgendamentoSaude>> criarAgendamentos({
    required String tipo,
    required String titulo,
    String? profissional,
    String? especialidade,
    String? local,
    required DateTime dataHora,
    String? preparo,
    String? observacao,
    int? lembreteMin,
    String? repeticaoUnidade,
    int repeticaoIntervalo = 1,
    int vezes = 1,
  }) async {
    final serie = repeticaoUnidade != null && vezes >= 2;
    final datas = serie
        ? ocorrenciasAgendamento(dataHora, repeticaoUnidade, repeticaoIntervalo, vezes)
        : [dataHora];
    final grupo = serie ? _uuid.v4() : null;
    final ids = <String>[];
    await transaction(() async {
      for (var i = 0; i < datas.length; i++) {
        final eventoId = await inserirEvento(titulo: tituloEventoSaude(tipo, titulo), inicio: datas[i], tipo: 'saude');
        final id = _uuid.v4();
        ids.add(id);
        await into(agendamentosSaude).insert(AgendamentosSaudeCompanion.insert(
          id: Value(id),
          tipo: tipo,
          titulo: titulo,
          dataHora: datas[i],
          profissional: Value(profissional),
          especialidade: Value(especialidade),
          local: Value(local),
          preparo: Value(preparo),
          observacao: Value(observacao),
          lembreteMin: Value(lembreteMin),
          eventoId: Value(eventoId),
          grupoSerie: Value(grupo),
          serieNumero: Value(serie ? i + 1 : null),
          serieTotal: Value(serie ? datas.length : null),
          repeticao: Value(serie ? '$repeticaoUnidade:$repeticaoIntervalo' : null),
        ));
      }
    });
    return (select(agendamentosSaude)
          ..where((a) => a.id.isIn(ids))
          ..orderBy([(a) => OrderingTerm.asc(a.dataHora)]))
        .get();
  }

  Future<List<AgendamentoSaude>> _seguintes(AgendamentoSaude a) async {
    if (a.grupoSerie == null || a.serieNumero == null) return const [];
    return (select(agendamentosSaude)
          ..where((x) =>
              x.grupoSerie.equals(a.grupoSerie!) & x.serieNumero.isBiggerThanValue(a.serieNumero!) & x.excluidoEm.isNull())
          ..orderBy([(x) => OrderingTerm.asc(x.serieNumero)]))
        .get();
  }

  Future<int> contarSeguintesAgendamento(AgendamentoSaude a) async => (await _seguintes(a)).length;

  Future<void> _atualizarEvento(String? eventoId, {String? titulo, DateTime? inicio, String? local, bool? excluido}) async {
    if (eventoId == null) return;
    await (update(eventos)..where((e) => e.id.equals(eventoId))).write(EventosCompanion(
      titulo: titulo == null ? const Value.absent() : Value(titulo),
      inicio: inicio == null ? const Value.absent() : Value(inicio),
      local: local == null ? const Value.absent() : Value(local),
      excluidoEm: excluido == null ? const Value.absent() : Value(excluido ? DateTime.now() : null),
      atualizadoEm: Value(DateTime.now()),
    ));
  }

  /// Edita o agendamento. Com [aplicarNosSeguintes], os demais dados (menos a data) passam
  /// tambem aos agendamentos posteriores da serie. Devolve os agendamentos alterados (para refazer lembretes).
  Future<List<AgendamentoSaude>> atualizarAgendamento(
    AgendamentoSaude original, {
    required String tipo,
    required String titulo,
    String? profissional,
    String? especialidade,
    String? local,
    required DateTime dataHora,
    String? preparo,
    String? observacao,
    int? lembreteMin,
    bool aplicarNosSeguintes = false,
  }) async {
    final alvos = [original, if (aplicarNosSeguintes) ...await _seguintes(original)];
    await transaction(() async {
      for (final a in alvos) {
        final esta = a.id == original.id;
        await (update(agendamentosSaude)..where((t) => t.id.equals(a.id))).write(AgendamentosSaudeCompanion(
          tipo: Value(tipo),
          titulo: Value(titulo),
          profissional: Value(profissional),
          especialidade: Value(especialidade),
          local: Value(local),
          preparo: Value(preparo),
          observacao: Value(observacao),
          lembreteMin: Value(lembreteMin),
          dataHora: esta ? Value(dataHora) : const Value.absent(),
          atualizadoEm: Value(DateTime.now()),
        ));
        await _atualizarEvento(a.eventoId,
            titulo: tituloEventoSaude(tipo, titulo), inicio: esta ? dataHora : null, local: local ?? '');
      }
    });
    return (select(agendamentosSaude)..where((t) => t.id.isIn(alvos.map((a) => a.id).toList()))).get();
  }

  /// Muda a situacao (agendado, realizado, cancelado, faltou). Cancelado/faltou tiram o
  /// compromisso da Agenda; voltar para agendado o recoloca.
  Future<void> definirStatusAgendamento(AgendamentoSaude a, String status, {String? resultado}) async {
    await (update(agendamentosSaude)..where((t) => t.id.equals(a.id))).write(AgendamentosSaudeCompanion(
      status: Value(status),
      resultado: resultado == null ? const Value.absent() : Value(resultado.isEmpty ? null : resultado),
      atualizadoEm: Value(DateTime.now()),
    ));
    await _atualizarEvento(a.eventoId, excluido: status == 'cancelado' || status == 'faltou');
  }

  /// Exclui (logicamente) o agendamento e seu compromisso na Agenda; [seguintes] inclui o resto da serie.
  /// Devolve os excluidos (para cancelar lembretes).
  Future<List<AgendamentoSaude>> excluirAgendamento(AgendamentoSaude a, {bool seguintes = false}) async {
    final alvos = [a, if (seguintes) ...await _seguintes(a)];
    await transaction(() async {
      for (final x in alvos) {
        await (update(agendamentosSaude)..where((t) => t.id.equals(x.id))).write(AgendamentosSaudeCompanion(
          excluidoEm: Value(DateTime.now()),
          atualizadoEm: Value(DateTime.now()),
        ));
        await _atualizarEvento(x.eventoId, excluido: true);
      }
    });
    return alvos;
  }
}

/// Nome de arquivo seguro para o id do usuario (so letras, numeros e _).
String nomeSeguro(String? usuarioId) =>
    (usuarioId == null || usuarioId.isEmpty) ? 'sem_login' : usuarioId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

/// Banco local do usuario logado; troca sozinho (e fecha o anterior) quando outro usuario entra.
final bancoProvider = Provider<Banco>((ref) {
  final id = ref.watch(sessaoProvider.select((s) => s.usuario?.id));
  final banco = Banco(usuarioId: id);
  ref.onDispose(banco.close);
  return banco;
});
