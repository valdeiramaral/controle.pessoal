import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Lembretes locais: disparam no aparelho, sem depender de internet.
class ServicoNotificacoes {
  ServicoNotificacoes._();
  static final ServicoNotificacoes instancia = ServicoNotificacoes._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const NotificationDetails _detalhes = NotificationDetails(
    android: AndroidNotificationDetails(
      'lembretes',
      'Lembretes',
      channelDescription: 'Compromissos, consultas, remedios e contas',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> iniciar() async {
    tzdata.initializeTimeZones();
    // TODO: ler o fuso do aparelho (pacote flutter_timezone) em vez de fixar.
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

    const config = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(config);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Id numerico estavel a partir do UUID do registro.
  ///
  /// Nao usa String.hashCode: o Dart nao garante o mesmo valor entre versoes,
  /// e o app nao acharia mais a notificacao para cancelar depois de uma
  /// atualizacao. Este hash (polinomial, 31 bits) e fixo para sempre.
  static int idNumerico(String uuid, {int salto = 0}) {
    var h = 7;
    for (final c in uuid.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return (h + salto) & 0x7fffffff;
  }

  /// Notificacao unica (compromisso, consulta, conta a vencer).
  Future<void> agendar({
    required int id,
    required String titulo,
    required String corpo,
    required DateTime quando,
  }) async {
    if (!quando.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id,
      titulo,
      corpo,
      tz.TZDateTime.from(quando, tz.local),
      _detalhes,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Notificacao que se repete todo dia no mesmo horario (remedios).
  Future<void> agendarDiaria({
    required int id,
    required String titulo,
    required String corpo,
    required int hora,
    required int minuto,
  }) async {
    final agora = tz.TZDateTime.now(tz.local);
    var proxima =
        tz.TZDateTime(tz.local, agora.year, agora.month, agora.day, hora, minuto);
    if (!proxima.isAfter(agora)) proxima = proxima.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id,
      titulo,
      corpo,
      proxima,
      _detalhes,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelar(int id) => _plugin.cancel(id);
}
