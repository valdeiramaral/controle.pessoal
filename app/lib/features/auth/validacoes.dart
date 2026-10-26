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
