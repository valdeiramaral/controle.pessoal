import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cifra e decifra os campos secretos do cofre de senhas (AES-256-GCM).
/// O banco guarda so o texto cifrado ("v1:" + nonce + texto + selo, em base64).
abstract class Cofre {
  Future<String> cifrar(String texto);

  /// Lanca [CofreIndisponivel] se o texto foi cifrado com outra chave ou foi alterado.
  Future<String> decifrar(String cifrado);
}

class CofreIndisponivel implements Exception {
  const CofreIndisponivel();
  @override
  String toString() => 'Não foi possível abrir o conteúdo cifrado (chave diferente ou dado alterado).';
}

class CofreAes implements Cofre {
  CofreAes(this._chave);

  /// Entrega os 32 bytes da chave do aparelho.
  final Future<List<int>> Function() _chave;
  static const prefixo = 'v1:';
  static const _tamNonce = 12;
  static const _tamSelo = 16;
  final _algo = AesGcm.with256bits();

  @override
  Future<String> cifrar(String texto) async {
    if (texto.isEmpty) return '';
    final caixa = await _algo.encrypt(utf8.encode(texto), secretKey: SecretKey(await _chave()));
    return '$prefixo${base64Encode(caixa.concatenation())}';
  }

  @override
  Future<String> decifrar(String cifrado) async {
    if (cifrado.isEmpty) return '';
    if (!cifrado.startsWith(prefixo)) throw const CofreIndisponivel();
    try {
      final caixa = SecretBox.fromConcatenation(base64Decode(cifrado.substring(prefixo.length)),
          nonceLength: _tamNonce, macLength: _tamSelo);
      return utf8.decode(await _algo.decrypt(caixa, secretKey: SecretKey(await _chave())));
    } on CofreIndisponivel {
      rethrow;
    } catch (_) {
      throw const CofreIndisponivel();
    }
  }
}

/// Chave aleatoria do aparelho, criada na primeira vez e guardada no Keystore (Android) / Keychain (iOS).
Future<List<int>> chaveDoAparelho([FlutterSecureStorage? armazenamento]) async {
  final s = armazenamento ?? const FlutterSecureStorage();
  const nome = 'cofre_chave_v1';
  final atual = await s.read(key: nome);
  if (atual != null) return base64Decode(atual);
  final r = Random.secure();
  final nova = List<int>.generate(32, (_) => r.nextInt(256));
  await s.write(key: nome, value: base64Encode(nova));
  return nova;
}

/// Trocavel nos testes (chave fixa, sem Keystore).
final cofreProvider = Provider<Cofre>((ref) => CofreAes(chaveDoAparelho));
