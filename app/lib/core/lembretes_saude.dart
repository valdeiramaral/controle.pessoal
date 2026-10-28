import '../data/local/banco.dart';
import 'formatos.dart';
import 'notificacoes.dart';
import 'saude_calculo.dart';

/// Lembretes locais do modulo Saude (remedios e consultas/exames).
/// Sem ServicoNotificacoes.iniciar() (testes, web) nada e agendado.
class LembretesSaude {
  LembretesSaude._();

  static final _n = ServicoNotificacoes.instancia;

  /// Cada horario usa uma faixa de 100 ids: +0 diario, +1..7 dia da semana, +0..29 proximas doses (intervalo).
  static int _id(Medicamento m, int horario, int k) => ServicoNotificacoes.idNumerico(m.id, salto: horario * 100 + k);

  /// Dias a frente para os quais agenda doses avulsas (medicamentos "a cada N dias").
  static const _doses = 30;

  static Future<void> agendarMedicamento(Medicamento m) async {
    if (!m.ativo) return;
    final horas = lerHorarios(m.horarios);
    final corpo = '${m.nome} · ${m.dose} · ${descricaoQuantidade(m.formato, m.quantidade)}';
    for (var i = 0; i < horas.length; i++) {
      final (h, min) = horas[i];
      switch (m.frequencia) {
        case 'diaria':
          if (m.fim == null) {
            await _n.agendarDiaria(id: _id(m, i, 0), titulo: 'Hora do remédio', corpo: corpo, hora: h, minuto: min);
          } else {
            await _avulsas(m, i, h, min, corpo);
          }
        case 'dias_semana':
          if (m.fim == null) {
            for (final d in lerDiasSemana(m.diasSemana)) {
              await _n.agendarSemanal(id: _id(m, i, d), titulo: 'Hora do remédio', corpo: corpo, diaSemana: d, hora: h, minuto: min);
            }
          } else {
            await _avulsas(m, i, h, min, corpo);
          }
        case 'intervalo':
          await _avulsas(m, i, h, min, corpo);
      }
    }
  }

  /// Agenda as proximas doses uma a uma (tratamentos com data final ou a cada N dias).
  static Future<void> _avulsas(Medicamento m, int i, int h, int min, String corpo) async {
    final hoje = soDia(DateTime.now());
    var k = 0;
    for (var d = 0; d < 400 && k < _doses; d++) {
      final dia = hoje.add(Duration(days: d));
      if (!tomaNoDia(m, dia)) continue;
      final quando = DateTime(dia.year, dia.month, dia.day, h, min);
      if (!quando.isAfter(DateTime.now())) continue;
      await _n.agendar(id: _id(m, i, k), titulo: 'Hora do remédio', corpo: corpo, quando: quando);
      k++;
    }
  }

  static Future<void> cancelarMedicamento(Medicamento m) async {
    final n = lerHorarios(m.horarios).length;
    for (var i = 0; i < n; i++) {
      await _n.cancelar(ServicoNotificacoes.idNumerico(m.id, salto: i)); // formato antigo (antes da v5)
      for (var k = 0; k < _doses; k++) {
        await _n.cancelar(_id(m, i, k));
      }
    }
  }

  /// Refaz os lembretes dos medicamentos em doses avulsas (renovam a janela de 30 doses).
  static Future<void> renovar(List<Medicamento> lista) async {
    for (final m in lista) {
      if (m.ativo && (m.frequencia == 'intervalo' || m.fim != null)) {
        await cancelarMedicamento(m);
        await agendarMedicamento(m);
      }
    }
  }

  static int _idAgendamento(AgendamentoSaude a) => ServicoNotificacoes.idNumerico(a.eventoId ?? a.id);

  static Future<void> agendarAgendamento(AgendamentoSaude a) async {
    await _n.cancelar(_idAgendamento(a));
    final min = a.lembreteMin;
    if (min == null || a.status != 'agendado') return;
    final onde = (a.local ?? '').isEmpty ? '' : ' · ${a.local}';
    await _n.agendar(
      id: _idAgendamento(a),
      titulo: tituloEventoSaude(a.tipo, a.titulo),
      corpo: '${formatarDataHora(a.dataHora)}$onde',
      quando: a.dataHora.subtract(Duration(minutes: min)),
    );
  }

  static Future<void> cancelarAgendamento(AgendamentoSaude a) => _n.cancelar(_idAgendamento(a));
}
