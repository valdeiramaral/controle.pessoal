import 'package:controle_pessoal/core/bancos.dart';
import 'package:controle_pessoal/core/calculos.dart';
import 'package:controle_pessoal/core/conta_validacao.dart';
import 'package:controle_pessoal/core/documentos.dart';
import 'package:controle_pessoal/core/formatos.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/financas/conta_detalhe_page.dart';
import 'package:controle_pessoal/features/financas/contas_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'util_testes.dart';

Widget app(Banco banco, Widget corpo) => ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco)],
      child: MaterialApp(theme: temaApp(), home: Scaffold(body: corpo)),
    );

void main() {
  late Banco banco;
  setUp(() => banco = Banco.paraTeste(NativeDatabase.memory()));
  tearDown(() => banco.close());

  group('validacoes', () {
    test('CNPJ', () {
      expect(cnpjValido('11.222.333/0001-81'), isTrue);
      expect(cnpjValido('11.222.333/0001-82'), isFalse);
      expect(cnpjValido('11111111111111'), isFalse);
      expect(cpfOuCnpjValido('529.982.247-25'), isTrue);
      expect(cpfOuCnpjValido('123'), isFalse);
    });

    test('mascara CPF ou CNPJ conforme a quantidade de digitos', () {
      expect(formatarCpfOuCnpj('52998224725'), '529.982.247-25');
      expect(formatarCpfOuCnpj('11222333000181'), '11.222.333/0001-81');
    });

    test('agencia e numero da conta', () {
      expect(validarAgencia('4544'), isNull);
      expect(validarAgencia('1234-5'), isNull);
      expect(validarAgencia(''), isNotNull);
      expect(validarAgencia('12a'), isNotNull);
      expect(validarNumeroConta('18882982'), isNull);
      expect(validarNumeroConta('123456-7'), isNull);
      expect(validarNumeroConta('1234567890123'), isNotNull);
    });

    test('documento e chave PIX sao opcionais, mas precisam ser validos quando preenchidos', () {
      expect(validarDocumentoOpcional(''), isNull);
      expect(validarDocumentoOpcional('877.877.777-78'), isNotNull);
      expect(validarDocumentoOpcional('529.982.247-25'), isNull);
      expect(validarChavePixOpcional(''), isNull);
      expect(validarChavePixOpcional('fulano@exemplo.com'), isNull);
      expect(validarChavePixOpcional('529.982.247-25'), isNull);
      expect(validarChavePixOpcional('+5511987654321'), isNull);
      expect(validarChavePixOpcional('123e4567-e89b-12d3-a456-426614174000'), isNull);
      expect(validarChavePixOpcional('qualquer coisa'), isNotNull);
    });

    test('catalogo de bancos', () {
      expect(bancoPorCodigo('341').nome, 'Itaú');
      expect(bancoPorCodigo('999').nome, 'Outro banco');
      expect(bancoPorCodigo(null).codigo, codigoOutroBanco);
      expect(catalogoBancos.map((b) => b.codigo).toSet().length, catalogoBancos.length);
      expect(catalogoBancos.length, greaterThan(400)); // lista completa Febraban + Outro banco
      expect(bancoPorCodigo('070').nome, isNot('Outro banco')); // BRB
    });
  });

  group('banco local', () {
    test('cria, le e atualiza uma conta bancaria', () async {
      final id = await banco.inserirConta(
        nome: 'Principal',
        banco: '341',
        agencia: '6252',
        numeroConta: '7362616',
        documento: '52998224725',
        chavePix: 'a@b.com',
        apelido: 'Principal',
        saldoInicialCentavos: 97844,
      );
      var c = (await banco.select(banco.contas).get()).firstWhere((x) => x.id == id);
      expect([c.banco, c.agencia, c.numeroConta, c.titularidade], ['341', '6252', '7362616', 'propria']);
      await banco.atualizarConta(id,
          nome: 'Reserva', tipo: 'poupanca', saldoInicialCentavos: 100, titularidade: 'propria', banco: '237', agencia: '1', numeroConta: '2');
      c = (await banco.select(banco.contas).get()).firstWhere((x) => x.id == id);
      expect([c.nome, c.tipo, c.banco, c.chavePix], ['Reserva', 'poupanca', '237', null]);
    });

    test('detecta conta duplicada (mesmo banco, agencia e numero), ignorando a propria', () async {
      final id = await banco.inserirConta(nome: 'A', banco: '341', agencia: '1', numeroConta: '2');
      expect(await banco.existeContaBancaria(banco: '341', agencia: '1', numeroConta: '2'), isTrue);
      expect(await banco.existeContaBancaria(banco: '341', agencia: '1', numeroConta: '2', ignorarId: id), isFalse);
      expect(await banco.existeContaBancaria(banco: '237', agencia: '1', numeroConta: '2'), isFalse);
    });

    test('excluir: conta padrao e conta com lancamentos sao recusadas; vazia e excluida (logicamente)', () async {
      expect(await banco.excluirConta(contaPadraoId), contains('padrão'));
      final comLanc = await banco.inserirConta(nome: 'Com lançamento', banco: '341', agencia: '1', numeroConta: '3');
      await banco.inserirLancamento(descricao: 'x', valorCentavos: 100, tipo: 'despesa', contaId: comLanc);
      expect(await banco.excluirConta(comLanc), contains('1 lançamento'));
      final vazia = await banco.inserirConta(nome: 'Vazia', banco: '341', agencia: '1', numeroConta: '4');
      expect(await banco.excluirConta(vazia), isNull);
      final todas = await banco.select(banco.contas).get();
      expect(todas.firstWhere((c) => c.id == vazia).excluidoEm, isNotNull); // continua gravada
      expect((await banco.observarContas().first).any((c) => c.id == vazia), isFalse);
    });

    test('saldo por conta e conta externa fora do saldo total', () async {
      final propria = await banco.inserirConta(nome: 'Minha', banco: '341', agencia: '1', numeroConta: '5', saldoInicialCentavos: 10000);
      await banco.inserirConta(
          nome: 'Do pai', banco: '104', agencia: '2', numeroConta: '6', titularidade: 'externa', saldoInicialCentavos: 999999);
      await banco.inserirLancamento(descricao: 'r', valorCentavos: 5000, tipo: 'receita', pago: true, contaId: propria);
      await banco.inserirLancamento(descricao: 'd', valorCentavos: 2000, tipo: 'despesa', pago: true, contaId: propria);
      await banco.inserirLancamento(descricao: 'p', valorCentavos: 9000, tipo: 'despesa', pago: false, contaId: propria);
      final contas = await banco.select(banco.contas).get();
      final ls = await banco.select(banco.lancamentos).get();
      expect(calcularSaldoDaContaCentavos(contas.firstWhere((c) => c.id == propria), ls), 13000);
      expect(calcularSaldoCentavos(contas, ls), 13000); // sem os 9.999,99 da conta externa
    });
  });

  group('telas', () {
    testWidgets('lista separa Minhas contas e Contas externas e mostra saldo so nas proprias', (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final minha = await banco.inserirConta(
          nome: 'Itaú', banco: '341', agencia: '6252', numeroConta: '7362616', saldoInicialCentavos: 97844);
      final externa = await banco.inserirConta(
          nome: 'Caixa', banco: '104', agencia: '222', numeroConta: '6768866', titularidade: 'externa');

      await tester.pumpWidget(app(banco, const ContasPage()));
      await tester.pumpAndSettle();

      expect(find.text('Minhas contas'), findsOneWidget);
      expect(find.text('Contas externas'), findsOneWidget);
      expect(find.byKey(const Key('botao_adicionar_conta')), findsOneWidget);
      expect(
          find.descendant(of: find.byKey(const Key('secao_proprias')), matching: find.byKey(Key('conta_$minha'))), findsOneWidget);
      expect(
          find.descendant(of: find.byKey(const Key('secao_externas')), matching: find.byKey(Key('conta_$externa'))), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(Key('saldo_$minha'))).data, formatarCentavos(97844));
      expect(find.byKey(Key('saldo_$externa')), findsNothing);
      expect(tester.takeException(), isNull);
      await encerrar(tester);
    });

    testWidgets('formulario cria conta (valida campos e impede duplicada)', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(banco, const ContasPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('botao_adicionar_conta')));
      await tester.pumpAndSettle();

      // Vazio: erros de campo obrigatorio e nada e gravado.
      await tester.tap(find.byKey(const Key('botao_salvar_conta')));
      await tester.pumpAndSettle();
      expect(find.text('Informe se a conta é sua'), findsWidgets);
      expect(find.text('Escolha o banco'), findsWidgets); // dica + mensagem de erro
      expect(find.text('Informe a agência'), findsOneWidget);
      expect(find.text('Informe o número da conta'), findsOneWidget);

      Future<void> preencher() async {
        await tester.tap(find.byKey(const Key('campo_titularidade')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sim, a conta é minha').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('campo_banco')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('341 · Itaú').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('campo_agencia')), '4544');
        await tester.enterText(find.byKey(const Key('campo_numero')), '18882982');
        await tester.enterText(find.byKey(const Key('campo_documento')), '52998224725');
        await tester.enterText(find.byKey(const Key('campo_pix')), 'fulano@exemplo.com');
        await tester.enterText(find.byKey(const Key('campo_apelido')), 'Salário');
        await tester.enterText(find.byKey(const Key('campo_saldo')), '978,44');
      }

      await preencher();
      await tester.tap(find.byKey(const Key('botao_salvar_conta')));
      await tester.pumpAndSettle();

      final contas = await banco.select(banco.contas).get();
      final c = contas.firstWhere((x) => x.banco == '341');
      expect([c.nome, c.agencia, c.numeroConta, c.documento, c.chavePix, c.saldoInicialCentavos, c.titularidade],
          ['Salário', '4544', '18882982', '52998224725', 'fulano@exemplo.com', 97844, 'propria']);
      expect(find.byKey(Key('conta_${c.id}')), findsOneWidget); // voltou para a lista

      // Mesma conta de novo: recusada.
      await tester.tap(find.byKey(const Key('botao_adicionar_conta')));
      await tester.pumpAndSettle();
      await preencher();
      await tester.tap(find.byKey(const Key('botao_salvar_conta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('erro_conta')), findsOneWidget);
      expect((await banco.select(banco.contas).get()).where((x) => x.banco == '341').length, 1);
      expect(tester.takeException(), isNull);
      await encerrar(tester);
    });

    testWidgets('banco: busca na lista Febraban e cadastra banco que nao consta', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(banco, const ContasPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('botao_adicionar_conta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('campo_titularidade')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sim, a conta é minha').last);
      await tester.pumpAndSettle();

      // Busca por codigo acha um banco fora dos destaques (070 = BRB).
      await tester.tap(find.byKey(const Key('campo_banco')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('busca_banco')), '070');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('banco_070')), findsOneWidget);
      expect(find.byKey(const Key('banco_341')), findsNothing);

      // Banco fora da lista: pede o nome do banco.
      await tester.enterText(find.byKey(const Key('busca_banco')), 'zzzz');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('banco_000')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('campo_nome_banco')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('campo_nome_banco')), 'Banco do Vilarejo');
      await tester.enterText(find.byKey(const Key('campo_agencia')), '12');
      await tester.enterText(find.byKey(const Key('campo_numero')), '99887');
      await tester.tap(find.byKey(const Key('botao_salvar_conta')));
      await tester.pumpAndSettle();

      final c = (await banco.select(banco.contas).get()).firstWhere((x) => x.banco == codigoOutroBanco);
      expect(c.nome, 'Banco do Vilarejo');
      expect(tituloDaConta(c), 'Banco do Vilarejo');
      expect(tester.takeException(), isNull);
      await encerrar(tester);
    });

    testWidgets('gerenciar conta: mostra dados, edita e exclui', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final id = await banco.inserirConta(
          nome: 'Santander', banco: '033', agencia: '4544', numeroConta: '18882982', documento: '52998224725');

      await tester.pumpWidget(app(
        banco,
        Builder(
          builder: (c) => Center(
            child: ElevatedButton(
              key: const Key('abrir'),
              onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => ContaDetalhePage(contaId: id))),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('detalhe_banco'))).data, 'SANTANDER');
      expect(tester.widget<Text>(find.byKey(const Key('detalhe_agencia'))).data, '4544');
      expect(tester.widget<Text>(find.byKey(const Key('detalhe_conta'))).data, '18882982');
      expect(tester.widget<Text>(find.byKey(const Key('detalhe_documento'))).data, '529.982.247-25');
      expect(tester.widget<Text>(find.byKey(const Key('detalhe_pix'))).data, 'Não vinculada');

      await tester.tap(find.byKey(const Key('botao_editar')));
      await tester.pumpAndSettle();
      expect(find.text('Editar conta'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('campo_agencia')), '9999');
      await tester.tap(find.byKey(const Key('botao_salvar_conta')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('detalhe_agencia'))).data, '9999');

      await tester.tap(find.byKey(const Key('botao_excluir_conta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_exclusao')));
      await tester.pumpAndSettle();
      expect((await banco.select(banco.contas).get()).firstWhere((c) => c.id == id).excluidoEm, isNotNull);
      expect(tester.takeException(), isNull);
      await encerrar(tester);
    });
  });
}
