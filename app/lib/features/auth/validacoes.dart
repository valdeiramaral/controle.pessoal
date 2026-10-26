import '../../core/documentos.dart';

/// Validacoes dos formularios (mesmas regras da API). Devolvem o texto do erro ou null.
String? validarNome(String? v) {
  if (v == null || v.trim().isEmpty) return 'Informe seu nome.';
  if (v.trim().length > 120) return 'Nome muito longo.';
  return null;
}

final _padraoEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validarEmail(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Informe seu e-mail.';
  if (t.length > 254 || !_padraoEmail.hasMatch(t)) return 'E-mail inválido.';
  return null;
}

String? validarSenhaNova(String? v) {
  if (v == null || v.isEmpty) return 'Crie uma senha.';
  if (v.length < 8) return 'Use ao menos 8 caracteres.';
  if (v.length > 128) return 'Senha muito longa (máximo 128).';
  return null;
}

String? validarSenhaLogin(String? v) =>
    (v == null || v.isEmpty) ? 'Informe sua senha.' : null;

String? validarCpf(String? v) {
  if (v == null || v.trim().isEmpty) return 'Informe o CPF.';
  return cpfValido(v) ? null : 'CPF inválido.';
}

String? validarTelefone(String? v) {
  if (v == null || v.trim().isEmpty) return 'Informe o telefone.';
  final n = soDigitos(v).length;
  return (n >= 10 && n <= 11) ? null : 'Telefone inválido. Use DDD + número.';
}

/// Campos opcionais: vazio vale.
String? validarCepOpcional(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  return soDigitos(v).length == 8 ? null : 'CEP inválido.';
}

const ufsBrasil = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA',
  'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
];

String? validarUfOpcional(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  return ufsBrasil.contains(v.trim().toUpperCase()) ? null : 'UF inválida.';
}

String? validarNascimentoOpcional(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final iso = dataBrParaIso(v);
  if (iso == null) return 'Data inválida (dd/mm/aaaa).';
  final d = DateTime.parse(iso);
  if (d.isAfter(DateTime.now()) || d.year < 1900) return 'Data de nascimento inválida.';
  return null;
}
