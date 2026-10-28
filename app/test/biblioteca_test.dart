import 'dart:typed_data';

import 'package:controle_pessoal/core/arquivos.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/biblioteca/biblioteca_form_page.dart';
import 'package:controle_pessoal/features/biblioteca/biblioteca_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'util_testes.dart';

Widget _app(Banco banco, Widget home, {List<Override> extra = const []}) => ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco), ...extra],
      child: MaterialApp(theme: temaApp(), home: home),
    );

void _tela(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('banco: tombo sequencial, tombo em uso e exclusao sem apagar', () async {
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    expect(await banco.proximoTombo(), 1);
    final id = await banco.inserirObra(ObrasCompanion(tombo: const Value(40102), titulo: const Value('Dom Casmurro')));
    var o = (await banco.obraPorId(id))!;
    expect(o.noAcervo, isTrue);
    expect(o.exemplar, 1);
    expect(o.faixaEtaria, '00-99');
    expect(o.capaAutoAjuste, isTrue);
    expect(await banco.proximoTombo(), 40103);
    expect(await banco.tomboEmUso(40102), isTrue);
    expect(await banco.tomboEmUso(40102, exceto: id), isFalse);
    await banco.atualizarObra(id, ObrasCompanion(tombo: const Value(40102), titulo: const Value('Dom Casmurro'), ano: const Value(1899)));
    o = (await banco.obraPorId(id))!;
    expect(o.ano, 1899);
    await banco.excluirObra(id);
    expect(await banco.listarObras(), isEmpty);
    expect(await banco.tomboEmUso(40102), isFalse);
  });

  testWidgets('cadastro: sugere o tombo, salva todos os campos e aparece na lista', (tester) async {
    _tela(tester);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    await banco.inserirObra(ObrasCompanion(tombo: const Value(40101), titulo: const Value('Antiga')));
    final png = Uint8List.fromList(List.filled(8, 1));
    await tester.pumpWidget(_app(banco, const BibliotecaPage(titulo: 'Biblioteca'), extra: [
      escolhedorArquivosProvider.overrideWithValue(() async => [ArquivoAnexo(nome: 'c.png', bytes: png, tipoMime: 'image/png')]),
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fab_nova_obra')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.byKey(const Key('campo_tombo_obra'))).controller!.text, '40102');
    expect(tester.widget<TextFormField>(find.byKey(const Key('campo_exemplar_obra'))).controller!.text, '1');
    expect(tester.widget<TextFormField>(find.byKey(const Key('campo_faixa_etaria'))).controller!.text, '00-99');
    expect(find.text('NO ACERVO'), findsOneWidget);

    // titulo obrigatorio
    await tester.tap(find.byKey(const Key('botao_salvar_obra')));
    await tester.pumpAndSettle();
    expect(find.text('Informe o título da obra'), findsOneWidget);

    Future<void> digitar(String chave, String texto) async {
      await tester.ensureVisible(find.byKey(Key(chave)));
      await tester.enterText(find.byKey(Key(chave)), texto);
    }

    await digitar('campo_isbn_obra', '9788535902778');
    await digitar('campo_tipo_codigo', 'LV');
    await digitar('campo_tipo_descricao', 'Livro');
    await digitar('campo_titulo_obra', 'Memórias Póstumas');
    await digitar('campo_subtitulo_obra', 'de Brás Cubas');
    await digitar('campo_edicao_obra', '3');
    await digitar('campo_ano_obra', '1881');
    await digitar('campo_dias_obra', '14');
    await digitar('campo_classif_codigo', 'CDD');
    await digitar('campo_classif_descricao', 'Dewey');
    await digitar('campo_cod_autor', 'M149');
    await digitar('campo_paginas_obra', '256');
    await digitar('campo_idioma_codigo', 'PT');
    await digitar('campo_idioma_descricao', 'Português');
    await digitar('campo_editora_descricao', 'Globo');
    await digitar('campo_valor_obra', '49,90');
    await digitar('campo_localizacao_descricao', 'Estante 3');
    await digitar('campo_situacao_descricao', 'Disponível');
    await tester.ensureVisible(find.byKey(const Key('escolher_capa_obra')));
    await tester.tap(find.byKey(const Key('escolher_capa_obra')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('imagem_capa_obra')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('capa_centralizar')));
    await tester.tap(find.byKey(const Key('capa_centralizar')));
    await tester.tap(find.byKey(const Key('campo_no_acervo')));
    await tester.pumpAndSettle();

    // aba Observacoes
    await tester.tap(find.text('Observações'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_observacoes_obra')), 'Capa dura');
    await tester.tap(find.byKey(const Key('botao_salvar_obra')));
    await tester.pumpAndSettle();

    final obras = await banco.listarObras();
    expect(obras, hasLength(2));
    final o = obras.first;
    expect(o.tombo, 40102);
    expect(o.titulo, 'Memórias Póstumas');
    expect(o.subtitulo, 'de Brás Cubas');
    expect(o.isbn, '9788535902778');
    expect([o.tipoCodigo, o.tipoDescricao], ['LV', 'Livro']);
    expect([o.edicao, o.ano, o.diasPrevisao, o.nroPaginas], ['3', 1881, 14, 256]);
    expect([o.classifTipoCodigo, o.codAutor], ['CDD', 'M149']);
    expect([o.idiomaCodigo, o.idiomaDescricao, o.editoraDescricao], ['PT', 'Português', 'Globo']);
    expect(o.valorCentavos, 4990);
    expect([o.localizacaoDescricao, o.situacaoDescricao], ['Estante 3', 'Disponível']);
    expect(o.noAcervo, isFalse);
    expect(o.capaCentralizar, isFalse);
    expect(o.capaAutoAjuste, isTrue);
    expect(o.capa, png);
    expect(o.observacoes, 'Capa dura');

    // lista e busca
    expect(find.text('Memórias Póstumas'), findsOneWidget);
    expect(find.text('FORA'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('busca_obra')), 'antiga');
    await tester.pumpAndSettle();
    expect(find.text('Memórias Póstumas'), findsNothing);
    expect(find.text('Antiga'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('busca_obra')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('biblioteca_vazia')), findsOneWidget);
    await encerrar(tester);
  });

  testWidgets('cadastro: tombo repetido e recusado; lupa oferece valores ja usados; excluir', (tester) async {
    _tela(tester);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    await banco.inserirObra(ObrasCompanion(
        tombo: const Value(7), titulo: const Value('A'), idiomaCodigo: const Value('EN'), idiomaDescricao: const Value('Inglês')));
    final id = await banco.inserirObra(ObrasCompanion(tombo: const Value(8), titulo: const Value('B')));
    final b = (await banco.obraPorId(id))!;
    await tester.pumpWidget(_app(banco, ObraFormPage(obra: b)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('campo_tombo_obra')), '7');
    await tester.tap(find.byKey(const Key('botao_salvar_obra')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('erro_obra')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('lupa_idioma')));
    await tester.tap(find.byKey(const Key('lupa_idioma')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('opcao_idioma_EN')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('campo_idioma_descricao'))).controller!.text, 'Inglês');

    await tester.ensureVisible(find.byKey(const Key('lupa_localizacao')));
    await tester.tap(find.byKey(const Key('lupa_localizacao')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lupa_vazia')), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('excluir_obra_form')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar_exclusao_obra')));
    await tester.pumpAndSettle();
    expect(await banco.obraPorId(id), isNull);
    await encerrar(tester);
  });
}
