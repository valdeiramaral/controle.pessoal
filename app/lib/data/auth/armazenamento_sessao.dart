import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/cliente_api.dart';

/// O que fica guardado no aparelho entre uma abertura e outra do app.
class SessaoSalva {
  const SessaoSalva({
    this.token,
    this.expiraEm,
    this.usuario,
    this.local = false,
    this.emailLembrado,
    this.senhaLembrada,
  });

  final String? token;
  final DateTime? expiraEm;
  final UsuarioApi? usuario;

  /// true = o usuario escolheu usar o app sem conta (dados so neste aparelho).
  final bool local;

  /// "Lembrar de mim": e-mail preenchido na tela de login.
  final String? emailLembrado;

  /// "Lembrar de mim": senha guardada no cofre do aparelho para entrar sozinho
  /// quando o token vence. Nunca e guardada na web.
  final String? senhaLembrada;

  Map<String, dynamic> paraJson() => {
        'token': token,
        'expira_em': expiraEm?.toUtc().toIso8601String(),
        'usuario': usuario?.paraJson(),
        'local': local,
        'email_lembrado': emailLembrado,
        'senha_lembrada': senhaLembrada,
      };

  static SessaoSalva? deJson(String texto) {
    try {
      final j = jsonDecode(texto) as Map<String, dynamic>;
      final u = j['usuario'];
      return SessaoSalva(
        token: j['token'] as String?,
        expiraEm: DateTime.tryParse((j['expira_em'] as String?) ?? ''),
        usuario: u is Map<String, dynamic> ? UsuarioApi.deJson(u) : null,
        local: j['local'] == true,
        emailLembrado: j['email_lembrado'] as String?,
        senhaLembrada: j['senha_lembrada'] as String?,
      );
    } catch (_) {
      return null; // dado corrompido: trata como sem sessao
    }
  }
}

abstract class ArmazenamentoSessao {
  Future<SessaoSalva?> ler();
  Future<void> gravar(SessaoSalva sessao);
  Future<void> limpar();
}

/// Guarda no Keystore (Android) / Keychain (iOS).
class ArmazenamentoSeguro implements ArmazenamentoSessao {
  ArmazenamentoSeguro([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();

  static const _chave = 'sessao_v1';
  final FlutterSecureStorage _s;

  @override
  Future<SessaoSalva?> ler() async {
    final t = await _s.read(key: _chave);
    return t == null ? null : SessaoSalva.deJson(t);
  }

  @override
  Future<void> gravar(SessaoSalva sessao) => _s.write(key: _chave, value: jsonEncode(sessao.paraJson()));

  @override
  Future<void> limpar() => _s.delete(key: _chave);
}

/// Para testes.
class ArmazenamentoMemoria implements ArmazenamentoSessao {
  SessaoSalva? valor;

  @override
  Future<SessaoSalva?> ler() async => valor;

  @override
  Future<void> gravar(SessaoSalva sessao) async => valor = sessao;

  @override
  Future<void> limpar() async => valor = null;
}
