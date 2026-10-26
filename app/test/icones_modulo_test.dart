import 'dart:io';

import 'package:controle_pessoal/core/icones_modulo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalogo de icones: chaves unicas, mais de 80 opcoes e as antigas continuam existindo', () {
    final chaves = [for (final c in categoriasIcones) for (final i in c.icones) i.chave];
    expect(chaves.toSet().length, chaves.length);
    expect(chaves.length, greaterThan(80));
    for (final antiga in ['extension', 'folder', 'star', 'work', 'school', 'cart', 'home', 'fitness', 'pets', 'flight', 'book', 'build', 'chart', 'people', 'wallet']) {
      expect(iconesModulo.containsKey(antiga), isTrue, reason: antiga);
    }
  });

  test('a lista da API (modulos.js) tem as mesmas chaves do app', () {
    final f = File('../api/src/rotas/modulos.js');
    if (!f.existsSync()) return; // rodando fora da pasta do projeto
    final texto = f.readAsStringSync();
    final bloco = RegExp(r'export const ICONES = \[(.*?)\];', dotAll: true).firstMatch(texto)!.group(1)!;
    final api = RegExp(r"'([a-z_]+)'").allMatches(bloco).map((m) => m.group(1)!).toSet();
    final app = iconesModulo.keys.toSet();
    expect(api, app);
  });
}
