import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// O teste gerado pelo "flutter create" (contador / MyApp) nao se aplica a este
// app e quebraria o "flutter test". Os testes reais ficam em banco_test.dart,
// saldo_test.dart e formatos_test.dart. Este e so uma verificacao basica de
// que o Flutter renderiza widgets no ambiente de teste.
void main() {
  testWidgets('renderiza um widget basico', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Controle Pessoal'))));
    expect(find.text('Controle Pessoal'), findsOneWidget);
  });
}
