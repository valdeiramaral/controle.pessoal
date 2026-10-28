import 'package:controle_pessoal/core/tarefas_calculo.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/agenda/quadro_aba.dart';
import 'package:controle_pessoal/features/agenda/tarefa_form_page.dart';
import 'package:controle_pessoal/features/agenda/tarefas_aba.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'util_testes.dart';

Banco _novoBanco() {
  final b = Banco.paraTeste(NativeDatabase.memory());
  addTearDown(b.close);
  return b;
}

Widget _app(Banco banco, Widget home) => ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco)],
      child: MaterialApp(theme: temaApp(), home: home),
    );

Widget _abrirForm(Banco banco) => _app(
    banco,
    Scaffold(
        body: Builder(
            builder: (c) => TextButton(
                onPressed: () => abrirFormularioTarefa(c, hoje: DateTime(2026, 10, 28)), child: const Text('abrir')))));

void main() {
  group('tarefas: regras', () {
    test('prioridade padrao e Media; cores: alta vermelho, media laranja, baixa verde', () {
      expect(prioridadePadraoTarefa, 'media');
      expect(prioridadesTarefa.keys, ['alta', 'media', 'baixa']);
      expect(corDaPrioridade('alta'), const Color(0xFFD32F2F));
      expect(corDaPrioridade('media'), const Color(0xFFF57C00));
      expect(corDaPrioridade('baixa'), const Color(0xFF388E3C));
    });

    test('descricaoEstimativa', () {
      expect(descricaoEstimativa(30, 'minutos'), '30 min');
      expect(descricaoEstimativa(2, 'horas'), '2 h');
      expect(descricaoEstimativa(1, 'dias'), '1 dia');
      expect(descricaoEstimativa(3, 'dias'), '3 dias');
      expect(descricaoEstimativa(null, 'horas'), isNull);
      expect(descricaoEstimativa(0, 'horas'), isNull);
    });

    test('banco: cadastra com prioridade Media por padrao; concluir e reabrir mudam etapa e status; excluir some', () async {
      final b = _novoBanco();
      final id = await b.inserirTarefa(titulo: 'Pintar o muro', projeto: 'Reforma', prazo: DateTime(2026, 11, 3), estimativa: 2, estimativaUnidade: 'horas');
      var t = (await b.tarefaPorId(id))!;
      expect([t.prioridade, t.etapa, t.status, t.projeto, t.estimativa, t.estimativaUnidade], ['media', 'a_fazer', 'aberta', 'Reforma', 2, 'horas']);
      await b.definirEtapaTarefa(id, 'concluida');
      t = (await b.tarefaPorId(id))!;
      expect([t.etapa, t.status], ['concluida', 'concluida']);
      await b.definirEtapaTarefa(id, 'em_andamento');
      t = (await b.tarefaPorId(id))!;
      expect([t.etapa, t.status], ['em_andamento', 'aberta']);
      expect(await b.projetosDeTarefas(), ['Reforma']);
      await b.excluirTarefa(id);
      expect(await b.tarefaPorId(id), isNull);
      expect(await b.listarTarefas(), isEmpty);
    });

    test('agruparTarefasPorDia: dias crescentes, sem data por ultimo, prioridade alta primeiro no dia', () async {
      final b = _novoBanco();
      await b.inserirTarefa(titulo: 'C sem data');
      await b.inserirTarefa(titulo: 'B baixa', prazo: DateTime(2026, 10, 30, 15), prioridade: 'baixa');
      await b.inserirTarefa(titulo: 'A alta', prazo: DateTime(2026, 10, 30, 8), prioridade: 'alta');
      await b.inserirTarefa(titulo: 'Antes', prazo: DateTime(2026, 10, 29));
      final g = agruparTarefasPorDia(await b.listarTarefas());
      expect(g.map((x) => x.dia), [DateTime(2026, 10, 29), DateTime(2026, 10, 30), null]);
      expect(g[1].itens.map((t) => t.titulo), ['A alta', 'B baixa']);
    });
  });

  group('quadro da semana', () {
    test('inicioDaSemana: segunda-feira', () {
      expect(inicioDaSemana(DateTime(2026, 10, 28)), DateTime(2026, 10, 26)); // quarta
      expect(inicioDaSemana(DateTime(2026, 10, 26)), DateTime(2026, 10, 26)); // segunda
      expect(inicioDaSemana(DateTime(2026, 11, 1)), DateTime(2026, 10, 26)); // domingo
      expect(inicioDaSemana(DateTime(2026, 11, 2)), DateTime(2026, 11, 2));
    });

    testWidgets('tarefas em verde e compromissos em azul, no dia certo; navega entre as semanas', (tester) async {
      tester.view.physicalSize = const Size(2000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      final t = await banco.inserirTarefa(titulo: 'Pintar muro', prazo: DateTime(2026, 10, 29), prioridade: 'alta');
      final e = await banco.inserirEvento(titulo: 'Dentista', inicio: DateTime(2026, 10, 29, 10, 30));
      await banco.inserirTarefa(titulo: 'Semana seguinte', prazo: DateTime(2026, 11, 3));
      await tester.pumpWidget(_app(banco, Scaffold(body: QuadroAba(agora: DateTime(2026, 10, 28)))));
      await tester.pumpAndSettle();

      expect(find.text('26/10/2026 a 01/11/2026'), findsOneWidget);
      expect(find.text('Quinta-feira'), findsOneWidget);
      final quinta = find.byKey(const Key('quadro_dia_3'));
      expect(find.descendant(of: quinta, matching: find.byKey(Key('quadro_tarefa_$t'))), findsOneWidget);
      expect(find.descendant(of: quinta, matching: find.byKey(Key('quadro_evento_$e'))), findsOneWidget);
      expect(find.text('10:30'), findsOneWidget);
      expect(tester.widget<Card>(find.byKey(Key('quadro_tarefa_$t'))).color!.toARGB32() & 0xFFFFFF, corTarefaQuadro.toARGB32() & 0xFFFFFF);
      expect(tester.widget<Card>(find.byKey(Key('quadro_evento_$e'))).color!.toARGB32() & 0xFFFFFF, corCompromissoQuadro.toARGB32() & 0xFFFFFF);
      expect(find.text('Semana seguinte'), findsNothing);

      await tester.tap(find.byKey(const Key('quadro_proxima')));
      await tester.pumpAndSettle();
      expect(find.text('02/11/2026 a 08/11/2026'), findsOneWidget);
      expect(find.text('Semana seguinte'), findsOneWidget);
      expect(find.text('Pintar muro'), findsNothing);
      await tester.tap(find.byKey(const Key('quadro_hoje')));
      await tester.pumpAndSettle();
      expect(find.text('26/10/2026 a 01/11/2026'), findsOneWidget);

      // concluir pelo cartao
      await tester.tap(find.byKey(Key('quadro_concluir_$t')));
      await tester.pumpAndSettle();
      expect((await banco.tarefaPorId(t))!.etapa, 'concluida');
      await encerrar(tester);
    });
  });

  group('tarefas: telas', () {
    testWidgets('cadastro: prioridade vem em Media; nome e obrigatorio; salva com os campos e fecha', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      await tester.pumpWidget(_abrirForm(banco));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Nova tarefa'), findsOneWidget);
      expect(find.byKey(const Key('tag_prioridade_media')), findsOneWidget); // padrao: Media (laranja)
      await tester.tap(find.byKey(const Key('botao_salvar_tarefa')));
      await tester.pumpAndSettle();
      expect(find.text('Informe o nome da tarefa'), findsOneWidget);
      expect(await banco.listarTarefas(), isEmpty);

      await tester.enterText(find.byKey(const Key('campo_projeto_tarefa')), 'Reforma da casa');
      await tester.enterText(find.byKey(const Key('campo_nome_tarefa')), 'Comprar tinta');
      await tester.enterText(find.byKey(const Key('campo_descricao_tarefa')), 'Branco fosco, 18 litros');
      await tester.tap(find.byKey(const Key('campo_prioridade_tarefa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alta').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tag_prioridade_alta')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('campo_estimativa_tarefa')), '45');
      await tester.enterText(find.byKey(const Key('campo_responsavel_tarefa')), 'Eu');
      await tester.tap(find.byKey(const Key('campo_etapa_tarefa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aguardando').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dados_complementares_tarefa')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_tags_tarefa')), 'casa, urgente');
      await tester.tap(find.byKey(const Key('botao_salvar_tarefa')));
      await tester.pumpAndSettle();

      final t = (await banco.listarTarefas()).single;
      expect([t.titulo, t.projeto, t.descricao, t.prioridade, t.etapa, t.estimativa, t.estimativaUnidade, t.responsavel, t.tags],
          ['Comprar tinta', 'Reforma da casa', 'Branco fosco, 18 litros', 'alta', 'aguardando', 45, 'minutos', 'Eu', 'casa,urgente']);
      expect(find.text('Nova tarefa'), findsNothing); // "Fechar" e o padrao
      await encerrar(tester);
    });

    testWidgets('apos salvar: "Adicionar nova" limpa o formulario e mantem a tela aberta', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      await tester.pumpWidget(_abrirForm(banco));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('depois_nova')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('campo_nome_tarefa')), 'Primeira');
      await tester.tap(find.byKey(const Key('botao_salvar_tarefa')));
      await tester.pumpAndSettle();
      expect(find.text('Nova tarefa'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byKey(const Key('campo_nome_tarefa'))).controller!.text, isEmpty);
      await tester.enterText(find.byKey(const Key('campo_nome_tarefa')), 'Segunda');
      await tester.tap(find.byKey(const Key('botao_salvar_tarefa')));
      await tester.pumpAndSettle();
      expect((await banco.listarTarefas()).map((t) => t.titulo).toSet(), {'Primeira', 'Segunda'});
      await encerrar(tester);
    });

    testWidgets('lista: por dia, tag colorida, filtro por prioridade, concluir some, excluir pede confirmacao', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      final a = await banco.inserirTarefa(titulo: 'Tarefa alta', prazo: DateTime(2026, 10, 29), prioridade: 'alta');
      final m = await banco.inserirTarefa(titulo: 'Tarefa media', prazo: DateTime(2026, 10, 29));
      final bx = await banco.inserirTarefa(titulo: 'Tarefa baixa', prazo: DateTime(2026, 10, 30), prioridade: 'baixa');
      await tester.pumpWidget(_app(banco, Scaffold(body: TarefasAba(agora: DateTime(2026, 10, 28)))));
      await tester.pumpAndSettle();

      expect(find.text('Amanhã · 29/10/2026'), findsOneWidget);
      for (final (id, cor) in [(a, 0xFFD32F2F), (m, 0xFFF57C00), (bx, 0xFF388E3C)]) {
        final caixa = tester.widget<Container>(find.byKey(Key('prioridade_$id')));
        expect((caixa.decoration as BoxDecoration).color, Color(cor));
      }
      // filtro
      await tester.tap(find.byKey(const Key('filtro_alta')));
      await tester.pumpAndSettle();
      expect(find.text('Tarefa alta'), findsOneWidget);
      expect(find.text('Tarefa media'), findsNothing);
      await tester.tap(find.byKey(const Key('filtro_todas')));
      await tester.pumpAndSettle();
      // concluir some da lista (aparece em "Concluidas")
      await tester.tap(find.byKey(Key('concluir_$m')));
      await tester.pumpAndSettle();
      expect(find.text('Tarefa media'), findsNothing);
      await tester.tap(find.byKey(const Key('filtro_concluidas')));
      await tester.pumpAndSettle();
      expect(find.text('Tarefa media'), findsOneWidget);
      // excluir
      await tester.tap(find.byKey(Key('excluir_tarefa_$bx')));
      await tester.pumpAndSettle();
      expect(find.text('Excluir tarefa?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmar_exclusao_tarefa')));
      await tester.pumpAndSettle();
      expect(find.text('Tarefa baixa'), findsNothing);
      await encerrar(tester);
    });
  });
}
