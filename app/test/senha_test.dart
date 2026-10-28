import 'dart:math';

import 'package:controle_pessoal/core/cofre.dart';
import 'package:controle_pessoal/core/senha_calculo.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/senha/gerador_dialogo.dart';
import 'package:controle_pessoal/features/senha/senha_form_page.dart';
import 'package:controle_pessoal/features/senha/senha_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'util_testes.dart';

Cofre _cofre([int b = 7]) => CofreAes(() async => List.filled(32, b));

Widget _app(Banco banco, Widget home) => ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco), cofreProvider.overrideWithValue(_cofre())],
      child: MaterialApp(theme: temaApp(), home: home),
    );

/// Abre o formulario como rota empilhada (como no app), para o "salvar" poder fechar a tela.
Widget _anfitriao(Credencial? c) => Builder(
    builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('abrir_form'),
              onPressed: () => abrirCadastroSenha(context, credencial: c),
              child: const Text('abrir'),
            ),
          ),
        ));

void _tela(WidgetTester tester, {double largura = 1400}) {
  tester.view.physicalSize = Size(largura, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<String> _nova(Banco banco, String titulo,
    {String tipo = 'acesso', String tags = '', bool favorito = false, String senha = 'Abc12345!', DateTime? acessadoEm}) async {
  final cofre = _cofre();
  final id = await banco.inserirCredencial(CredenciaisCompanion(
    titulo: Value(titulo),
    tipo: Value(tipo),
    tags: Value(tags),
    favorito: Value(favorito),
    senhaAtual: Value(await cofre.cifrar(senha)),
    email: const Value('eu@exemplo.com'),
  ));
  if (acessadoEm != null) await banco.registrarAcessoCredencial(id, quando: acessadoEm);
  return id;
}

void main() {
  group('cofre (AES-GCM)', () {
    test('cifra e decifra; o texto cifrado nao revela a senha; vazio continua vazio', () async {
      final c = _cofre();
      final x = await c.cifrar('MinhaSenha@2026');
      expect(x.startsWith('v1:'), isTrue);
      expect(x.contains('MinhaSenha'), isFalse);
      expect(await c.decifrar(x), 'MinhaSenha@2026');
      expect(await c.cifrar('MinhaSenha@2026'), isNot(x), reason: 'cada cifragem usa um nonce novo');
      expect(await c.cifrar(''), '');
      expect(await c.decifrar(''), '');
    });

    test('chave errada ou dado alterado nao abre', () async {
      final x = await _cofre().cifrar('segredo');
      await expectLater(_cofre(9).decifrar(x), throwsA(isA<CofreIndisponivel>()));
      await expectLater(_cofre().decifrar('${x.substring(0, x.length - 4)}AAAA'), throwsA(isA<CofreIndisponivel>()));
      await expectLater(_cofre().decifrar('texto puro'), throwsA(isA<CofreIndisponivel>()));
    });
  });

  group('regras', () {
    test('forca e tempo para quebrar', () {
      expect(avaliarSenha('').nivel, 0);
      final fraca = avaliarSenha('12345678');
      expect(fraca.nivel, 1);
      expect(fraca.tempo, 'instantânea');
      expect(avaliarSenha('Xk9#mQ2!vL7@pR4z').nivel, 4);
      expect(avaliarSenha('Xk9#mQ2!vL7@pR4z').tempo, 'séculos');
      expect(avaliarSenha('aaaaaaaa').nivel, lessThanOrEqualTo(avaliarSenha('abcdefgh').nivel));
      expect(formatarTempoParaQuebrar(30), '30 segundos');
      expect(formatarTempoParaQuebrar(86400 * 7), '7 dias');
      expect(formatarTempoParaQuebrar(86400.0 * 40), '1 mês');
    });

    test('gerador respeita tamanho e grupos', () {
      final r = Random(1);
      final s = gerarSenha(tamanho: 20, random: r);
      expect(s.length, 20);
      expect(RegExp('[a-z]').hasMatch(s), isTrue);
      expect(RegExp('[A-Z]').hasMatch(s), isTrue);
      expect(RegExp('[0-9]').hasMatch(s), isTrue);
      expect(RegExp(r'[^a-zA-Z0-9]').hasMatch(s), isTrue);
      final so = gerarSenha(tamanho: 12, maiusculas: false, minusculas: false, simbolos: false, random: r);
      expect(RegExp(r'^[0-9]{12}$').hasMatch(so), isTrue);
    });
  });

  test('banco: grava cifrado, favorito/etiquetas nao mudam o Modificado, exclusao nao apaga', () async {
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final id = await _nova(banco, 'Banco X', tags: 'banco,pessoal', senha: 'SenhaSecreta#1');
    final c = (await banco.credencialPorId(id))!;
    expect(c.senhaAtual.contains('SenhaSecreta'), isFalse);
    expect(await _cofre().decifrar(c.senhaAtual), 'SenhaSecreta#1');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await banco.definirFavoritoCredencial(id, true);
    await banco.definirTagsCredencial(id, 'banco');
    await banco.definirAutopreencherCredencial(id, false);
    final d = (await banco.credencialPorId(id))!;
    expect(d.favorito, isTrue);
    expect(d.autopreencher, isFalse);
    expect(d.tags, 'banco');
    expect(d.atualizadoEm, c.atualizadoEm);
    await banco.excluirCredencial(id);
    expect(await banco.listarCredenciais(), isEmpty);
  });

  test('filtros, contagens e busca', () async {
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final agora = DateTime(2026, 10, 28, 12);
    await _nova(banco, 'Gmail', tags: 'google,pessoal', favorito: true, acessadoEm: agora.subtract(const Duration(days: 2)));
    await _nova(banco, 'Visa', tipo: 'cartao', tags: 'banco', acessadoEm: agora.subtract(const Duration(days: 20)));
    await _nova(banco, 'Anotação', tipo: 'nota');
    final todas = await banco.listarCredenciais();
    final cont = contagensDoCofre(todas, agora);
    expect(cont[filtroTodos], 3);
    expect(cont[filtroFavoritos], 1);
    expect(cont[filtroRecentes], 1);
    expect(cont[filtroTipo('cartao')], 1);
    expect(cont[filtroTipo('2fa')], 0);
    expect(cont[filtroTag('banco')], 1);
    expect(etiquetasDoCofre(todas), ['banco', 'google', 'pessoal']);
    expect(todas.where((c) => confereFiltro(c, filtroTag('google'), agora)).single.titulo, 'Gmail');
    expect(todas.where((c) => confereBusca(c, 'anotacao')).single.titulo, 'Anotação');
    expect(ordenarCredenciais(todas, 'nome').map((c) => c.titulo), ['Anotação', 'Gmail', 'Visa']);
  });

  testWidgets('cadastro: salva cifrado; trocar a Senha ATUAL guarda a anterior como Ultima Senha Valida', (tester) async {
    _tela(tester);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    await tester.pumpWidget(_app(banco, _anfitriao(null)));
    await tester.tap(find.byKey(const Key('abrir_form')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('botao_salvar_senha')));
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tipo_cartao')));
    await tester.enterText(find.byKey(const Key('campo_titulo_senha')), 'Cartão Nubank');
    await tester.enterText(find.byKey(const Key('campo_email_senha')), 'eu@exemplo.com');
    await tester.enterText(find.byKey(const Key('campo_atual_senha')), 'SenhaV1#xyz');
    await tester.pump();
    expect(find.byKey(const Key('forca_tempo')), findsWidgets);
    await tester.enterText(find.byKey(const Key('campo_segredo_senha')), '4111111111111111');
    await tester.enterText(find.byKey(const Key('campo_notas_senha')), 'senha do app: 0000');
    await tester.enterText(find.byKey(const Key('campo_tags_senha')), 'Banco, Cartão');
    await tester.tap(find.byKey(const Key('campo_favorito_senha')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('botao_salvar_senha')));
    await tester.pumpAndSettle();

    var c = (await banco.listarCredenciais()).single;
    expect(c.titulo, 'Cartão Nubank');
    expect(c.tipo, 'cartao');
    expect(c.favorito, isTrue);
    expect(c.tags, 'banco,cartão');
    for (final cifrado in [c.senhaAtual, c.segredo, c.notas]) {
      expect(cifrado.startsWith('v1:'), isTrue);
    }
    expect(c.segredo.contains('4111'), isFalse);
    expect(c.notas.contains('0000'), isFalse);
    expect(await _cofre().decifrar(c.segredo), '4111111111111111');

    // editar: trocar a senha atual
    await tester.pumpWidget(_app(banco, _anfitriao(c)));
    await tester.tap(find.byKey(const Key('abrir_form')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('campo_atual_senha'))).controller!.text, 'SenhaV1#xyz');
    await tester.enterText(find.byKey(const Key('campo_atual_senha')), 'SenhaV2#abc');
    await tester.tap(find.byKey(const Key('botao_salvar_senha')));
    await tester.pumpAndSettle();
    c = (await banco.listarCredenciais()).single;
    expect(await _cofre().decifrar(c.senhaAtual), 'SenhaV2#abc');
    expect(await _cofre().decifrar(c.senhaUltimaValida), 'SenhaV1#xyz');
    await encerrar(tester);
  });

  testWidgets('cadastro: gerador preenche a Senha ATUAL', (tester) async {
    _tela(tester);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    await tester.pumpWidget(_app(banco, const SenhaFormPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gerar_senha')));
    await tester.pumpAndSettle();
    final gerada = tester.widget<SelectableText>(find.byKey(const Key('senha_gerada'))).data!;
    expect(gerada.length, 16);
    await tester.tap(find.byKey(const Key('usar_gerada')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('campo_atual_senha'))).controller!.text, gerada);
    await encerrar(tester);
  });

  testWidgets('painel: tres colunas com contagens, filtros, busca, detalhe com olho, favorito e etiquetas', (tester) async {
    _tela(tester);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final agora = DateTime.now();
    final gmail = await _nova(banco, 'Gmail', tags: 'google', favorito: true, senha: 'Segredo#2026x');
    await _nova(banco, 'Visa', tipo: 'cartao', tags: 'banco');
    await _nova(banco, 'Nota solta', tipo: 'nota');
    await tester.pumpWidget(_app(banco, SenhaPage(titulo: 'Senha', agora: agora)));
    await tester.pumpAndSettle();

    String cont(String f) => (tester.widget<ListTile>(find.byKey(Key('filtro_$f'))).trailing as Text).data!;
    expect(cont(filtroTodos), '3');
    expect(cont(filtroFavoritos), '1');
    expect(cont(filtroTipo('cartao')), '1');
    expect(cont(filtroTag('banco')), '1');
    expect(find.byKey(const Key('detalhe_vazio')), findsOneWidget);

    await tester.tap(find.byKey(const Key('filtro_tipo:cartao')));
    await tester.pumpAndSettle();
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('Gmail'), findsNothing);
    await tester.tap(find.byKey(const Key('filtro_todos')));
    await tester.enterText(find.byKey(const Key('busca_senha')), 'nota');
    await tester.pumpAndSettle();
    expect(find.text('Nota solta'), findsOneWidget);
    expect(find.text('Gmail'), findsNothing);
    await tester.enterText(find.byKey(const Key('busca_senha')), '');
    await tester.pumpAndSettle();

    // detalhe: senha oculta ate tocar no olho
    await tester.tap(find.byKey(Key('item_$gmail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detalhe_titulo')), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('valor_atual'))).data, '••••••••');
    expect(find.byKey(const Key('forca_tempo')), findsWidgets);
    await tester.tap(find.byKey(const Key('olho_atual')));
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const Key('valor_atual'))).data, 'Segredo#2026x');
    expect(find.byKey(const Key('detalhe_modificado')), findsOneWidget);
    expect(find.byKey(const Key('detalhe_criado')), findsOneWidget);

    // abrir marca como recente
    expect((await banco.credencialPorId(gmail))!.acessadoEm, isNotNull);

    // etiquetas
    await tester.tap(find.byKey(const Key('definir_etiquetas')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_etiquetas_dialogo')), 'google, trabalho');
    await tester.tap(find.byKey(const Key('salvar_etiquetas')));
    await tester.pumpAndSettle();
    expect((await banco.credencialPorId(gmail))!.tags, 'google,trabalho');
    expect(cont(filtroTag('trabalho')), '1');

    // autopreenchimento e favorito
    await tester.tap(find.byKey(const Key('detalhe_autopreencher')));
    await tester.tap(find.byKey(const Key('favorito_senha')));
    await tester.pumpAndSettle();
    final g = (await banco.credencialPorId(gmail))!;
    expect(g.autopreencher, isFalse);
    expect(g.favorito, isFalse);

    // excluir
    await tester.tap(find.byKey(const Key('excluir_senha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar_exclusao_senha')));
    await tester.pumpAndSettle();
    expect(await banco.credencialPorId(gmail), isNull);
    expect(find.byKey(const Key('detalhe_vazio')), findsOneWidget);
    await encerrar(tester);
  });

  testWidgets('painel estreito: chips de categoria e detalhe em outra tela', (tester) async {
    _tela(tester, largura: 500);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    final id = await _nova(banco, 'Netflix', tags: 'streaming', favorito: true);
    await _nova(banco, 'Visa', tipo: 'cartao');
    await tester.pumpWidget(_app(banco, const SenhaPage()));
    await tester.pumpAndSettle();
    // chips no lugar do menu lateral (so os primeiros cabem na tela; os outros ficam na rolagem)
    expect(find.byKey(const Key('chip_todos')), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Visa'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chip_favoritos')));
    await tester.pumpAndSettle();
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Visa'), findsNothing);
    await tester.tap(find.byKey(const Key('chip_todos')));
    await tester.pumpAndSettle();
    expect(find.text('Visa'), findsOneWidget);
    // o detalhe abre em outra tela
    await tester.tap(find.byKey(Key('item_$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detalhe_titulo')), findsOneWidget);
    await encerrar(tester);
  });

  testWidgets('gerador avulso (toolbar) abre e copia sem "Usar"', (tester) async {
    _tela(tester);
    final banco = Banco.paraTeste(NativeDatabase.memory());
    addTearDown(banco.close);
    await tester.pumpWidget(_app(banco, const SenhaPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('abrir_gerador')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('senha_gerada')), findsOneWidget);
    expect(find.byKey(const Key('usar_gerada')), findsNothing);
    final antes = tester.widget<SelectableText>(find.byKey(const Key('senha_gerada'))).data;
    await tester.tap(find.byKey(const Key('gerar_outra')));
    await tester.pump();
    expect(tester.widget<SelectableText>(find.byKey(const Key('senha_gerada'))).data, isNot(antes));
    await tester.tap(find.byKey(const Key('gerador_simbolos')));
    await tester.pump();
    expect(RegExp(r'[^a-zA-Z0-9]').hasMatch(tester.widget<SelectableText>(find.byKey(const Key('senha_gerada'))).data!), isFalse);
    await encerrar(tester);
  });
}
