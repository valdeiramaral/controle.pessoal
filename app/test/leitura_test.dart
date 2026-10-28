import 'dart:typed_data';

import 'package:controle_pessoal/core/arquivos.dart';
import 'package:controle_pessoal/core/leitura_calculo.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/leitura/leitura_form_page.dart';
import 'package:controle_pessoal/features/leitura/leitura_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'util_testes.dart';

// PNG 1x1 valido.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
]);

void main() {
  test('regras: nota por toque e situacao da leitura', () {
    expect(novaNota(0, 3), 3);
    expect(novaNota(3, 3), 0);
    expect(novaNota(2, 5), 5);
    expect(situacaoDaLeitura(null, null), 'Não iniciado');
    expect(situacaoDaLeitura(DateTime(2026, 1, 1), null), 'Em leitura');
    expect(situacaoDaLeitura(DateTime(2026, 1, 1), DateTime(2026, 2, 1)), 'Lido');
    expect(temasLeitura.map((t) => t.codigo), ['drama', 'fantasia', 'romance', 'reflexao']);
  });

  test('banco: cria, atualiza e exclui a ficha sem apagar o registro', () async {
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final id = await banco.inserirLeitura(titulo: 'Dom Casmurro', autor: 'Machado de Assis', notaDrama: 4);
    var l = (await banco.leituraPorId(id))!;
    expect(l.formato, 'fisico');
    expect(l.notaDrama, 4);
    await banco.atualizarLeitura(id,
        titulo: 'Dom Casmurro',
        autor: 'Machado',
        formato: 'digital',
        notaDrama: 5,
        notaFantasia: 0,
        notaRomance: 3,
        notaReflexao: 2,
        fraseFavorita: 'Capitu...',
        capa: _png);
    l = (await banco.leituraPorId(id))!;
    expect(l.autor, 'Machado');
    expect(l.formato, 'digital');
    expect(l.notaRomance, 3);
    expect(l.capa, _png);
    await banco.excluirLeitura(id);
    expect(await banco.leituraPorId(id), isNull);
    expect(await banco.listarLeituras(), isEmpty);
  });

  testWidgets('ficha: preenche como a ficha de papel, salva e aparece na lista', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        escolhedorArquivosProvider.overrideWithValue(
            () async => [ArquivoAnexo(nome: 'capa.png', bytes: _png, tipoMime: 'image/png')]),
      ],
      child: MaterialApp(theme: temaApp(), home: const LeituraPage(titulo: 'Leitura')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leitura_vazia')), findsOneWidget);

    await tester.tap(find.byKey(const Key('fab_nova_leitura')));
    await tester.pumpAndSettle();

    // titulo e obrigatorio
    await tester.tap(find.byKey(const Key('botao_salvar_leitura')));
    await tester.pumpAndSettle();
    expect(find.text('Informe o título do livro'), findsOneWidget);

    await tester.tap(find.byKey(const Key('campo_capa_leitura')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('imagem_capa_leitura')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('campo_titulo_leitura')), 'O Pequeno Príncipe');
    await tester.enterText(find.byKey(const Key('campo_autor_leitura')), 'Saint-Exupéry');
    await tester.tap(find.byKey(const Key('formato_digital')));
    await tester.tap(find.byKey(const Key('nota_drama_3')));
    await tester.tap(find.byKey(const Key('nota_fantasia_5')));
    await tester.tap(find.byKey(const Key('nota_romance_2')));
    await tester.tap(find.byKey(const Key('nota_reflexao_4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('nota_reflexao_4'))); // de novo: zera
    await tester.enterText(find.byKey(const Key('campo_frase_leitura')), 'O essencial é invisível aos olhos.');
    await tester.enterText(find.byKey(const Key('campo_personagens_leitura')), 'O Príncipe\nA Raposa');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_salvar_leitura')));
    await tester.pumpAndSettle();

    final salvas = await banco.listarLeituras();
    expect(salvas, hasLength(1));
    final l = salvas.single;
    expect(l.titulo, 'O Pequeno Príncipe');
    expect(l.autor, 'Saint-Exupéry');
    expect(l.formato, 'digital');
    expect([l.notaDrama, l.notaFantasia, l.notaRomance, l.notaReflexao], [3, 5, 2, 0]);
    expect(l.fraseFavorita, 'O essencial é invisível aos olhos.');
    expect(l.personagens, 'O Príncipe\nA Raposa');
    expect(l.capa, _png);

    // voltou para a lista, com a ficha
    expect(find.text('O Pequeno Príncipe'), findsOneWidget);
    expect(find.text('Saint-Exupéry'), findsOneWidget);

    // editar e excluir
    await tester.tap(find.byKey(Key('leitura_${l.id}')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('campo_titulo_leitura'))).controller!.text, 'O Pequeno Príncipe');
    await tester.tap(find.byKey(const Key('excluir_leitura_form')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar_exclusao_leitura')));
    await tester.pumpAndSettle();
    expect(await banco.listarLeituras(), isEmpty);
    expect(find.byKey(const Key('leitura_vazia')), findsOneWidget);
    await encerrar(tester);
  });

  testWidgets('ficha: data de termino antes do inicio e recusada', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final id = await banco.inserirLeitura(titulo: 'X');
    final base = (await banco.leituraPorId(id))!;
    await banco.atualizarLeitura(id,
        titulo: 'X',
        iniciouEm: DateTime(2026, 5, 10),
        terminouEm: DateTime(2026, 5, 1),
        formato: base.formato,
        notaDrama: 0,
        notaFantasia: 0,
        notaRomance: 0,
        notaReflexao: 0);
    final l = (await banco.leituraPorId(id))!;
    await tester.pumpWidget(ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco)],
      child: MaterialApp(theme: temaApp(), home: LeituraFormPage(leitura: l)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('botao_salvar_leitura')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('erro_leitura')), findsOneWidget);
    await encerrar(tester);
  });
}
