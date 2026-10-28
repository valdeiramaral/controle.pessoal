import 'package:flutter/material.dart';

import '../data/local/banco.dart';

/// Formatos do livro na ficha de leitura.
const formatosLivro = {'fisico': 'Físico', 'digital': 'Digital'};

/// Nota maxima de cada tema (bolinhas, estrelas, coracoes, triangulos).
const notaMaximaTema = 5;

/// Temas abordados: cada um tem o seu simbolo (como na ficha de papel).
class TemaLeitura {
  const TemaLeitura(this.codigo, this.nome, this.cheio, this.vazio);
  final String codigo;
  final String nome;
  final IconData cheio;
  final IconData vazio;
}

const temasLeitura = <TemaLeitura>[
  TemaLeitura('drama', 'Drama', Icons.circle, Icons.circle_outlined),
  TemaLeitura('fantasia', 'Fantasia', Icons.star, Icons.star_border),
  TemaLeitura('romance', 'Romance', Icons.favorite, Icons.favorite_border),
  TemaLeitura('reflexao', 'Reflexão', Icons.change_history, Icons.change_history_outlined),
];

int notaDoTema(Leitura l, String tema) => switch (tema) {
      'drama' => l.notaDrama,
      'fantasia' => l.notaFantasia,
      'romance' => l.notaRomance,
      _ => l.notaReflexao,
    };

/// Tocar no simbolo [n] marca de 1 a n; tocar de novo no que ja e a nota zera.
int novaNota(int atual, int n) => atual == n ? 0 : n.clamp(0, notaMaximaTema);

/// "Em leitura", "Lido" ou "Quero ler", pelas datas da ficha.
String situacaoDaLeitura(DateTime? iniciou, DateTime? terminou) {
  if (terminou != null) return 'Lido';
  if (iniciou != null) return 'Em leitura';
  return 'Não iniciado';
}
