import 'package:controle_pessoal/data/local/banco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cada usuario tem um arquivo de banco proprio', () {
    final a = nomeSeguro('11111111-aaaa-bbbb-cccc-000000000001');
    final b = nomeSeguro('22222222-aaaa-bbbb-cccc-000000000002');
    expect(a, isNot(b));
    expect(a, matches(RegExp(r'^[A-Za-z0-9_]+$')));
    expect(nomeSeguro(null), 'sem_login');
    expect(nomeSeguro(''), 'sem_login');
    expect(nomeSeguro('../x/y'), '___x_y');
  });
}
