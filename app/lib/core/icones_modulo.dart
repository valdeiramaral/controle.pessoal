import 'package:flutter/material.dart';

/// Icones (contorno, minimalistas) que o administrador pode dar a um modulo.
/// A chave e o que a API guarda; deve ficar igual a lista ICONES da API.
const iconesModulo = <String, IconData>{
  'extension': Icons.extension_outlined,
  'folder': Icons.folder_outlined,
  'star': Icons.star_border,
  'work': Icons.work_outline,
  'school': Icons.school_outlined,
  'cart': Icons.shopping_cart_outlined,
  'home': Icons.home_outlined,
  'fitness': Icons.fitness_center_outlined,
  'pets': Icons.pets_outlined,
  'flight': Icons.flight_outlined,
  'book': Icons.menu_book_outlined,
  'build': Icons.build_outlined,
  'chart': Icons.bar_chart_outlined,
  'people': Icons.people_outline,
  'wallet': Icons.account_balance_wallet_outlined,
};

IconData iconeDoModulo(String? chave) => iconesModulo[chave] ?? Icons.extension_outlined;

/// Cor de cada icone de modulo (os icones do app sao coloridos).
const coresModulo = <String, MaterialColor>{
  'extension': Colors.deepPurple,
  'folder': Colors.amber,
  'star': Colors.orange,
  'work': Colors.brown,
  'school': Colors.indigo,
  'cart': Colors.pink,
  'home': Colors.teal,
  'fitness': Colors.red,
  'pets': Colors.deepOrange,
  'flight': Colors.lightBlue,
  'book': Colors.green,
  'build': Colors.blueGrey,
  'chart': Colors.cyan,
  'people': Colors.purple,
  'wallet': Colors.lightGreen,
};

MaterialColor corBaseDoModulo(String? chave) => coresModulo[chave] ?? Colors.deepPurple;
