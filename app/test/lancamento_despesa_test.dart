import 'dart:convert';
import 'dart:typed_data';

import 'package:controle_pessoal/core/arquivos.dart';
import 'package:controle_pessoal/core/lancamento_calculo.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/financas/lancamento_detalhe_page.dart';
import 'package:controle_pessoal/features/financas/lancamento_form_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'util_testes.dart';

void main() {
  group('calculos', () {
    test('dividirParcelas soma exatamente o total e poe a sobra nas primeiras', () {
      expect(dividirParcelas(10000, 3), [3334, 3333, 3333]);
      expect(dividirParcelas(10000, 4), [2500, 2500, 2500, 2500]);
      expect(dividirParcelas(1, 3), [1, 0, 0]);
      for (final (total, n) in [(99999, 7), (12345, 12), (100, 120)]) {
        expect(dividirParcelas(total, n).fold<int>(0, (a, b) => a + b), total);
      }
    });

    test('adicionarMeses nao estoura o fim do mes', () {
      expect(adicionarMeses(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(adicionarMeses(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(adicionarMeses(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
      expect(adicionarMeses(DateTime(2026, 12, 10), 12), DateTime(2027, 12, 10));
    });

    test('tags: normaliza, ignora repetidas e limita', () {
      expect(normalizarTag('  #Viagem, ótima '), 'viagem ótima');
      expect(tagsParaTexto(['Viagem', 'viagem', ' ', 'Reembolsável']), 'viagem,reembolsável');
      expect(tagsDoTexto('a,b,,c'), ['a', 'b', 'c']);
      expect(tagsParaTexto([for (var i = 0; i < 15; i++) 't$i']).split(',').length, maximoTags);
    });
  });

  group('banco: lancar', () {
    late Banco banco;
    setUp(() => banco = Banco.paraTeste(NativeDatabase.memory()));
    tearDown(() => banco.close());

    test('despesa unica com observacao, tags e dois anexos', () async {
      final ids = await banco.lancar(
        descricao: 'Aluguel da casa',
        valorCentavos: 150000,
        tipo: 'despesa',
        vencimento: DateTime(2026, 11, 5),
        contaId: contaPadraoId,
        tags: 'casa,fixo',
        observacao: 'Pago por PIX, sem juros',
        anexos: [
          ArquivoParaAnexar(nome: 'recibo.pdf', bytes: Uint8List.fromList([1, 2, 3]), tipoMime: 'application/pdf'),
          ArquivoParaAnexar(nome: 'cupom.png', bytes: Uint8List.fromList([4, 5]), tipoMime: 'image/png'),
        ],
      );
      expect(ids.length, 1);
      final l = (await banco.select(banco.lancamentos).get()).single;
      expect([l.descricao, l.valorCentavos, l.tipo, l.status, l.tags, l.observacao, l.dia],
          ['Aluguel da casa', 150000, 'despesa', 'pendente', 'casa,fixo', 'Pago por PIX, sem juros', DateTime(2026, 11, 5)]);
      final anexos = await banco.observarAnexos(l.id).first;
      expect(anexos.map((a) => a.nomeArquivo), ['recibo.pdf', 'cupom.png']);
      expect(anexos.map((a) => a.tamanhoBytes), [3, 2]);
      expect((await banco.observarContagemAnexos().first)[l.id], 2);
    });

    test('parcelada: valor total dividido, vencimento mensal, anexo so na primeira', () async {
      final ids = await banco.lancar(
        descricao: 'Geladeira',
        valorCentavos: 100000,
        tipo: 'despesa',
        vencimento: DateTime(2026, 11, 30),
        contaId: contaPadraoId,
        repeticao: 'parcelada',
        vezes: 3,
        anexos: [ArquivoParaAnexar(nome: 'nota.pdf', bytes: Uint8List.fromList([1]))],
      );
      final ls = (await banco.select(banco.lancamentos).get())..sort((a, b) => a.parcelaNumero!.compareTo(b.parcelaNumero!));
      expect(ls.map((l) => l.valorCentavos), [33334, 33333, 33333]);
      expect(ls.fold<int>(0, (s, l) => s + l.valorCentavos), 100000);
      expect(ls.map((l) => l.dia), [DateTime(2026, 11, 30), DateTime(2026, 12, 30), DateTime(2027, 1, 30)]);
      expect(ls.map((l) => l.descricao).first, 'Geladeira (1/3)');
      expect(ls.every((l) => l.parcelaTotal == 3 && l.status == 'pendente' && l.grupoParcelas == ls.first.grupoParcelas), isTrue);
      expect((await banco.select(banco.anexos).get()).single.lancamentoId, ids.first);
    });

    test('fixa: um lancamento por mes com recorrencia mensal', () async {
      await banco.lancar(
          descricao: 'Internet',
          valorCentavos: 9990,
          tipo: 'despesa',
          vencimento: DateTime(2026, 1, 31),
          contaId: contaPadraoId,
          repeticao: 'fixa',
          vezes: 4);
      final ls = (await banco.select(banco.lancamentos).get())..sort((a, b) => a.dia.compareTo(b.dia));
      expect(ls.length, 4);
      expect(ls.every((l) => l.recorrencia == 'FREQ=MONTHLY' && l.valorCentavos == 9990 && l.parcelaTotal == null), isTrue);
      expect(ls.map((l) => l.dia.month), [1, 2, 3, 4]);
      expect(ls[1].dia, DateTime(2026, 2, 28));
    });
    test('editar: so este, ou tambem a conta/categoria/tags dos seguintes; anexos entram e saem', () async {
      final cat = await banco.inserirCategoria(nome: 'Casa');
      final ids = await banco.lancar(
          descricao: 'Internet',
          valorCentavos: 10000,
          tipo: 'despesa',
          vencimento: DateTime(2026, 1, 10),
          contaId: contaPadraoId,
          repeticao: 'fixa',
          vezes: 3,
          anexos: [ArquivoParaAnexar(nome: 'a.pdf', bytes: Uint8List.fromList([1]))]);
      final primeiro = (await banco.lancamentoPorId(ids.first))!;
      expect(await banco.contarSeguintesDaSerie(primeiro), 2);
      final antigo = (await banco.observarAnexos(primeiro.id).first).single;
      await banco.atualizarLancamento(primeiro,
          descricao: 'Internet fibra',
          valorCentavos: 12000,
          dia: DateTime(2026, 1, 12),
          contaId: contaPadraoId,
          categoriaId: cat,
          tags: 'casa',
          observacao: 'Plano novo',
          pago: true,
          aplicarNosSeguintes: true,
          novosAnexos: [ArquivoParaAnexar(nome: 'b.png', bytes: Uint8List.fromList([2, 3]), tipoMime: 'image/png')],
          anexosRemovidos: [antigo.id]);
      final ls = (await banco.select(banco.lancamentos).get())..sort((a, b) => a.dia.compareTo(b.dia));
      expect([ls[0].descricao, ls[0].valorCentavos, ls[0].status, ls[0].dia], ['Internet fibra', 12000, 'pago', DateTime(2026, 1, 12)]);
      // Os seguintes herdam categoria, tags e observacao, mas nao valor/descricao/situacao.
      for (final s in ls.skip(1)) {
        expect([s.categoriaId, s.tags, s.observacao, s.descricao, s.valorCentavos, s.status], [cat, 'casa', 'Plano novo', 'Internet', 10000, 'pendente']);
      }
      expect((await banco.observarAnexos(primeiro.id).first).map((a) => a.nomeArquivo), ['b.png']);
      expect(await banco.conteudoDoAnexo(antigo.id), isNotNull); // exclusao logica: o registro continua
    });

    test('excluir: so este, ou este e os seguintes (com os anexos)', () async {
      final ids = await banco.lancar(
          descricao: 'Plano',
          valorCentavos: 5000,
          tipo: 'despesa',
          vencimento: DateTime(2026, 3, 1),
          contaId: contaPadraoId,
          repeticao: 'fixa',
          vezes: 4,
          anexos: [ArquivoParaAnexar(nome: 'x.pdf', bytes: Uint8List.fromList([1]))]);
      final todos = (await banco.select(banco.lancamentos).get())..sort((a, b) => a.dia.compareTo(b.dia));
      expect(await banco.excluirLancamentoDaSerie(todos[2], seguintes: true), 2); // 3o e 4o
      var ativos = (await banco.observarLancamentos().first);
      expect(ativos.length, 2);
      expect(await banco.excluirLancamentoDaSerie(todos[0]), 1);
      ativos = await banco.observarLancamentos().first;
      expect(ativos.map((l) => l.id), [todos[1].id]);
      expect(await banco.observarAnexos(ids.first).first, isEmpty); // anexo saiu junto
    });
  });

  group('tela', () {
    testWidgets('lanca despesa parcelada com categoria nova, observacao, tags e anexo', (tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = Banco.paraTeste(NativeDatabase.memory());
      addTearDown(banco.close);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          bancoProvider.overrideWithValue(banco),
          escolhedorArquivosProvider.overrideWithValue(() async => [
                ArquivoParaAnexar(nome: 'comprovante.pdf', bytes: Uint8List.fromList(List.filled(2048, 1)), tipoMime: 'application/pdf'),
              ]),
        ],
        child: MaterialApp(theme: temaApp(), home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => abrirFormularioLancamento(c, hoje: DateTime(2026, 10, 27)), child: const Text('abrir'))))),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Nova despesa'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('texto_data'))).data, '27/10/2026');

      // Vazio: mostra os erros e nao grava.
      await tester.tap(find.byKey(const Key('botao_salvar_lancamento')));
      await tester.pumpAndSettle();
      expect(find.text('Informe a descrição'), findsOneWidget);
      expect(find.text('Informe o valor'), findsOneWidget);
      expect(await banco.select(banco.lancamentos).get(), isEmpty);

      await tester.enterText(find.byKey(const Key('campo_descricao')), 'Geladeira');
      await tester.enterText(find.byKey(const Key('campo_valor')), '1000,00');
      await tester.pump();

      // Categoria nova direto do formulario.
      await tester.tap(find.byKey(const Key('campo_categoria')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Nova categoria…').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_nova_categoria')), 'Casa');
      await tester.tap(find.byKey(const Key('confirmar_categoria')));
      await tester.pumpAndSettle();

      // Repetir: parcelada em 3x -> previa 333,34 / 333,33.
      await tester.tap(find.byKey(const Key('campo_repetir')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parcelada').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_vezes')), '3');
      await tester.pump();
      expect(find.byKey(const Key('previa_parcelas')), findsOneWidget);
      expect(find.text('Valor total (R\$)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('campo_observacao')), 'Juros de 2%');
      await tocarRolando(tester, find.byKey(const Key('botao_anexar')));
      await tester.pumpAndSettle();
      expect(find.text('comprovante.pdf'), findsOneWidget);

      await tocarRolando(tester, find.byKey(const Key('campo_tags')));
      await tester.enterText(find.byKey(const Key('campo_tags')), 'Cozinha, eletro');
      await tester.tap(find.byKey(const Key('botao_add_tag')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tag_cozinha')), findsOneWidget);
      expect(find.byKey(const Key('tag_eletro')), findsOneWidget);

      await tocarRolando(tester, find.byKey(const Key('botao_salvar_lancamento')));
      await tester.pumpAndSettle();

      final ls = (await banco.select(banco.lancamentos).get())..sort((a, b) => a.parcelaNumero!.compareTo(b.parcelaNumero!));
      expect(ls.map((l) => l.valorCentavos), [33334, 33333, 33333]);
      expect(ls.first.tags, 'cozinha,eletro');
      expect(ls.first.observacao, 'Juros de 2%');
      expect(ls.first.categoriaId, isNotNull);
      expect(ls.first.dia, DateTime(2026, 10, 27));
      expect(ls.first.contaId, contaPadraoId);
      expect((await banco.select(banco.anexos).get()).single.nomeArquivo, 'comprovante.pdf');
      expect(find.text('Nova despesa'), findsNothing); // fechou
      expect(tester.takeException(), isNull);
      await encerrar(tester);
    });

    testWidgets('detalhe: abre anexos, edita (remove anexo, muda valor) e exclui', (tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = Banco.paraTeste(NativeDatabase.memory());
      addTearDown(banco.close);
      final baixados = <String>[];
      // PNG 1x1 valido.
      final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
      final ids = await banco.lancar(
        descricao: 'Energia',
        valorCentavos: 23050,
        tipo: 'despesa',
        vencimento: DateTime(2026, 11, 10),
        contaId: contaPadraoId,
        tags: 'casa,luz',
        observacao: 'Conta de outubro',
        anexos: [
          ArquivoParaAnexar(nome: 'fatura.pdf', bytes: Uint8List.fromList([1, 2, 3]), tipoMime: 'application/pdf'),
          ArquivoParaAnexar(nome: 'foto.png', bytes: png, tipoMime: 'image/png'),
        ],
      );
      final anexos = await banco.observarAnexos(ids.first).first;
      final pdf = anexos.firstWhere((a) => a.nomeArquivo == 'fatura.pdf');
      final img = anexos.firstWhere((a) => a.nomeArquivo == 'foto.png');

      await tester.pumpWidget(ProviderScope(
        overrides: [
          bancoProvider.overrideWithValue(banco),
          baixadorArquivosProvider.overrideWithValue((nome, bytes, mime) async => baixados.add(nome)),
        ],
        child: MaterialApp(theme: temaApp(), home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => abrirDetalheLancamento(c, ids.first), child: const Text('abrir'))))),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('detalhe_descricao'))).data, 'Energia');
      expect(find.byKey(const Key('detalhe_observacao')), findsOneWidget);
      expect(find.byKey(const Key('detalhe_tag_luz')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('detalhe_data'))).data, '10/11/2026');

      // PDF: baixa direto. Imagem: abre a previa e baixa pelo botao.
      await tester.tap(find.byKey(Key('anexo_${pdf.id}')));
      await tester.pumpAndSettle();
      expect(baixados, ['fatura.pdf']);
      await tester.tap(find.byKey(Key('anexo_${img.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('previa_imagem')), findsOneWidget);
      await tester.tap(find.byKey(const Key('baixar_anexo_dialogo')));
      await tester.pumpAndSettle();
      expect(baixados, ['fatura.pdf', 'foto.png']);
      await tester.tap(find.byKey(const Key('fechar_anexo')));
      await tester.pumpAndSettle();

      // Editar: novo valor, tira o PDF, marca como paga.
      await tester.tap(find.byKey(const Key('botao_editar_lancamento')));
      await tester.pumpAndSettle();
      expect(find.text('Editar despesa'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byKey(const Key('campo_valor'))).controller!.text, '230,50');
      await tester.enterText(find.byKey(const Key('campo_valor')), '250,00');
      await tester.tap(find.byKey(Key('remover_anexo_existente_${pdf.id}')));
      await tester.pump();
      await tocarRolando(tester, find.byKey(const Key('campo_pago'))); // marca como paga
      await tester.pump();
      await tocarRolando(tester, find.byKey(const Key('botao_salvar_lancamento')));
      await tester.pumpAndSettle();

      final l = (await banco.lancamentoPorId(ids.first))!;
      expect([l.valorCentavos, l.status], [25000, 'pago']);
      expect((await banco.observarAnexos(ids.first).first).map((a) => a.nomeArquivo), ['foto.png']);
      expect(tester.widget<Text>(find.byKey(const Key('detalhe_valor'))).data!.contains('250,00'), isTrue);

      // Excluir (sem serie): confirma e volta.
      await tester.tap(find.byKey(const Key('botao_excluir_lancamento')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_exclusao_lancamento')));
      await tester.pumpAndSettle();
      expect(await banco.observarLancamentos().first, isEmpty);
      expect(find.byKey(const Key('detalhe_descricao')), findsNothing);
      expect(tester.takeException(), isNull);
      await encerrar(tester);
    });
  });
}
