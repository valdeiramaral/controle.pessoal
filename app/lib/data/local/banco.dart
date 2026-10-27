import '../../features/auth/sessao.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'tabelas.dart';

part 'banco.g.dart';

/// Conta criada automaticamente na primeira abertura do app.
const contaPadraoId = 'conta-padrao';

@DriftDatabase(tables: [
  Usuarios,
  Contas,
  Categorias,
  Eventos,
  Tarefas,
  Lancamentos,
  Orcamentos,
  Metas,
  Consultas,
  Medicamentos,
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
  int get schemaVersion => 2;

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

  Future<void> inserirLancamento({
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
  }) =>
      into(lancamentos).insert(LancamentosCompanion.insert(
        contaId: contaId ?? contaPadraoId,
        categoriaId: Value(categoriaId),
        descricao: descricao,
        valorCentavos: valorCentavos,
        dia: dia ?? DateTime.now(),
        tipo: tipo,
        status: Value(pago ? 'pago' : 'pendente'),
        recorrencia: Value(recorrencia),
        parcelaNumero: Value(parcelaNumero),
        parcelaTotal: Value(parcelaTotal),
        grupoParcelas: Value(grupoParcelas),
      ));

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
        dia: DateTime(primeiroDia.year, primeiroDia.month + i, primeiroDia.day),
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

  Future<void> alternarPagamento(Lancamento l) =>
      (update(lancamentos)..where((t) => t.id.equals(l.id))).write(
        LancamentosCompanion(
          status: Value(l.status == 'pago' ? 'pendente' : 'pago'),
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

  /// [horarios] no formato "08:00,20:00". Retorna o id do medicamento.
  Future<String> inserirMedicamento({
    required String nome,
    required String dose,
    required String horarios,
  }) async {
    final id = _uuid.v4();
    await into(medicamentos).insert(MedicamentosCompanion.insert(
      id: Value(id),
      nome: nome,
      dose: dose,
      horarios: horarios,
      inicio: DateTime.now(),
    ));
    return id;
  }

  Future<void> excluirMedicamento(String id) =>
      (update(medicamentos)..where((t) => t.id.equals(id))).write(
        MedicamentosCompanion(
          excluidoEm: Value(DateTime.now()),
          atualizadoEm: Value(DateTime.now()),
        ),
      );
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
