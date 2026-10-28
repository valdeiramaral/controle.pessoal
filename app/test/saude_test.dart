import 'package:controle_pessoal/core/catalogo_medicamentos.dart';
import 'package:controle_pessoal/core/formatos.dart';
import 'package:controle_pessoal/core/saude_calculo.dart';
import 'package:controle_pessoal/core/tema.dart';
import 'package:controle_pessoal/data/local/banco.dart';
import 'package:controle_pessoal/features/saude/agendamento_form_page.dart';
import 'package:controle_pessoal/features/saude/agendamentos_aba.dart';
import 'package:controle_pessoal/features/saude/medicacao_aba.dart';
import 'package:controle_pessoal/features/saude/medicamento_form_page.dart';
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

Future<Medicamento> _med(Banco b,
    {String horarios = '08:00',
    String frequencia = 'diaria',
    String diasSemana = '',
    int intervalo = 1,
    int quantidade = 1,
    int? estoque,
    int? minimo,
    DateTime? fim}) async {
  final id = await b.inserirMedicamento(
    nome: 'AAS',
    dose: '100 mg',
    horarios: horarios,
    frequencia: frequencia,
    diasSemana: diasSemana,
    intervaloDias: intervalo,
    quantidade: quantidade,
    inicio: DateTime(2026, 10, 1),
    fim: fim,
    estoque: estoque,
    estoqueMinimo: minimo,
  );
  return (await b.medicamentoPorId(id))!;
}

Widget _app(Banco banco, Widget home) => ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco)],
      child: MaterialApp(theme: temaApp(), home: home),
    );

