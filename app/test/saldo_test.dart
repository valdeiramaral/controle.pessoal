import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controle_pessoal/core/calculos.dart';
import 'package:controle_pessoal/data/local/banco.dart';

void main() {
  late Banco banco;

  setUp(() => banco = Banco.paraTeste(NativeDatabase.memory()));
  tearDown(() => banco.close());

  Future<int> saldo() async => calcularSaldoCentavos(
        await banco.select(banco.contas).get(),
        await banco.select(banco.lancamentos).get(),
      );

  test('sem lancamentos o saldo e o saldo inicial das contas', () async {
    expect(await saldo(), 0);
    await (banco.update(banco.contas)
          ..where((c) => c.id.equals(contaPadraoId)))
        .write(const ContasCompanion(saldoInicialCentavos: Value(50000)));
    expect(await saldo(), 50000);
  });

  test('receita soma e despesa subtrai, so os pagos', () async {
    await banco.inserirLancamento(
        descricao: 'Salario', valorCentavos: 300000, tipo: 'receita', pago: true);
    await banco.inserirLancamento(
        descricao: 'Mercado', valorCentavos: 12550, tipo: 'despesa', pago: true);
    await banco.inserirLancamento(
        descricao: 'Aluguel', valorCentavos: 100000, tipo: 'despesa', pago: false);
    expect(await saldo(), 300000 - 12550);
  });

  test('transferencia nao altera o saldo total', () async {
    await banco.inserirLancamento(
        descricao: 'Para poupanca', valorCentavos: 20000, tipo: 'transferencia', pago: true);
    expect(await saldo(), 0);
  });

  test('lancamento excluido logicamente nao entra no saldo', () async {
    await banco.inserirLancamento(
        descricao: 'Erro', valorCentavos: 9900, tipo: 'despesa', pago: true);
    final l = (await banco.select(banco.lancamentos).get()).single;
    expect(await saldo(), -9900);
    await banco.excluirLancamento(l.id);
    expect(await saldo(), 0);
  });
}
