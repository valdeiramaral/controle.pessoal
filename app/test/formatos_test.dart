import 'package:flutter_test/flutter_test.dart';

import 'package:controle_pessoal/core/formatos.dart';
import 'package:controle_pessoal/core/notificacoes.dart';

void main() {
  group('centavosDeTexto', () {
    test('formatos comuns no Brasil', () {
      expect(centavosDeTexto('12,50'), 1250);
      expect(centavosDeTexto('1.234,50'), 123450);
      expect(centavosDeTexto('0,5'), 50);
      expect(centavosDeTexto('7'), 700);
      expect(centavosDeTexto('R\$ 5'), 500);
      expect(centavosDeTexto(' 12,5 '), 1250);
    });

    test('ponto como milhar (1.234 = mil duzentos e trinta e quatro)', () {
      expect(centavosDeTexto('1.234'), 123400);
      expect(centavosDeTexto('12.345.678'), 1234567800);
    });

    test('ponto como decimal', () {
      expect(centavosDeTexto('12.50'), 1250);
      expect(centavosDeTexto('0.5'), 50);
    });

    test('sem erro de arredondamento', () {
      expect(centavosDeTexto('1,005'), isNull); // 3 casas: invalido
      expect(centavosDeTexto('19,99'), 1999);
      expect(centavosDeTexto('0,29'), 29);
    });

    test('entradas invalidas', () {
      for (final t in ['', 'abc', '-5', '1,2,3', '1,5a', ',', 'R\$']) {
        expect(centavosDeTexto(t), isNull, reason: 'entrada "\$t"');
      }
    });
  });

  group('idNumerico (id de notificacao)', () {
    const uuid = '3f2c1a9e-8b7d-4c6e-9a10-5d4e3f2a1b0c';

    test('e estavel: mesmo valor sempre (valor fixado, nao depende do Dart)', () {
      // ((7*31 + 'a') * 31 + 'b') * 31 + 'c'
      expect(ServicoNotificacoes.idNumerico('abc'), 304891);
      expect(ServicoNotificacoes.idNumerico('a'), 314);
    });

    test('cabe em 31 bits e o salto gera ids diferentes', () {
      final a = ServicoNotificacoes.idNumerico(uuid);
      final b = ServicoNotificacoes.idNumerico(uuid, salto: 1);
      expect(a, inInclusiveRange(0, 0x7fffffff));
      expect(b, a + 1);
    });
  });
}
