import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/cliente_api.dart';

/// O que o aparelho guarda para abrir o app sem internet: so uma verificacao
/// (PBKDF2) da senha, nunca a senha, mais os dados e permissoes da conta.
class AcessoOffline {
  const AcessoOffline({required this.usuario, required this.perfil});

  final UsuarioApi usuario;
  final PerfilApi? perfil;
}

abstract class CofreOffline {
  /// Guarda (ou troca) a verificacao da senha deste e-mail, junto com a conta e o perfil.
  Future<void> guardar(String email, String senha, UsuarioApi usuario, PerfilApi? perfil);

  /// Confere e-mail e senha no aparelho. Nulo se nao houver registro ou a senha nao bater.
  Future<AcessoOffline?> verificar(String email, String senha);

  /// Ha registro para este e-mail? (para diferenciar "senha errada" de "nunca entrou aqui")
  Future<bool> existe(String email);
}

String _chaveEmail(String email) => email.trim().toLowerCase();

Future<List<int>> _derivar(String senha, List<int> sal, int iteracoes) async {
  final k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iteracoes, bits: 256)
      .deriveKeyFromPassword(password: senha, nonce: sal);
  return k.extractBytes();
}

bool _iguais(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a[i] ^ b[i];
  }
  return r == 0;
}

/// Registros por e-mail, em JSON. Subclasses so dizem onde o texto fica guardado.
abstract class _CofreEmTexto implements CofreOffline {
  /// Iteracoes do PBKDF2 (os testes podem baixar).
  static int iteracoes = 60000;

  Future<String?> lerTexto();
  Future<void> gravarTexto(String texto);

  Future<Map<String, dynamic>> _todos() async {
    try {
      final t = await lerTexto();
      if (t == null) return {};
      return (jsonDecode(t) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> guardar(String email, String senha, UsuarioApi usuario, PerfilApi? perfil) async {
    try {
      final r = Random.secure();
      final sal = List<int>.generate(16, (_) => r.nextInt(256));
      final hash = await _derivar(senha, sal, iteracoes);
      final todos = await _todos();
      todos[_chaveEmail(email)] = {
        'sal': base64Encode(sal),
        'hash': base64Encode(hash),
        'iteracoes': iteracoes,
        'usuario': usuario.paraJson(),
        'perfil': perfil?.paraJson(),
      };
      await gravarTexto(jsonEncode(todos));
    } catch (_) {}
  }

  @override
  Future<bool> existe(String email) async => (await _todos()).containsKey(_chaveEmail(email));

  @override
  Future<AcessoOffline?> verificar(String email, String senha) async {
    try {
      final j = (await _todos())[_chaveEmail(email)] as Map<String, dynamic>?;
      if (j == null) return null;
      final calc = await _derivar(senha, base64Decode(j['sal'] as String), (j['iteracoes'] as num).toInt());
      if (!_iguais(calc, base64Decode(j['hash'] as String))) return null;
      final p = j['perfil'];
      return AcessoOffline(
        usuario: UsuarioApi.deJson((j['usuario'] as Map).cast<String, dynamic>()),
        perfil: p is Map ? PerfilApi.deJson(p.cast<String, dynamic>()) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Keystore (Android) / Keychain (iOS). Na web fora de HTTPS o cofre falha e o acesso offline simplesmente nao existe.
class CofreOfflineSeguro extends _CofreEmTexto {
  CofreOfflineSeguro([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();

  static const _chave = 'acesso_offline_v1';
  final FlutterSecureStorage _s;

  @override
  Future<String?> lerTexto() => _s.read(key: _chave);

  @override
  Future<void> gravarTexto(String texto) => _s.write(key: _chave, value: texto);
}

/// Para testes.
class CofreOfflineMemoria extends _CofreEmTexto {
  String? texto;

  @override
  Future<String?> lerTexto() async => texto;

  @override
  Future<void> gravarTexto(String t) async => texto = t;
}

/// Teste: baixa o custo do PBKDF2.
void iteracoesOfflineParaTeste(int n) => _CofreEmTexto.iteracoes = n;
