import 'package:flutter/services.dart';

/// CPF, telefone, CEP e datas: limpeza, validacao e mascaras de digitacao.

String soDigitos(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

/// CPF com 11 digitos, digitos verificadores corretos e sem sequencia repetida.
bool cpfValido(String? texto) {
  final c = soDigitos(texto);
  if (c.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(c)) return false;
  int dv(int n) {
    var s = 0;
    for (var i = 0; i < n; i++) {
      s += int.parse(c[i]) * (n + 1 - i);
    }
    final r = (s * 10) % 11;
    return r == 10 ? 0 : r;
  }

  return dv(9) == int.parse(c[9]) && dv(10) == int.parse(c[10]);
}

/// CNPJ com 14 digitos, digitos verificadores corretos e sem sequencia repetida.
bool cnpjValido(String? texto) {
  final c = soDigitos(texto);
  if (c.length != 14 || RegExp(r'^(\d)\1{13}$').hasMatch(c)) return false;
  int dv(int n) {
    const pesos = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    var s = 0;
    for (var i = 0; i < n; i++) {
      s += int.parse(c[i]) * pesos[13 - n + i];
    }
    final r = s % 11;
    return r < 2 ? 0 : 11 - r;
  }

  return dv(12) == int.parse(c[12]) && dv(13) == int.parse(c[13]);
}

/// CPF (11 digitos) ou CNPJ (14 digitos) valido.
bool cpfOuCnpjValido(String? texto) => cpfValido(texto) || cnpjValido(texto);

/// Aplica um molde: '#' recebe um digito, qualquer outro caractere e fixo.
/// Para quando acabam os digitos (nao completa com mascara vazia).
String aplicarMolde(String digitos, String molde) {
  final b = StringBuffer();
  var i = 0;
  for (final ch in molde.split('')) {
    if (i >= digitos.length) break;
    if (ch == '#') {
      b.write(digitos[i++]);
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

String formatarCpf(String? s) => aplicarMolde(soDigitos(s), '###.###.###-##');
String formatarCnpj(String? s) => aplicarMolde(soDigitos(s), '##.###.###/####-##');

/// Mostra como CPF (ate 11 digitos) ou CNPJ (mais de 11) enquanto o usuario digita.
String formatarCpfOuCnpj(String? s) {
  final d = soDigitos(s);
  return d.length > 11 ? formatarCnpj(d.length > 14 ? d.substring(0, 14) : d) : formatarCpf(d);
}

String formatarCep(String? s) => aplicarMolde(soDigitos(s), '#####-###');

/// (11) 98765-4321 (celular) ou (11) 3333-4444 (fixo). Acima de 11 digitos, so os 11 primeiros.
String formatarTelefone(String? s) {
  final d = soDigitos(s);
  final x = d.length > 11 ? d.substring(0, 11) : d;
  return aplicarMolde(x, x.length > 10 ? '(##) #####-####' : '(##) ####-####');
}

/// '2026-10-26' -> '26/10/2026'.
String isoParaDataBr(String? iso) {
  if (iso == null || iso.length < 10) return '';
  return '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';
}

/// '26/10/2026' -> '2026-10-26' (null se incompleta ou inexistente, como 31/02).
String? dataBrParaIso(String? br) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch((br ?? '').trim());
  if (m == null) return null;
  final d = int.parse(m[1]!), mes = int.parse(m[2]!), a = int.parse(m[3]!);
  final data = DateTime.utc(a, mes, d);
  if (data.year != a || data.month != mes || data.day != d) return null;
  return '${m[3]}-${m[2]}-${m[1]}';
}

/// Mascara de digitacao: o usuario digita so numeros e o campo mostra o formato.
class MascaraFormatter extends TextInputFormatter {
  MascaraFormatter(this.formatar);

  final String Function(String) formatar;

  static MascaraFormatter cpf() => MascaraFormatter(formatarCpf);
  static MascaraFormatter cpfOuCnpj() => MascaraFormatter(formatarCpfOuCnpj);
  static MascaraFormatter cep() => MascaraFormatter(formatarCep);
  static MascaraFormatter telefone() => MascaraFormatter(formatarTelefone);
  static MascaraFormatter data() =>
      MascaraFormatter((s) => aplicarMolde(soDigitos(s), '##/##/####'));

  @override
  TextEditingValue formatEditUpdate(TextEditingValue antigo, TextEditingValue novo) {
    final texto = formatar(novo.text);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
