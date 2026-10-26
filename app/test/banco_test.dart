import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controle_pessoal/data/local/banco.dart';

void main() {
  late Banco banco;

  setUp(() => banco = Banco.paraTeste(NativeDatabase.memory()));
  tearDown(() => banco.close());

  test('cria a conta padrao na primeira abertura', () async {
    final contas = await banco.select(banco.contas).get();
    expect(contas.single.id, contaPadraoId);
  });

  test('lancamento excluido some da lista (exclusao logica)', () async {
    await banco.inserirLancamento(
        descricao: 'Mercado', valorCentavos: 12550, tipo: 'despesa');
    var lista = await banco.observarLancamentos().first;
    expect(lista, hasLength(1));

    await banco.excluirLancamento(lista.single.id);
    lista = await banco.observarLancamentos().first;
    expect(lista, isEmpty);

    // Continua gravado, marcado como excluido (necessario para sincronizar).
    final todos = await banco.select(banco.lancamentos).get();
    expect(todos.single.excluidoEm, isNotNull);
  });
}
