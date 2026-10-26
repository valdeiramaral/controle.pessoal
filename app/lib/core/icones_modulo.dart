import 'package:flutter/material.dart';

// Icones do Material Design (vetoriais, contorno, licenca Apache 2.0: gratuitos) que o SuperUsuario
// pode dar a um modulo. A chave e o que a API guarda; deve ficar igual a lista ICONES da API
// (api/src/rotas/modulos.js).

/// Um icone escolhivel: chave, desenho e nome (usado na busca).
class IconeModulo {
  const IconeModulo(this.chave, this.icone, this.nome);

  final String chave;
  final IconData icone;
  final String nome;
}

/// Categoria de icones, com a cor usada nos icones dela.
class CategoriaIcones {
  const CategoriaIcones(this.nome, this.cor, this.icones);

  final String nome;
  final MaterialColor cor;
  final List<IconeModulo> icones;
}

const categoriasIcones = <CategoriaIcones>[
  CategoriaIcones('Geral', Colors.orange, [
    IconeModulo('extension', Icons.extension_outlined, 'Módulo'),
    IconeModulo('folder', Icons.folder_outlined, 'Pasta'),
    IconeModulo('star', Icons.star_border, 'Estrela'),
    IconeModulo('build', Icons.build_outlined, 'Ferramentas'),
    IconeModulo('chart', Icons.bar_chart_outlined, 'Gráfico'),
    IconeModulo('people', Icons.people_outline, 'Pessoas'),
    IconeModulo('flag', Icons.flag_outlined, 'Meta'),
    IconeModulo('bookmark', Icons.bookmark_border, 'Favorito'),
    IconeModulo('label', Icons.label_outlined, 'Etiqueta'),
    IconeModulo('lock', Icons.lock_outline, 'Cadeado'),
    IconeModulo('security', Icons.security_outlined, 'Segurança'),
    IconeModulo('cloud', Icons.cloud_outlined, 'Nuvem'),
    IconeModulo('bolt', Icons.bolt, 'Energia'),
    IconeModulo('notifications', Icons.notifications_none, 'Alertas'),
    IconeModulo('event', Icons.event_outlined, 'Calendário'),
    IconeModulo('handyman', Icons.handyman_outlined, 'Reparos'),
  ]),
  CategoriaIcones('Finanças', Colors.green, [
    IconeModulo('wallet', Icons.account_balance_wallet_outlined, 'Carteira'),
    IconeModulo('savings', Icons.savings_outlined, 'Poupança'),
    IconeModulo('money', Icons.attach_money, 'Dinheiro'),
    IconeModulo('card', Icons.credit_card_outlined, 'Cartão'),
    IconeModulo('receipt', Icons.receipt_long_outlined, 'Contas'),
    IconeModulo('bank', Icons.account_balance_outlined, 'Banco'),
    IconeModulo('growth', Icons.trending_up, 'Investimentos'),
    IconeModulo('pie', Icons.pie_chart_outline, 'Orçamento'),
    IconeModulo('payments', Icons.payments_outlined, 'Pagamentos'),
    IconeModulo('exchange', Icons.currency_exchange, 'Câmbio'),
    IconeModulo('quote', Icons.request_quote_outlined, 'Orçamento de venda'),
    IconeModulo('calculator', Icons.calculate_outlined, 'Calculadora'),
  ]),
  CategoriaIcones('Saúde', Colors.red, [
    IconeModulo('fitness', Icons.fitness_center_outlined, 'Academia'),
    IconeModulo('heart', Icons.favorite_border, 'Coração'),
    IconeModulo('medication', Icons.medication_outlined, 'Remédios'),
    IconeModulo('heartbeat', Icons.monitor_heart_outlined, 'Batimentos'),
    IconeModulo('hospital', Icons.local_hospital_outlined, 'Hospital'),
    IconeModulo('vaccine', Icons.vaccines_outlined, 'Vacinas'),
    IconeModulo('run', Icons.directions_run, 'Corrida'),
    IconeModulo('spa', Icons.spa_outlined, 'Bem-estar'),
    IconeModulo('sleep', Icons.bedtime_outlined, 'Sono'),
    IconeModulo('water', Icons.water_drop_outlined, 'Água'),
    IconeModulo('food', Icons.restaurant_outlined, 'Alimentação'),
    IconeModulo('meditation', Icons.self_improvement, 'Meditação'),
  ]),
  CategoriaIcones('Trabalho e estudos', Colors.indigo, [
    IconeModulo('work', Icons.work_outline, 'Trabalho'),
    IconeModulo('school', Icons.school_outlined, 'Escola'),
    IconeModulo('book', Icons.menu_book_outlined, 'Livro'),
    IconeModulo('laptop', Icons.laptop_outlined, 'Computador'),
    IconeModulo('code', Icons.code, 'Código'),
    IconeModulo('team', Icons.groups_outlined, 'Equipe'),
    IconeModulo('business', Icons.business_center_outlined, 'Negócios'),
    IconeModulo('assignment', Icons.assignment_outlined, 'Tarefas'),
    IconeModulo('checklist', Icons.checklist, 'Lista'),
    IconeModulo('notes', Icons.edit_note, 'Anotações'),
    IconeModulo('idea', Icons.lightbulb_outline, 'Ideias'),
    IconeModulo('science', Icons.science_outlined, 'Ciência'),
    IconeModulo('language', Icons.language, 'Idiomas'),
    IconeModulo('translate', Icons.translate, 'Tradução'),
  ]),
  CategoriaIcones('Casa e família', Colors.teal, [
    IconeModulo('home', Icons.home_outlined, 'Casa'),
    IconeModulo('cart', Icons.shopping_cart_outlined, 'Compras'),
    IconeModulo('bag', Icons.shopping_bag_outlined, 'Sacola'),
    IconeModulo('kitchen', Icons.kitchen_outlined, 'Cozinha'),
    IconeModulo('sofa', Icons.weekend_outlined, 'Sala'),
    IconeModulo('laundry', Icons.local_laundry_service_outlined, 'Lavanderia'),
    IconeModulo('garden', Icons.yard_outlined, 'Jardim'),
    IconeModulo('baby', Icons.child_care, 'Bebê'),
    IconeModulo('family', Icons.family_restroom, 'Família'),
    IconeModulo('cake', Icons.cake_outlined, 'Aniversário'),
    IconeModulo('party', Icons.celebration_outlined, 'Festa'),
    IconeModulo('gift', Icons.redeem, 'Presente'),
  ]),
  CategoriaIcones('Viagem e transporte', Colors.lightBlue, [
    IconeModulo('flight', Icons.flight_outlined, 'Voo'),
    IconeModulo('car', Icons.directions_car_outlined, 'Carro'),
    IconeModulo('moto', Icons.two_wheeler, 'Moto'),
    IconeModulo('bus', Icons.directions_bus_outlined, 'Ônibus'),
    IconeModulo('train', Icons.train_outlined, 'Trem'),
    IconeModulo('boat', Icons.sailing_outlined, 'Barco'),
    IconeModulo('hotel', Icons.hotel_outlined, 'Hotel'),
    IconeModulo('map', Icons.map_outlined, 'Mapa'),
    IconeModulo('luggage', Icons.luggage_outlined, 'Mala'),
    IconeModulo('beach', Icons.beach_access_outlined, 'Praia'),
    IconeModulo('camera', Icons.camera_alt_outlined, 'Fotos'),
  ]),
  CategoriaIcones('Lazer', Colors.purple, [
    IconeModulo('pets', Icons.pets_outlined, 'Animais'),
    IconeModulo('music', Icons.music_note_outlined, 'Música'),
    IconeModulo('movie', Icons.movie_outlined, 'Filmes'),
    IconeModulo('games', Icons.sports_esports_outlined, 'Jogos'),
    IconeModulo('art', Icons.palette_outlined, 'Arte'),
    IconeModulo('brush', Icons.brush_outlined, 'Pintura'),
    IconeModulo('headphones', Icons.headphones_outlined, 'Fones'),
    IconeModulo('theater', Icons.theater_comedy_outlined, 'Teatro'),
    IconeModulo('ball', Icons.sports_soccer_outlined, 'Futebol'),
    IconeModulo('basket', Icons.sports_basketball_outlined, 'Basquete'),
    IconeModulo('coffee', Icons.local_cafe_outlined, 'Café'),
    IconeModulo('bar', Icons.local_bar_outlined, 'Bar'),
    IconeModulo('nature', Icons.eco_outlined, 'Natureza'),
    IconeModulo('sun', Icons.wb_sunny_outlined, 'Sol'),
  ]),
];

/// Chave -> desenho.
final iconesModulo = <String, IconData>{
  for (final c in categoriasIcones)
    for (final i in c.icones) i.chave: i.icone,
};

/// Chave -> cor da categoria.
final coresModulo = <String, MaterialColor>{
  for (final c in categoriasIcones)
    for (final i in c.icones) i.chave: c.cor,
};

IconData iconeDoModulo(String? chave) => iconesModulo[chave] ?? Icons.extension_outlined;

MaterialColor corBaseDoModulo(String? chave) => coresModulo[chave] ?? Colors.orange;
