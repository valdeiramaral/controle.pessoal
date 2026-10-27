import 'documentos.dart';

/// Validacoes do cadastro de contas bancarias. Cada funcao devolve a mensagem de erro, ou null se valido.

/// Agencia: 1 a 5 digitos, com digito verificador opcional ("4544" ou "1234-5").
String? validarAgencia(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Informe a agência';
  if (!RegExp(r'^\d{1,5}(-[0-9xX])?$').hasMatch(t)) return 'Agência inválida (ex.: 4444 ou 4444-1)';
  return null;
}

/// Numero da conta: 1 a 12 digitos, com digito verificador opcional ("18882982" ou "12345-6").
String? validarNumeroConta(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Informe o número da conta';
  if (!RegExp(r'^\d{1,12}(-[0-9xX])?$').hasMatch(t)) return 'Número da conta inválido (ex.: 123456-7)';
  return null;
}

/// CPF/CNPJ opcional: vazio e valido; se preenchido precisa ser um CPF ou CNPJ correto.
String? validarDocumentoOpcional(String? v) {
  if (soDigitos(v).isEmpty) return null;
  return cpfOuCnpjValido(v) ? null : 'CPF/CNPJ inválido';
}

/// Chave PIX opcional: CPF/CNPJ, celular (+55...), e-mail ou chave aleatoria (UUID).
String? validarChavePixOpcional(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return null;
  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) && t.length <= 77 ||
      RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(t) ||
      cpfOuCnpjValido(t) ||
      RegExp(r'^\+?55\d{10,11}$').hasMatch(t.replaceAll(RegExp(r'[\s()-]'), '')) ||
      RegExp(r'^\(?\d{2}\)?\s?9?\d{4}-?\d{4}$').hasMatch(t);
  return ok ? null : 'Chave PIX inválida (CPF/CNPJ, celular, e-mail ou chave aleatória)';
}
