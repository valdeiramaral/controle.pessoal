import 'dart:async';

import 'package:controle_pessoal/features/sync/sincronizacao.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Roda uma vez por arquivo de teste: carrega os dados de data/hora em portugues (como o main.dart faz).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeDateFormatting('pt_BR');
  // Sem timers de fundo nos testes (eles falhariam com "Timer pendente"); os testes chamam sincronizar().
  SincronizacaoNotifier.automatica = false;
  await testMain();
}
