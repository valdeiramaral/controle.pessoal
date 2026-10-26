import 'package:controle_pessoal/core/documentos.dart';
import 'package:controle_pessoal/features/auth/validacoes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _digitar(TextInputFormatter f, String texto) =>
    f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: texto));

void main() {
  group('CPF', () {
    test('aceita validos, com ou sem mascara', () {
      expect(cpfValido('52998224725'), isTrue);
      expect(cpfValido('529.982.247-25'), isTrue);
      expect(cpfValido('111.444.777-35'), isTrue);
    });
    test('recusa digito errado, sequencia repetida e tamanho errado', () {
      expect(cpfValido('52998224724'), isFalse);
      expect(cpfValido('11111111111'), isFalse);
      expect(cpfValido('1234'), isFalse);
      expect(cpfValido(''), isFalse);
      expect(cpfValido(null), isFalse);
    });
    test('formata e limpa', () {
      expect(formatarCpf('52998224725'), '529.982.247-25');
      expect(formatarCpf('5299'), '529.9');
      expect(soDigitos('529.982.247-25'), '52998224725');
    });
  });

  group('telefone e CEP', () {
    test('celular e fixo', () {
      expect(formatarTelefone('11987654321'), '(11) 98765-4321');
      expect(formatarTelefone('1133334444'), '(11) 3333-4444');
      expect(formatarTelefone('119'), '(11) 9');
      expect(formatarTelefone('11987654321999'), '(11) 98765-4321');
    });
    test('CEP', () {
      expect(formatarCep('01310100'), '01310-100');
      expect(formatarCep('0131'), '0131');
    });
  });

  group('datas', () {
    test('ISO para BR e de volta', () {
      expect(isoParaDataBr('1990-05-17'), '17/05/1990');
      expect(dataBrParaIso('17/05/1990'), '1990-05-17');
      expect(isoParaDataBr(null), '');
    });
    test('data inexistente ou incompleta vira nulo', () {
      expect(dataBrParaIso('31/02/2020'), isNull);
      expect(dataBrParaIso('17/05/19'), isNull);
      expect(dataBrParaIso(''), isNull);
    });
  });

  group('mascaras de digitacao', () {
    test('CPF, telefone, CEP e data', () {
      expect(_digitar(MascaraFormatter.cpf(), '52998224725').text, '529.982.247-25');
      expect(_digitar(MascaraFormatter.telefone(), '11987654321').text, '(11) 98765-4321');
      expect(_digitar(MascaraFormatter.cep(), '01310100').text, '01310-100');
      expect(_digitar(MascaraFormatter.data(), '17051990').text, '17/05/1990');
    });
    test('o cursor vai para o fim', () {
      final v = _digitar(MascaraFormatter.cpf(), '529982');
      expect(v.selection.baseOffset, v.text.length);
    });
  });

  group('validacoes dos formularios', () {
    test('CPF e telefone obrigatorios', () {
      expect(validarCpf(''), 'Informe o CPF.');
      expect(validarCpf('111.111.111-11'), 'CPF inválido.');
      expect(validarCpf('529.982.247-25'), isNull);
      expect(validarTelefone(''), 'Informe o telefone.');
      expect(validarTelefone('(11) 9876'), isNotNull);
      expect(validarTelefone('(11) 98765-4321'), isNull);
    });
    test('opcionais: vazio vale, preenchido errado nao', () {
      expect(validarCepOpcional(''), isNull);
      expect(validarCepOpcional('123'), isNotNull);
      expect(validarCepOpcional('01310-100'), isNull);
      expect(validarUfOpcional(''), isNull);
      expect(validarUfOpcional('xx'), isNotNull);
      expect(validarUfOpcional('sp'), isNull);
      expect(validarNascimentoOpcional(''), isNull);
      expect(validarNascimentoOpcional('31/02/2020'), isNotNull);
      expect(validarNascimentoOpcional('01/01/2999'), isNotNull);
      expect(validarNascimentoOpcional('17/05/1990'), isNull);
    });
  });
}