void main() {
  group('medicacao: regras', () {
    test('lerHorarios ordena, tira repetidos e ignora invalidos', () {
      expect(lerHorarios('20:00, 08:00,08:00, 25:00, abc, 7:5'), [(7, 5), (8, 0), (20, 0)]);
      expect(horariosParaTexto([(8, 0), (20, 30)]), '08:00,20:30');
      expect(lerHorarios(''), isEmpty);
      expect(lerDiasSemana('3,1,9,x,3'), [1, 3]);
    });

    test('tomaNoDia: diaria, periodo, dias da semana, a cada N dias, necessario e suspenso', () async {
      final b = _novoBanco();
      final diaria = await _med(b, fim: DateTime(2026, 10, 31));
      expect(tomaNoDia(diaria, DateTime(2026, 10, 28)), isTrue);
      expect(tomaNoDia(diaria, DateTime(2026, 9, 30)), isFalse); // antes de comecar
      expect(tomaNoDia(diaria, DateTime(2026, 11, 1)), isFalse); // depois de terminar

      final semana = await _med(b, frequencia: 'dias_semana', diasSemana: '1,3'); // seg e qua
      expect(tomaNoDia(semana, DateTime(2026, 10, 28)), isTrue); // quarta
      expect(tomaNoDia(semana, DateTime(2026, 10, 26)), isTrue); // segunda
      expect(tomaNoDia(semana, DateTime(2026, 10, 29)), isFalse); // quinta

      final cada3 = await _med(b, frequencia: 'intervalo', intervalo: 3); // desde 01/10
      expect(tomaNoDia(cada3, DateTime(2026, 10, 4)), isTrue);
      expect(tomaNoDia(cada3, DateTime(2026, 10, 5)), isFalse);
      expect(tomaNoDia(cada3, DateTime(2026, 10, 28)), isTrue);

      final prn = await _med(b, frequencia: 'necessario', horarios: '');
      expect(tomaNoDia(prn, DateTime(2026, 10, 28)), isFalse);
      expect(dosesDoDia(prn, DateTime(2026, 10, 28)), isEmpty);

      await b.definirAtivoMedicamento(diaria.id, false);
      final suspenso = (await b.medicamentoPorId(diaria.id))!;
      expect(suspenso.ativo, isFalse);
      expect(dosesDoDia(suspenso, DateTime(2026, 10, 28)), isEmpty);
    });

    test('dosesDoDia e resumo da frequencia', () async {
      final b = _novoBanco();
      final m = await _med(b, horarios: '20:00,08:00');
      expect(dosesDoDia(m, DateTime(2026, 10, 28)), [DateTime(2026, 10, 28, 8), DateTime(2026, 10, 28, 20)]);
      expect(resumoFrequencia(m), 'Todos os dias · 08:00, 20:00');
      final s = await _med(b, frequencia: 'dias_semana', diasSemana: '1,3');
      expect(resumoFrequencia(s), 'Seg, Qua · 08:00');
      final i = await _med(b, frequencia: 'intervalo', intervalo: 2);
      expect(resumoFrequencia(i), 'A cada 2 dias · 08:00');
      expect(descricaoQuantidade('comprimido', 1), '1 comprimido');
      expect(descricaoQuantidade('capsula', 2), '2 cápsulas');
    });

    test('estoque: dias restantes e alerta de estoque baixo', () async {
      final b = _novoBanco();
      expect(diasDeEstoque(await _med(b, horarios: '08:00,20:00', estoque: 10)), 5);
      expect(diasDeEstoque(await _med(b, estoque: 6, frequencia: 'dias_semana', diasSemana: '1,3,5')), 14);
      expect(diasDeEstoque(await _med(b, estoque: 6, frequencia: 'intervalo', intervalo: 2)), 12);
      expect(diasDeEstoque(await _med(b)), isNull);
      final baixo = await _med(b, estoque: 5, minimo: 5);
      expect(estoqueBaixo(baixo), isTrue);
      expect(estoqueBaixo(await _med(b, estoque: 6, minimo: 5)), isFalse);
      expect(estoqueBaixo(await _med(b, estoque: 1)), isFalse); // sem minimo definido
    });

    test('tomar desconta do estoque, desfazer devolve, pular nao mexe, nunca abaixo de zero', () async {
      final b = _novoBanco();
      final m = await _med(b, horarios: '08:00,20:00', quantidade: 2, estoque: 5);
      final d1 = DateTime(2026, 10, 28, 8);
      final d2 = DateTime(2026, 10, 28, 20);
      Future<int?> estoque() async => (await b.medicamentoPorId(m.id))!.estoque;

      await b.registrarTomada(m, d1);
      expect(await estoque(), 3);
      await b.registrarTomada(m, d1); // repetir nao desconta de novo
      expect(await estoque(), 3);
      await b.registrarTomada(m, d1, status: 'pendente'); // desfazer
      expect(await estoque(), 5);
      await b.registrarTomada(m, d2, status: 'pulou');
      expect(await estoque(), 5);
      await b.registrarTomada(m, d2);
      expect(await estoque(), 3);

      await b.registrarDoseAvulsa(m, agora: DateTime(2026, 10, 28, 15, 0, 0));
      expect(await estoque(), 1);
      await b.registrarDoseAvulsa(m, agora: DateTime(2026, 10, 28, 15, 1, 0));
      expect(await estoque(), 0); // 1 - 2, trava em zero

      final tomadas = await b.listarTomadasDoDia(DateTime(2026, 10, 28));
      expect(tomadas.length, 4);
      expect(tomadas.where((t) => t.status == 'tomou').length, 3);
    });

    test('sem estoque informado, tomar nao cria estoque', () async {
      final b = _novoBanco();
      final m = await _med(b);
      await b.registrarTomada(m, DateTime(2026, 10, 28, 8));
      expect((await b.medicamentoPorId(m.id))!.estoque, isNull);
    });

    test('atualizarMedicamento regrava posologia e estoque', () async {
      final b = _novoBanco();
      final m = await _med(b, estoque: 10);
      await b.atualizarMedicamento(
        m.id,
        nome: 'Sinvastatina',
        dose: '20 mg',
        horarios: '22:00',
        formato: 'comprimido',
        tratamento: 'Colesterol alto',
        quantidade: 1,
        frequencia: 'dias_semana',
        diasSemana: '2,4',
        intervaloDias: 1,
        inicio: DateTime(2026, 10, 1),
        estoque: null,
        lembreteReabastecer: false,
      );
      final novo = (await b.medicamentoPorId(m.id))!;
      expect(novo.nome, 'Sinvastatina');
      expect(novo.tratamento, 'Colesterol alto');
      expect(novo.diasSemana, '2,4');
      expect(novo.estoque, isNull);
      expect(novo.lembreteReabastecer, isFalse);
    });
  });

  group('agendamentos: regras', () {
    test('ocorrencias: mensal nao estoura fim de mes, semanal, anual, hora mantida', () {
      final jan31 = DateTime(2026, 1, 31, 10, 30);
      expect(ocorrenciasAgendamento(jan31, 'meses', 1, 3),
          [DateTime(2026, 1, 31, 10, 30), DateTime(2026, 2, 28, 10, 30), DateTime(2026, 3, 31, 10, 30)]);
      expect(ocorrenciasAgendamento(DateTime(2026, 10, 28, 9), 'semanas', 2, 3),
          [DateTime(2026, 10, 28, 9), DateTime(2026, 11, 11, 9), DateTime(2026, 11, 25, 9)]);
      expect(ocorrenciasAgendamento(DateTime(2028, 2, 29, 8), 'anos', 1, 2), [DateTime(2028, 2, 29, 8), DateTime(2029, 2, 28, 8)]);
      expect(ocorrenciasAgendamento(DateTime(2026, 12, 30), 'dias', 5, 2), [DateTime(2026, 12, 30), DateTime(2027, 1, 4)]);
      expect(rotuloRepeticao('meses:3'), 'Trimestral');
      expect(rotuloRepeticao('meses:5'), 'A cada 5 meses');
      expect(rotuloRepeticao('dias:1'), 'A cada dia');
    });

    test('serie periodica: cria uma linha por data, espelha na Agenda e edita/exclui os seguintes', () async {
      final b = _novoBanco();
      final lista = await b.criarAgendamentos(
        tipo: 'exame',
        titulo: 'Hemograma',
        local: 'Lab Central',
        dataHora: DateTime(2026, 11, 3, 7, 30),
        lembreteMin: 1440,
        repeticaoUnidade: 'meses',
        repeticaoIntervalo: 3,
        vezes: 4,
      );
      expect(lista.length, 4);
      expect(lista.map((a) => a.serieNumero), [1, 2, 3, 4]);
      expect(lista.every((a) => a.serieTotal == 4 && a.repeticao == 'meses:3' && a.grupoSerie == lista.first.grupoSerie), isTrue);
      expect(lista.map((a) => a.dataHora), [
        DateTime(2026, 11, 3, 7, 30),
        DateTime(2027, 2, 3, 7, 30),
        DateTime(2027, 5, 3, 7, 30),
        DateTime(2027, 8, 3, 7, 30),
      ]);
      var eventos = await b.select(b.eventos).get();
      expect(eventos.length, 4);
      expect(eventos.every((e) => e.tipo == 'saude' && e.titulo == 'Exame: Hemograma'), isTrue);

      // Editar o 2o aplicando aos seguintes: muda local em 2, 3 e 4, e a data so no 2o.
      final segundo = lista[1];
      expect(await b.contarSeguintesAgendamento(segundo), 2);
      await b.atualizarAgendamento(
        segundo,
        tipo: 'exame',
        titulo: 'Hemograma completo',
        local: 'Lab Norte',
        dataHora: DateTime(2027, 2, 4, 8),
        aplicarNosSeguintes: true,
      );
      final depois = await b.listarAgendamentos();
      expect(depois[0].local, 'Lab Central'); // anterior nao muda
      expect(depois.sublist(1).every((a) => a.local == 'Lab Norte' && a.titulo == 'Hemograma completo'), isTrue);
      expect(depois[1].dataHora, DateTime(2027, 2, 4, 8));
      expect(depois[2].dataHora, DateTime(2027, 5, 3, 7, 30)); // data dos seguintes preservada
      eventos = await b.select(b.eventos).get();
      expect(eventos.where((e) => e.titulo == 'Exame: Hemograma completo').length, 3);

      // Excluir o 3o e os seguintes.
      final removidos = await b.excluirAgendamento(depois[2], seguintes: true);
      expect(removidos.length, 2);
      expect((await b.listarAgendamentos()).length, 2);
      expect((await b.select(b.eventos).get()).where((e) => e.excluidoEm == null).length, 2);
    });

    test('status: cancelado tira da Agenda, agendado volta; realizado guarda o resultado', () async {
      final b = _novoBanco();
      final a = (await b.criarAgendamentos(tipo: 'consulta', titulo: 'Rotina', dataHora: DateTime(2026, 11, 5, 14))).single;
      expect(a.grupoSerie, isNull);
      expect(a.serieNumero, isNull);
      Future<int> eventosAtivos() async => (await b.select(b.eventos).get()).where((e) => e.excluidoEm == null).length;
      expect(await eventosAtivos(), 1);
      await b.definirStatusAgendamento(a, 'cancelado');
      expect((await b.agendamentoPorId(a.id))!.status, 'cancelado');
      expect(await eventosAtivos(), 0);
      await b.definirStatusAgendamento(a, 'agendado');
      expect(await eventosAtivos(), 1);
      await b.definirStatusAgendamento(a, 'realizado', resultado: 'Tudo normal');
      final r = (await b.agendamentoPorId(a.id))!;
      expect(r.status, 'realizado');
      expect(r.resultado, 'Tudo normal');
      expect(await eventosAtivos(), 1); // realizado continua na Agenda
    });

    test('vezes 1 ou sem unidade cria um unico agendamento', () async {
      final b = _novoBanco();
      final l = await b.criarAgendamentos(
          tipo: 'vacina', titulo: 'Gripe', dataHora: DateTime(2027, 4, 1, 9), repeticaoUnidade: 'anos', vezes: 1);
      expect(l.length, 1);
      expect(l.single.repeticao, isNull);
    });
  });

  group('saude: telas', () {
    testWidgets('cadastra medicamento com posologia e estoque; valida campos obrigatorios', (tester) async {
      tester.view.physicalSize = const Size(900, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      await tester.pumpWidget(_app(
          banco,
          Scaffold(
              body: Builder(
                  builder: (c) => TextButton(
                      onPressed: () => abrirFormularioMedicamento(c, hoje: DateTime(2026, 10, 28)), child: const Text('abrir'))))));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Novo medicamento'), findsOneWidget);
      await tester.tap(find.byKey(const Key('botao_salvar_med')));
      await tester.pumpAndSettle();
      expect(find.text('Informe o nome'), findsOneWidget);
      expect(find.text('Informe a dose'), findsOneWidget);
      expect(await banco.listarMedicamentos(), isEmpty);

      await tester.enterText(find.byKey(const Key('campo_nome_med')), 'Ácido acetilsalicílico');
      await tester.enterText(find.byKey(const Key('campo_dose_med')), '100 mg');
      await tester.enterText(find.byKey(const Key('campo_tratamento_med')), 'Colesterol alto');
      await tester.tap(find.byKey(const Key('campo_frequencia_med')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dias da semana').last);
      await tester.pumpAndSettle();

      // Dias da semana sem escolher nenhum: erro.
      await tester.tap(find.byKey(const Key('botao_salvar_med')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('erro_medicamento')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dia_semana_1')));
      await tester.tap(find.byKey(const Key('dia_semana_3')));
      await tester.pump();
      expect(find.byKey(const Key('horario_08:00')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('campo_estoque_med')), '30');
      await tester.enterText(find.byKey(const Key('campo_estoque_minimo_med')), '5');
      await tester.tap(find.byKey(const Key('botao_salvar_med')));
      await tester.pumpAndSettle();

      final lista = await banco.listarMedicamentos();
      expect(lista.length, 1);
      final m = lista.single;
      expect(m.nome, 'Ácido acetilsalicílico');
      expect(m.dose, '100 mg');
      expect(m.tratamento, 'Colesterol alto');
      expect(m.frequencia, 'dias_semana');
      expect(m.diasSemana, '1,3');
      expect(m.horarios, '08:00');
      expect(m.estoque, 30);
      expect(m.estoqueMinimo, 5);
      expect(m.ativo, isTrue);
      await encerrar(tester);
    });

    testWidgets('suspender pede confirmacao e marca "nao estou tomando"; voltar a tomar reativa', (tester) async {
      tester.view.physicalSize = const Size(900, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      final m = await _med(banco, estoque: 10);
      await tester.pumpWidget(_app(
          banco,
          Scaffold(
              body: Builder(
                  builder: (c) => TextButton(onPressed: () => abrirFormularioMedicamento(c, medicamento: m), child: const Text('abrir'))))));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Editar medicamento'), findsOneWidget);

      await tester.tap(find.byKey(const Key('botao_suspender_med')));
      await tester.pumpAndSettle();
      expect(find.text('Suspender AAS?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('manter_med')));
      await tester.pumpAndSettle();
      expect((await banco.medicamentoPorId(m.id))!.ativo, isTrue);

      await tester.tap(find.byKey(const Key('botao_suspender_med')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmar_suspender')));
      await tester.pumpAndSettle();
      expect((await banco.medicamentoPorId(m.id))!.ativo, isFalse);

      final suspenso = (await banco.medicamentoPorId(m.id))!;
      await tester.pumpWidget(_app(
          banco,
          Scaffold(
              body: Builder(
                  builder: (c) =>
                      TextButton(onPressed: () => abrirFormularioMedicamento(c, medicamento: suspenso), child: const Text('abrir2'))))));
      await tester.tap(find.text('abrir2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aviso_suspenso')), findsOneWidget);
      await tester.tap(find.byKey(const Key('botao_reativar_med')));
      await tester.pumpAndSettle();
      expect((await banco.medicamentoPorId(m.id))!.ativo, isTrue);
      await encerrar(tester);
    });

    testWidgets('doses de hoje: tomei desconta estoque e avisa estoque baixo; desfazer devolve', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      final m = await _med(banco, horarios: '08:00,20:00', estoque: 10, minimo: 9);
      final agora = DateTime(2026, 10, 28, 9, 0);
      await tester.pumpWidget(_app(banco, Scaffold(body: MedicacaoAba(agora: agora))));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('dose_${m.id}_0800')), findsOneWidget);
      expect(find.byKey(Key('dose_${m.id}_2000')), findsOneWidget);
      expect(find.textContaining('Atrasada'), findsOneWidget); // 08:00 ja passou das 09:00
      expect(find.byKey(Key('estoque_${m.id}')), findsOneWidget);

      await tester.tap(find.byKey(Key('tomar_${m.id}_0800')));
      await tester.pumpAndSettle();
      expect((await banco.medicamentoPorId(m.id))!.estoque, 9);
      expect(find.textContaining('Tomou às'), findsOneWidget);
      expect(find.byKey(const Key('aviso_estoque_baixo')), findsOneWidget);
      expect(find.text('Estoque baixo: 9 restantes'), findsOneWidget);

      await tester.tap(find.byKey(Key('desfazer_${m.id}_0800')));
      await tester.pumpAndSettle();
      expect((await banco.medicamentoPorId(m.id))!.estoque, 10);
      expect(find.byKey(Key('tomar_${m.id}_0800')), findsOneWidget);

      await tester.tap(find.byKey(Key('pular_${m.id}_2000')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pulou esta dose'), findsOneWidget);
      expect((await banco.medicamentoPorId(m.id))!.estoque, 10);
      await encerrar(tester);
    });

    testWidgets('medicamento "quando necessario" registra dose avulsa; suspenso some das doses', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      final prn = await _med(banco, frequencia: 'necessario', horarios: '', estoque: 4);
      final susp = await _med(banco, horarios: '12:00');
      await banco.definirAtivoMedicamento(susp.id, false);
      await tester.pumpWidget(_app(banco, Scaffold(body: MedicacaoAba(agora: DateTime(2026, 10, 28, 9)))));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('avulso_${prn.id}')), findsOneWidget);
      expect(find.byKey(Key('dose_${susp.id}_1200')), findsNothing);
      expect(find.textContaining('Não estou tomando'), findsOneWidget); // na lista de medicamentos

      await tester.tap(find.byKey(Key('dose_avulsa_${prn.id}')));
      await tester.pumpAndSettle();
      expect((await banco.medicamentoPorId(prn.id))!.estoque, 3);
      await encerrar(tester);
    });

    testWidgets('agenda um exame periodico (trimestral) com previa e grava a serie', (tester) async {
      tester.view.physicalSize = const Size(900, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      await tester.pumpWidget(_app(
          banco,
          Scaffold(
              body: Builder(
                  builder: (c) => TextButton(
                      onPressed: () => abrirFormularioAgendamento(c, agora: DateTime(2026, 10, 28, 10, 15)),
                      child: const Text('abrir'))))));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('texto_data_ag'))).data, '29/10/2026 10:00');
      await tester.tap(find.byKey(const Key('botao_salvar_ag')));
      await tester.pumpAndSettle();
      expect(find.text('Informe a descrição'), findsOneWidget);
      expect(await banco.listarAgendamentos(), isEmpty);

      await tester.tap(find.byKey(const Key('campo_tipo_ag')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exame').last);
      await tester.pumpAndSettle();
      expect(find.text('Nome do exame'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('campo_titulo_ag')), 'Hemograma completo');
      await tester.enterText(find.byKey(const Key('campo_local_ag')), 'Lab Central');
      await tester.enterText(find.byKey(const Key('campo_preparo_ag')), 'Jejum de 8 horas');
      await tester.tap(find.byKey(const Key('campo_repetir_ag')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trimestral').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_vezes_ag')), '3');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('previa_serie_ag'))).data, '3 agendamentos: de 29/10/2026 a 29/04/2027');

      await tester.tap(find.byKey(const Key('botao_salvar_ag')));
      await tester.pumpAndSettle();

      final lista = await banco.listarAgendamentos();
      expect(lista.length, 3);
      expect(lista.every((a) => a.tipo == 'exame' && a.titulo == 'Hemograma completo' && a.preparo == 'Jejum de 8 horas'), isTrue);
      expect(lista.map((a) => a.dataHora), [DateTime(2026, 10, 29, 10), DateTime(2027, 1, 29, 10), DateTime(2027, 4, 29, 10)]);
      expect(lista.first.lembreteMin, 60); // padrao: 1 hora antes
      expect((await banco.select(banco.eventos).get()).length, 3);
      await encerrar(tester);
    });

    testWidgets('lista consultas e exames, filtra, abre o detalhe, marca realizado e exclui', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      final consulta = (await banco.criarAgendamentos(
              tipo: 'consulta', titulo: 'Revisão', especialidade: 'Cardiologia', profissional: 'Dra. Ana', dataHora: DateTime(2026, 11, 5, 14)))
          .single;
      await banco.criarAgendamentos(tipo: 'exame', titulo: 'Ultrassom', dataHora: DateTime(2026, 11, 10, 8));
      await tester.pumpWidget(_app(banco, Scaffold(body: AgendamentosAba(agora: DateTime(2026, 10, 28)))));
      await tester.pumpAndSettle();

      expect(find.text('Próximos (2)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('filtro_ag_exames')));
      await tester.pumpAndSettle();
      expect(find.text('Próximos (1)'), findsOneWidget);
      expect(find.text('Ultrassom'), findsOneWidget);
      expect(find.text('Revisão'), findsNothing);
      await tester.tap(find.byKey(const Key('filtro_ag_todos')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('agendamento_${consulta.id}')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('det_ag_titulo'))).data, 'Revisão');
      expect(tester.widget<Text>(find.byKey(const Key('det_ag_status'))).data, 'Agendado');
      expect(find.text('Dra. Ana'), findsOneWidget);
      expect(find.text('Cardiologia'), findsOneWidget);

      await tester.tap(find.byKey(const Key('botao_ag_realizado')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_resultado_ag')), 'Pressão normal');
      await tester.tap(find.byKey(const Key('confirmar_realizado')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('det_ag_status'))).data, 'Realizado');
      expect(find.text('Pressão normal'), findsOneWidget);
      expect((await banco.agendamentoPorId(consulta.id))!.resultado, 'Pressão normal');

      await tester.tap(find.byKey(const Key('botao_excluir_ag')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('excluir_so_este_ag')));
      await tester.pumpAndSettle();
      expect(await banco.agendamentoPorId(consulta.id), isNull);
      expect(find.text('Próximos (1)'), findsOneWidget); // voltou para a lista, so o exame
      await encerrar(tester);
    });
  });

  group('medicamento: periodo de uso', () {
    test('fimDoPeriodo: dias, semanas e meses (o inicio conta como o primeiro dia); continuo = sem fim', () {
      final i = DateTime(2026, 10, 1);
      expect(fimDoPeriodo(i, 'diario', 7), DateTime(2026, 10, 7));
      expect(fimDoPeriodo(i, 'diario', 1), DateTime(2026, 10, 1));
      expect(fimDoPeriodo(i, 'semanal', 2), DateTime(2026, 10, 14));
      expect(fimDoPeriodo(DateTime(2026, 1, 15), 'mensal', 1), DateTime(2026, 2, 14));
      expect(fimDoPeriodo(DateTime(2026, 1, 31), 'mensal', 1), DateTime(2026, 2, 27)); // fevereiro mais curto
      expect(fimDoPeriodo(DateTime(2026, 11, 10), 'mensal', 3), DateTime(2027, 2, 9));
      expect(fimDoPeriodo(i, 'continuo', 5), isNull);
      expect(fimDoPeriodo(i, 'diario', null), isNull);
      expect(fimDoPeriodo(i, 'diario', 0), isNull);
    });

    test('grava periodo e duracao; resumo mostra "uso continuo" ou "uso por N ... (ate data)"', () async {
      final b = _novoBanco();
      addTearDown(b.close);
      final cont = (await b.medicamentoPorId(await b.inserirMedicamento(nome: 'A', dose: '1', horarios: '08:00', inicio: DateTime(2026, 10, 1))))!;
      expect(cont.periodoUso, 'continuo');
      expect(resumoPeriodoUso(cont), 'Uso contínuo');
      final fim = fimDoPeriodo(DateTime(2026, 10, 1), 'semanal', 2);
      final id = await b.inserirMedicamento(
          nome: 'B', dose: '1', horarios: '08:00', inicio: DateTime(2026, 10, 1), fim: fim, periodoUso: 'semanal', duracaoUso: 2);
      final m = (await b.medicamentoPorId(id))!;
      expect(m.periodoUso, 'semanal');
      expect(m.duracaoUso, 2);
      expect(resumoPeriodoUso(m), 'Uso por 2 semanas (até 14/10/2026)');
      expect(tomaNoDia(m, DateTime(2026, 10, 14)), isTrue);
      expect(tomaNoDia(m, DateTime(2026, 10, 15)), isFalse);
    });

    testWidgets('formulario: continuo nao pede tempo; semanal pede e calcula o termino', (tester) async {
      tester.view.physicalSize = const Size(900, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      await tester.pumpWidget(_app(
          banco,
          Scaffold(
              body: Builder(
                  builder: (c) => TextButton(
                      onPressed: () => abrirFormularioMedicamento(c, hoje: DateTime(2026, 10, 28)), child: const Text('abrir'))))));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_nome_med')), 'Amoxicilina');
      await tester.enterText(find.byKey(const Key('campo_dose_med')), '500 mg');
      expect(find.byKey(const Key('campo_periodo_med')), findsOneWidget);
      expect(find.byKey(const Key('campo_duracao_med')), findsNothing); // contínuo por padrão

      await tester.tap(find.byKey(const Key('campo_periodo_med')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semanal (por semanas)').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('campo_duracao_med')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('campo_duracao_med')), '');
      await tester.tap(find.byKey(const Key('botao_salvar_med')));
      await tester.pumpAndSettle();
      expect(await banco.listarMedicamentos(), isEmpty); // sem o tempo, nao salva

      await tester.enterText(find.byKey(const Key('campo_duracao_med')), '2');
      await tester.pump();
      expect(find.text('Termina em ${formatarData(DateTime(2026, 11, 10))}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('botao_salvar_med')));
      await tester.pumpAndSettle();
      final m = (await banco.listarMedicamentos()).single;
      expect(m.periodoUso, 'semanal');
      expect(m.duracaoUso, 2);
      expect(m.fim, DateTime(2026, 11, 10));
      await encerrar(tester);
    });
  });

  group('medicamento: identificacao e informacoes', () {
    test('catalogo: reconhece nome, apelido e "nome + dosagem"; sugere por prefixo sem acento', () {
      expect(infoDoMedicamento('Paracetamol 750 mg')?.nome, 'Paracetamol');
      expect(infoDoMedicamento('paracetamol')?.informacao, contains('antitérmico'));
      expect(infoDoMedicamento('AAS')?.nome, 'Ácido acetilsalicílico');
      expect(infoDoMedicamento('Dorflex')?.nome, 'Dipirona');
      expect(infoDoMedicamento('Remédio Inventado'), isNull);
      expect(infoDoMedicamento('Pa'), isNull);
      expect(sugerirMedicamentos('P'), isEmpty);
      expect(sugerirMedicamentos('parac').map((m) => m.nome), contains('Paracetamol'));
      expect(sugerirMedicamentos('acido').map((m) => m.nome), containsAll(['Ácido acetilsalicílico', 'Ácido fólico']));
      expect(sugerirMedicamentos('a').length, 0);
      final nomes = catalogoMedicamentos.map((m) => m.nome).toList();
      expect(nomes.toSet().length, nomes.length); // sem repetidos
      expect(catalogoMedicamentos.every((m) => m.informacao.length > 20), isTrue);
    });

    test('grava e atualiza tipo, fabricante, validade, posologia e informacoes', () async {
      final b = _novoBanco();
      final id = await b.inserirMedicamento(
        nome: 'Losartana',
        dose: '50 mg',
        horarios: '08:00',
        tipoMedicamento: 'generico',
        fabricante: 'EMS',
        validade: DateTime(2027, 3, 31),
        posologia: '1 comprimido pela manhã',
        informacoes: 'Anti-hipertensivo.',
      );
      var m = (await b.medicamentoPorId(id))!;
      expect([m.tipoMedicamento, m.fabricante, m.posologia, m.informacoes], ['generico', 'EMS', '1 comprimido pela manhã', 'Anti-hipertensivo.']);
      expect(m.validade, DateTime(2027, 3, 31));
      await b.atualizarMedicamento(id,
          nome: 'Losartana',
          dose: '50 mg',
          horarios: '08:00',
          formato: 'comprimido',
          quantidade: 1,
          frequencia: 'diaria',
          diasSemana: '',
          intervaloDias: 1,
          inicio: DateTime(2026, 10, 1),
          lembreteReabastecer: true,
          tipoMedicamento: 'referencia',
          fabricante: 'Merck');
      m = (await b.medicamentoPorId(id))!;
      expect(m.tipoMedicamento, 'referencia');
      expect(m.fabricante, 'Merck');
      expect(m.validade, isNull);
      expect(m.posologia, isNull);
    });

    test('validade: vencido, vence em ate 30 dias, ok e sem validade', () async {
      final b = _novoBanco();
      Future<Medicamento> com(DateTime? v) async {
        final id = await b.inserirMedicamento(nome: 'X', dose: '1', horarios: '08:00', validade: v);
        return (await b.medicamentoPorId(id))!;
      }

      final hoje = DateTime(2026, 10, 28, 15);
      final vencido = await com(DateTime(2026, 10, 20));
      expect(situacaoValidade(vencido, hoje), 'vencido');
      expect(diasParaVencer(vencido, hoje), -8);
      final hojeVence = await com(DateTime(2026, 10, 28));
      expect(situacaoValidade(hojeVence, hoje), 'vence_logo'); // vale ate o fim do dia
      expect(diasParaVencer(hojeVence, hoje), 0);
      expect(situacaoValidade(await com(DateTime(2026, 11, 27)), hoje), 'vence_logo'); // 30 dias
      expect(situacaoValidade(await com(DateTime(2026, 11, 28)), hoje), 'ok'); // 31 dias
      expect(situacaoValidade(await com(null), hoje), isNull);
    });

    testWidgets('formulario: nome conhecido preenche a informacao; sugestao; salva classificacao, fabricante e posologia', (tester) async {
      tester.view.physicalSize = const Size(900, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      await tester.pumpWidget(_app(
          banco,
          Scaffold(
              body: Builder(
                  builder: (c) => TextButton(
                      onPressed: () => abrirFormularioMedicamento(c, hoje: DateTime(2026, 10, 28)), child: const Text('abrir'))))));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('campo_nome_med')), 'Parac');
      await tester.pump();
      expect(find.byKey(const Key('sugestao_med_0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sugestao_med_0')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(find.byKey(const Key('campo_nome_med'))).controller!.text, 'Paracetamol');
      expect(tester.widget<TextFormField>(find.byKey(const Key('campo_informacoes_med'))).controller!.text, contains('Analgésico e antitérmico'));
      expect(find.text(avisoInformacao), findsOneWidget);

      await tester.enterText(find.byKey(const Key('campo_dose_med')), '750 mg');
      await tester.tap(find.byKey(const Key('campo_tipo_medicamento')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Genérico').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_fabricante_med')), 'EMS');
      await tester.enterText(find.byKey(const Key('campo_posologia_med')), '1 comprimido de 8 em 8 horas, por 7 dias');
      await tester.tap(find.byKey(const Key('botao_salvar_med')));
      await tester.pumpAndSettle();

      final m = (await banco.listarMedicamentos()).single;
      expect(m.nome, 'Paracetamol');
      expect(m.tipoMedicamento, 'generico');
      expect(m.fabricante, 'EMS');
      expect(m.posologia, '1 comprimido de 8 em 8 horas, por 7 dias');
      expect(m.informacoes, contains('Analgésico e antitérmico'));
      await encerrar(tester);
    });

    testWidgets('informacao escrita pela pessoa nao e apagada ao mudar o nome', (tester) async {
      tester.view.physicalSize = const Size(900, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      await tester.pumpWidget(_app(
          banco,
          Scaffold(
              body: Builder(
                  builder: (c) => TextButton(
                      onPressed: () => abrirFormularioMedicamento(c, hoje: DateTime(2026, 10, 28)), child: const Text('abrir'))))));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_informacoes_med')), 'Anotação minha');
      await tester.enterText(find.byKey(const Key('campo_nome_med')), 'Paracetamol');
      await tester.pump();
      expect(tester.widget<TextFormField>(find.byKey(const Key('campo_informacoes_med'))).controller!.text, 'Anotação minha');
      await encerrar(tester);
    });

    testWidgets('lista mostra classificacao, fabricante, posologia e alerta de validade', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banco = _novoBanco();
      final vencido = await banco.inserirMedicamento(
        nome: 'Antigo',
        dose: '10 mg',
        horarios: '08:00',
        tipoMedicamento: 'similar',
        fabricante: 'Medley',
        posologia: '1 ao dia',
        validade: DateTime(2026, 10, 20),
      );
      final logo = await banco.inserirMedicamento(nome: 'Quase', dose: '5 mg', horarios: '09:00', validade: DateTime(2026, 11, 10));
      final ok = await banco.inserirMedicamento(nome: 'Novo', dose: '5 mg', horarios: '10:00', validade: DateTime(2027, 6, 1));
      await tester.pumpWidget(_app(banco, Scaffold(body: MedicacaoAba(agora: DateTime(2026, 10, 28, 9)))));
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(Key('validade_$vencido'))).data, 'VENCIDO em 20/10/2026');
      expect(tester.widget<Text>(find.byKey(Key('validade_$logo'))).data, 'Vence em 13 dias (10/11/2026)');
      expect(tester.widget<Text>(find.byKey(Key('validade_$ok'))).data, 'Validade: 01/06/2027');
      expect(find.textContaining('Similar · Medley'), findsOneWidget);
      expect(find.textContaining('Posologia: 1 ao dia'), findsOneWidget);
      await encerrar(tester);
    });
  });
}
