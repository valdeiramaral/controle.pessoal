import 'package:flutter/material.dart';

/// Banco do catalogo (codigo COMPE de 3 digitos, nome e cor da marca para o selo).
/// Sem logotipos: o selo e um circulo colorido com a sigla (nao usa marcas registradas).
class BancoCatalogo {
  const BancoCatalogo(this.codigo, this.nome, this.sigla, this.cor);
  final String codigo;
  final String nome;
  final String sigla;
  final Color cor;
}

const codigoOutroBanco = '000';

const catalogoBancos = <BancoCatalogo>[
  BancoCatalogo('341', 'Itaú', 'it', Color(0xFFEC7000)),
  BancoCatalogo('237', 'Bradesco', 'Br', Color(0xFFCC092F)),
  BancoCatalogo('001', 'Banco do Brasil', 'BB', Color(0xFFF9D200)),
  BancoCatalogo('104', 'Caixa', 'Cx', Color(0xFF0070AF)),
  BancoCatalogo('033', 'Santander', 'Sa', Color(0xFFEC0000)),
  BancoCatalogo('260', 'Nubank', 'Nu', Color(0xFF820AD1)),
  BancoCatalogo('077', 'Banco Inter', 'In', Color(0xFFFF7A00)),
  BancoCatalogo('336', 'C6 Bank', 'C6', Color(0xFF242424)),
  BancoCatalogo('208', 'BTG Pactual', 'BTG', Color(0xFF001E62)),
  BancoCatalogo('748', 'Sicredi', 'Si', Color(0xFF3FA535)),
  BancoCatalogo('756', 'Sicoob', 'Sc', Color(0xFF003641)),
  BancoCatalogo('041', 'Banrisul', 'Bs', Color(0xFF004B8D)),
  BancoCatalogo('422', 'Safra', 'Sf', Color(0xFF0B2D5B)),
  BancoCatalogo('212', 'Banco Original', 'Or', Color(0xFF00A859)),
  BancoCatalogo('380', 'PicPay', 'Pp', Color(0xFF21C25E)),
  BancoCatalogo('323', 'Mercado Pago', 'MP', Color(0xFF00A1EA)),
  BancoCatalogo('403', 'Cora', 'Co', Color(0xFFFE3E6D)),
  BancoCatalogo('290', 'PagBank', 'Pg', Color(0xFF41B57F)),
  BancoCatalogo(codigoOutroBanco, 'Outro banco', '?', Color(0xFF607D8B)),
];

/// Banco pelo codigo; codigos desconhecidos/nulos caem em "Outro banco".
BancoCatalogo bancoPorCodigo(String? codigo) =>
    catalogoBancos.firstWhere((b) => b.codigo == codigo, orElse: () => catalogoBancos.last);

/// Selo redondo do banco (sigla sobre a cor da marca).
class SeloBanco extends StatelessWidget {
  const SeloBanco(this.codigo, {super.key, this.raio = 18});
  final String? codigo;
  final double raio;

  @override
  Widget build(BuildContext context) {
    final b = bancoPorCodigo(codigo);
    final claro = b.cor.computeLuminance() > .5;
    return CircleAvatar(
      radius: raio,
      backgroundColor: b.cor,
      child: Text(b.sigla,
          style: TextStyle(
              color: claro ? Colors.black87 : Colors.white, fontSize: raio * .7, fontWeight: FontWeight.w700)),
    );
  }
}
