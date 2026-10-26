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
  int get schemaVersion => 1;

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
  }) =>
      into(lancamentos).insert(LancamentosCompanion.insert(
        contaId: contaPadraoId,
        descricao: descricao,
        valorCentavos: valorCentavos,
        dia: dia ?? DateTime.now(),
        tipo: tipo,
        status: Value(pago ? 'pago' : 'pendente'),
      ));

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
