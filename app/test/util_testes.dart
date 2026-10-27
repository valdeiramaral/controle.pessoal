import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desmonta a arvore e deixa rodar o timer de limpeza do Drift (Timer.run), para o teste nao
/// terminar com "Pending timers" quando ha StreamBuilder ligado ao banco.
Future<void> encerrar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}
