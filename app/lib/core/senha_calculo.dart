import 'dart:math';

import 'package:flutter/material.dart';

import '../data/local/banco.dart';

/// Categorias do cofre (como no menu da esquerda).
const tiposSenha = {
  'acesso': 'Acessos e senhas',
  'cartao': 'Cartões de crédito',
  'nota': 'Notas',
  '2fa': 'Senhas de uso único (2FA)',
  'chave': 'Chaves de acesso',
};

const iconesTipoSenha = {
  'acesso': Icons.lock_outline,
  'cartao': Icons.credit_card,
  'nota': Icons.sticky_note_2_outlined,
  '2fa': Icons.pin_outlined,
  'chave': Icons.vpn_key_outlined,
};

/// Nome do campo "segredo" conforme a categoria.
String rotuloSegredo(String tipo) => switch (tipo) {
      'cartao' => 'Número do cartão',
      '2fa' => 'Chave secreta (2FA)',
      'chave' => 'Chave de acesso',
      _ => 'Dado secreto',
    };

/// Forca da senha: nivel de 0 (vazia) a 4 e o "tempo para quebrar" estimado.
class ForcaSenha {
  const ForcaSenha(this.nivel, this.tempo);
  final int nivel;
  final String tempo;
}

const _tentativasPorSegundo = 1e10;

ForcaSenha avaliarSenha(String s) {
  if (s.isEmpty) return const ForcaSenha(0, '');
  var pool = 0;
  if (RegExp('[a-z]').hasMatch(s)) pool += 26;
  if (RegExp('[A-Z]').hasMatch(s)) pool += 26;
  if (RegExp('[0-9]').hasMatch(s)) pool += 10;
  if (RegExp('[^a-zA-Z0-9]').hasMatch(s)) pool += 33;
  // caracteres repetidos valem pouco
  final unicos = s.split('').toSet().length;
  final tamanhoEfetivo = unicos + (s.length - unicos) * 0.3;
  final bits = tamanhoEfetivo * (log(pool) / ln2);
  final segundos = pow(2, bits - 1) / _tentativasPorSegundo;
  final nivel = bits < 30 ? 1 : (bits < 45 ? 2 : (bits < 60 ? 3 : 4));
  return ForcaSenha(nivel, formatarTempoParaQuebrar(segundos.toDouble()));
}

String formatarTempoParaQuebrar(double s) {
  String n(double v, String um, String varios) {
    final i = v.floor();
    return '$i ${i == 1 ? um : varios}';
  }

  if (s < 1) return 'instantânea';
  if (s < 60) return n(s, 'segundo', 'segundos');
  if (s < 3600) return n(s / 60, 'minuto', 'minutos');
  if (s < 86400) return n(s / 3600, 'hora', 'horas');
  if (s < 86400 * 30) return n(s / 86400, 'dia', 'dias');
  if (s < 86400 * 365) return n(s / (86400 * 30), 'mês', 'meses');
  if (s < 86400 * 365 * 100) return n(s / (86400 * 365), 'ano', 'anos');
  return 'séculos';
}

Color corDaForca(int nivel) => switch (nivel) {
      1 => const Color(0xFFE53935),
      2 => const Color(0xFFFB8C00),
      3 => const Color(0xFFC0CA33),
      4 => const Color(0xFF43A047),
      _ => const Color(0xFF9E9E9E),
    };

/// Gera uma senha aleatoria com pelo menos um caractere de cada grupo escolhido.
String gerarSenha({
  int tamanho = 16,
  bool maiusculas = true,
  bool minusculas = true,
  bool numeros = true,
  bool simbolos = true,
  Random? random,
}) {
  final r = random ?? Random.secure();
  final grupos = <String>[
    if (minusculas) 'abcdefghijklmnopqrstuvwxyz',
    if (maiusculas) 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    if (numeros) '0123456789',
    if (simbolos) r'!@#$%&*?-_+=',
  ];
  if (grupos.isEmpty) grupos.add('abcdefghijklmnopqrstuvwxyz');
  final n = max(tamanho, grupos.length);
  final todos = grupos.join();
  final chars = <String>[for (final g in grupos) g[r.nextInt(g.length)]];
  while (chars.length < n) {
    chars.add(todos[r.nextInt(todos.length)]);
  }
  chars.shuffle(r);
  return chars.join();
}

// ---- filtros do painel ----

/// Filtros: 'todos', 'favoritos', 'recentes', 'tipo:<codigo>' e 'tag:<etiqueta>'.
const filtroTodos = 'todos';
const filtroFavoritos = 'favoritos';
const filtroRecentes = 'recentes';
String filtroTipo(String t) => 'tipo:$t';
String filtroTag(String t) => 'tag:$t';

/// "Recentes": abertos nos ultimos 7 dias.
const diasRecentes = 7;

List<String> tagsDaCredencial(Credencial c) => c.tags.isEmpty ? const [] : c.tags.split(',');

bool confereFiltro(Credencial c, String filtro, DateTime agora) {
  if (filtro == filtroTodos) return true;
  if (filtro == filtroFavoritos) return c.favorito;
  if (filtro == filtroRecentes) {
    return c.acessadoEm != null && agora.difference(c.acessadoEm!).inDays < diasRecentes;
  }
  if (filtro.startsWith('tipo:')) return c.tipo == filtro.substring(5);
  if (filtro.startsWith('tag:')) return tagsDaCredencial(c).contains(filtro.substring(4));
  return true;
}

String _semAcento(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  var t = s.toLowerCase();
  for (var i = 0; i < de.length; i++) {
    t = t.replaceAll(de[i], para[i]);
  }
  return t;
}

/// A busca olha titulo, aplicativo, e-mail, usuario, endereco e etiquetas (nunca os campos cifrados).
bool confereBusca(Credencial c, String busca) {
  if (busca.trim().isEmpty) return true;
  final q = _semAcento(busca.trim());
  return [c.titulo, c.aplicativo, c.email, c.usuario, c.url, c.tags].any((v) => _semAcento(v ?? '').contains(q));
}

/// Ordens: 'nome', 'modificado' (mais recente primeiro) e 'criado' (mais recente primeiro).
List<Credencial> ordenarCredenciais(List<Credencial> lista, String ordem) {
  final l = [...lista];
  switch (ordem) {
    case 'modificado':
      l.sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
    case 'criado':
      l.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    default:
      l.sort((a, b) => _semAcento(a.titulo).compareTo(_semAcento(b.titulo)));
  }
  return l;
}

/// Contagem de cada item do menu lateral (para os numeros ao lado do nome).
Map<String, int> contagensDoCofre(List<Credencial> lista, DateTime agora) {
  final m = <String, int>{
    filtroTodos: lista.length,
    filtroFavoritos: lista.where((c) => c.favorito).length,
    filtroRecentes: lista.where((c) => confereFiltro(c, filtroRecentes, agora)).length,
    for (final t in tiposSenha.keys) filtroTipo(t): lista.where((c) => c.tipo == t).length,
  };
  for (final c in lista) {
    for (final t in tagsDaCredencial(c)) {
      m[filtroTag(t)] = (m[filtroTag(t)] ?? 0) + 1;
    }
  }
  return m;
}

/// Etiquetas usadas, em ordem alfabetica.
List<String> etiquetasDoCofre(List<Credencial> lista) =>
    {for (final c in lista) ...tagsDaCredencial(c)}.toList()..sort();
