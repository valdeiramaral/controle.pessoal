import 'package:flutter/material.dart';

import 'bancos_febraban.dart';

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

/// Bancos mais usados, com a cor da marca; aparecem primeiro na lista.
const _destaques = <BancoCatalogo>[
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
];

/// Todos os bancos da lista COMPE/Febraban (os destaques primeiro, depois os demais por codigo)
/// e, no inicio, "Novo banco" para quem nao consta na lista.
final catalogoBancos = <BancoCatalogo>[
  const BancoCatalogo(codigoOutroBanco, 'Novo banco', '+', Color(0xFF607D8B)),
  ..._destaques,
  for (final (codigo, nome) in bancosFebraban)
    if (!_destaques.any((d) => d.codigo == codigo))
      BancoCatalogo(codigo, nome, _sigla(nome), _corDoCodigo(codigo)),
];

String _sigla(String nome) {
  final p = nome.split(RegExp(r'\s+')).where((x) => x.isNotEmpty && x[0].toUpperCase() != x[0].toLowerCase()).toList();
  if (p.isEmpty) return '?';
  if (p.length == 1) return p.first.substring(0, p.first.length < 2 ? 1 : 2);
  return p.first[0].toUpperCase() + p[1][0].toLowerCase();
}

Color _corDoCodigo(String codigo) {
  final n = int.tryParse(codigo) ?? 0;
  return HSLColor.fromAHSL(1, (n * 47) % 360, .45, .32).toColor();
}

/// Banco pelo codigo; codigos desconhecidos/nulos caem em "Novo banco".
BancoCatalogo bancoPorCodigo(String? codigo) =>
    catalogoBancos.firstWhere((b) => b.codigo == codigo, orElse: () => catalogoBancos.first);

/// Codigos COMPE que tem logotipo em assets/bancos/<codigo>.png.
/// Logos oficiais publicados pelas proprias instituicoes (uso nominativo; ver docs/logos-bancos-aviso.md).
const bancosComLogo = <String>{
  '001',
  '003',
  '004',
  '007',
  '011',
  '014',
  '015',
  '016',
  '017',
  '021',
  '025',
  '033',
  '036',
  '037',
  '040',
  '041',
  '047',
  '063',
  '064',
  '066',
  '069',
  '070',
  '074',
  '077',
  '079',
  '084',
  '085',
  '100',
  '101',
  '102',
  '104',
  '105',
  '107',
  '111',
  '113',
  '119',
  '120',
  '121',
  '122',
  '125',
  '129',
  '133',
  '136',
  '140',
  '143',
  '144',
  '174',
  '197',
  '208',
  '212',
  '213',
  '217',
  '218',
  '222',
  '224',
  '233',
  '237',
  '246',
  '250',
  '254',
  '260',
  '265',
  '268',
  '269',
  '274',
  '276',
  '278',
  '290',
  '292',
  '300',
  '301',
  '310',
  '318',
  '323',
  '326',
  '329',
  '330',
  '332',
  '335',
  '336',
  '341',
  '348',
  '352',
  '358',
  '362',
  '363',
  '364',
  '368',
  '370',
  '374',
  '376',
  '380',
  '381',
  '383',
  '386',
  '389',
  '393',
  '394',
  '396',
  '397',
  '401',
  '403',
  '404',
  '406',
  '407',
  '412',
  '413',
  '422',
  '426',
  '428',
  '450',
  '461',
  '469',
  '475',
  '477',
  '479',
  '487',
  '488',
  '505',
  '507',
  '509',
  '517',
  '518',
  '529',
  '531',
  '534',
  '536',
  '541',
  '542',
  '554',
  '555',
  '565',
  '567',
  '576',
  '588',
  '593',
  '594',
  '595',
  '611',
  '612',
  '613',
  '620',
  '623',
  '626',
  '633',
  '634',
  '637',
  '643',
  '654',
  '655',
  '665',
  '668',
  '672',
  '675',
  '694',
  '703',
  '707',
  '712',
  '741',
  '743',
  '745',
  '748',
  '752',
  '755',
  '756',
  '763',
  '769',
  '773',
  '775',
  '783',
  '793',
  '803',
};

/// Selo redondo do banco (sigla sobre a cor da marca).
class SeloBanco extends StatelessWidget {
  const SeloBanco(this.codigo, {super.key, this.raio = 18});
  final String? codigo;
  final double raio;

  @override
  Widget build(BuildContext context) {
    final b = bancoPorCodigo(codigo);
    final claro = b.cor.computeLuminance() > .5;
    final selo = CircleAvatar(
      radius: raio,
      backgroundColor: b.cor,
      child: Text(b.sigla,
          style: TextStyle(
              color: claro ? Colors.black87 : Colors.white, fontSize: raio * .7, fontWeight: FontWeight.w700)),
    );
    if (!bancosComLogo.contains(b.codigo)) return selo;
    return Container(
      key: Key('logo_${b.codigo}'),
      width: raio * 2,
      height: raio * 2,
      padding: EdgeInsets.all(raio * .12),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
      ),
      child: ClipOval(
        child: Image.asset('assets/bancos/${b.codigo}.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => selo),
      ),
    );
  }
}
