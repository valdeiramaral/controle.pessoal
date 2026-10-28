/// Informacao breve e geral sobre medicamentos comuns, guardada no proprio app (funciona sem internet).
/// E apoio para reconhecer o remedio: NAO substitui a bula nem a orientacao do medico ou do farmaceutico.

class InfoMedicamento {
  const InfoMedicamento(this.nome, this.informacao);
  final String nome;
  final String informacao;
}

const avisoInformacao = 'Informação geral de apoio. Não substitui a bula nem a orientação do médico ou do farmacêutico.';

const catalogoMedicamentos = <InfoMedicamento>[
  InfoMedicamento('Paracetamol', 'Analgésico e antitérmico. Usado para dor leve a moderada e febre. Respeite a dose máxima diária e evite associar com outros remédios que também contenham paracetamol (risco para o fígado).'),
  InfoMedicamento('Dipirona', 'Analgésico e antitérmico. Usado para dor e febre. Pode causar reação alérgica; procure atendimento se surgirem manchas, falta de ar ou inchaço.'),
  InfoMedicamento('Ibuprofeno', 'Anti-inflamatório não esteroide. Usado para dor, febre e inflamação. Tomar após alimentar-se; exige cuidado em quem tem problemas de estômago, rins ou pressão alta.'),
  InfoMedicamento('Ácido acetilsalicílico', 'Analgésico, antitérmico e antiagregante plaquetário (AAS). Em dose baixa, e só com orientação médica, ajuda a prevenir infarto e AVC. Pode irritar o estômago e aumentar o risco de sangramento.'),
  InfoMedicamento('Diclofenaco', 'Anti-inflamatório não esteroide. Usado para dor e inflamação (articulações, músculos, cólicas). Tomar com alimento; cuidado com estômago, rins e coração.'),
  InfoMedicamento('Nimesulida', 'Anti-inflamatório, analgésico e antitérmico. Uso por poucos dias; pode afetar o fígado se usado por muito tempo ou em excesso.'),
  InfoMedicamento('Naproxeno', 'Anti-inflamatório não esteroide. Usado para dor, inflamação e cólicas. Tomar após alimentar-se.'),
  InfoMedicamento('Cetoprofeno', 'Anti-inflamatório não esteroide. Usado para dor e inflamação. Tomar com alimento.'),
  InfoMedicamento('Tramadol', 'Analgésico opioide para dor moderada a intensa. Pode causar sonolência, tontura e dependência; uso com receita controlada.'),
  InfoMedicamento('Omeprazol', 'Inibidor da produção de ácido do estômago. Usado em gastrite, refluxo e úlcera. Costuma ser tomado em jejum, cerca de 30 minutos antes do café da manhã.'),
  InfoMedicamento('Pantoprazol', 'Inibidor da produção de ácido do estômago. Usado em gastrite, refluxo e úlcera. Costuma ser tomado em jejum.'),
  InfoMedicamento('Domperidona', 'Antiemético e procinético. Usado para náusea, vômito e sensação de estômago pesado. Tomar antes das refeições.'),
  InfoMedicamento('Metoclopramida', 'Antiemético. Usado para náusea, vômito e refluxo. Pode causar sonolência e movimentos involuntários.'),
  InfoMedicamento('Ondansetrona', 'Antiemético. Usado para prevenir e tratar náuseas e vômitos.'),
  InfoMedicamento('Escopolamina', 'Antiespasmódico. Usado para cólicas abdominais, intestinais e menstruais. Pode causar boca seca.'),
  InfoMedicamento('Simeticona', 'Antigases. Alivia o desconforto causado por gases no intestino.'),
  InfoMedicamento('Losartana', 'Anti-hipertensivo (bloqueador do receptor de angiotensina). Usado para pressão alta e proteção do coração e dos rins. Uso contínuo, todos os dias.'),
  InfoMedicamento('Enalapril', 'Anti-hipertensivo (inibidor da ECA). Usado para pressão alta e insuficiência cardíaca. Pode causar tosse seca.'),
  InfoMedicamento('Captopril', 'Anti-hipertensivo (inibidor da ECA). Usado para pressão alta e insuficiência cardíaca. Pode causar tosse seca.'),
  InfoMedicamento('Anlodipino', 'Anti-hipertensivo (bloqueador de canal de cálcio). Usado para pressão alta e angina. Pode causar inchaço nos tornozelos.'),
  InfoMedicamento('Hidroclorotiazida', 'Diurético. Usado para pressão alta e retenção de líquidos. Aumenta a vontade de urinar.'),
  InfoMedicamento('Furosemida', 'Diurético potente. Usado em inchaço, insuficiência cardíaca e pressão alta. Aumenta a urina; atenção à hidratação.'),
  InfoMedicamento('Espironolactona', 'Diurético poupador de potássio. Usado em insuficiência cardíaca, pressão alta e retenção de líquidos.'),
  InfoMedicamento('Atenolol', 'Betabloqueador. Usado para pressão alta, angina e arritmias. Não suspenda de repente sem orientação médica.'),
  InfoMedicamento('Propranolol', 'Betabloqueador. Usado para pressão alta, arritmias, enxaqueca e tremores. Não suspenda de repente sem orientação médica.'),
  InfoMedicamento('Carvedilol', 'Betabloqueador. Usado em insuficiência cardíaca e pressão alta. Não suspenda de repente sem orientação médica.'),
  InfoMedicamento('Sinvastatina', 'Estatina que reduz o colesterol. Costuma ser tomada à noite. Avise o médico se tiver dor ou fraqueza muscular.'),
  InfoMedicamento('Atorvastatina', 'Estatina que reduz o colesterol e o risco cardiovascular. Avise o médico se tiver dor ou fraqueza muscular.'),
  InfoMedicamento('Rosuvastatina', 'Estatina que reduz o colesterol e o risco cardiovascular. Avise o médico se tiver dor ou fraqueza muscular.'),
  InfoMedicamento('Clopidogrel', 'Antiagregante plaquetário. Previne trombos em quem teve infarto, AVC ou usa stent. Aumenta o risco de sangramento.'),
  InfoMedicamento('Varfarina', 'Anticoagulante. Exige exames de sangue periódicos (INR) e atenção a alimentos e remédios que interferem na ação.'),
  InfoMedicamento('Rivaroxabana', 'Anticoagulante oral. Previne e trata trombose e AVC. Aumenta o risco de sangramento; não pule doses.'),
  InfoMedicamento('Metformina', 'Antidiabético. Usado no diabetes tipo 2. Tomar junto às refeições reduz o desconforto no estômago.'),
  InfoMedicamento('Glibenclamida', 'Antidiabético que estimula a produção de insulina. Pode causar hipoglicemia se a refeição for pulada.'),
  InfoMedicamento('Gliclazida', 'Antidiabético que estimula a produção de insulina. Pode causar hipoglicemia se a refeição for pulada.'),
  InfoMedicamento('Levotiroxina', 'Hormônio da tireoide. Usado no hipotireoidismo. Tomar em jejum, de 30 a 60 minutos antes do café, sempre no mesmo horário.'),
  InfoMedicamento('Amoxicilina', 'Antibiótico (penicilina). Usado em infecções bacterianas. Tome pelo tempo indicado, mesmo melhorando; não use se tiver alergia a penicilina.'),
  InfoMedicamento('Azitromicina', 'Antibiótico (macrolídeo). Usado em infecções respiratórias, de garganta e de pele. Tome pelo tempo indicado.'),
  InfoMedicamento('Cefalexina', 'Antibiótico (cefalosporina). Usado em infecções de pele, urinárias e respiratórias. Tome pelo tempo indicado.'),
  InfoMedicamento('Ciprofloxacino', 'Antibiótico (quinolona). Usado em infecções urinárias, intestinais e outras. Evite tomar junto com leite ou antiácidos.'),
  InfoMedicamento('Prednisona', 'Corticoide. Usado em inflamações, alergias e doenças autoimunes. Em uso prolongado, não suspenda de repente.'),
  InfoMedicamento('Dexametasona', 'Corticoide potente. Usado em inflamações e alergias graves. Pode aumentar a glicose e a pressão.'),
  InfoMedicamento('Loratadina', 'Anti-histamínico. Usado em rinite e alergias de pele. Causa pouca sonolência.'),
  InfoMedicamento('Desloratadina', 'Anti-histamínico. Usado em rinite e urticária. Causa pouca sonolência.'),
  InfoMedicamento('Cetirizina', 'Anti-histamínico. Usado em rinite e urticária. Pode causar sonolência.'),
  InfoMedicamento('Dimenidrinato', 'Antiemético e anti-vertigem. Usado para enjoo de movimento. Causa sonolência.'),
  InfoMedicamento('Salbutamol', 'Broncodilatador de ação rápida. Alivia a falta de ar e o chiado na asma e na bronquite. Pode causar tremor e palpitação.'),
  InfoMedicamento('Fluoxetina', 'Antidepressivo (inibidor da recaptação de serotonina). Usado em depressão, ansiedade e TOC. O efeito leva semanas; não suspenda sem orientação.'),
  InfoMedicamento('Sertralina', 'Antidepressivo (inibidor da recaptação de serotonina). Usado em depressão, ansiedade e pânico. O efeito leva semanas; não suspenda sem orientação.'),
  InfoMedicamento('Escitalopram', 'Antidepressivo (inibidor da recaptação de serotonina). Usado em depressão e ansiedade. O efeito leva semanas; não suspenda sem orientação.'),
  InfoMedicamento('Amitriptilina', 'Antidepressivo tricíclico. Usado em depressão, dor crônica e prevenção de enxaqueca. Causa sonolência e boca seca.'),
  InfoMedicamento('Clonazepam', 'Benzodiazepínico. Usado em ansiedade, pânico e convulsões. Causa sonolência e pode gerar dependência; uso com receita controlada.'),
  InfoMedicamento('Alprazolam', 'Benzodiazepínico. Usado em ansiedade e pânico. Causa sonolência e pode gerar dependência; uso com receita controlada.'),
  InfoMedicamento('Zolpidem', 'Indutor do sono. Usado em insônia, por curto período. Tome só quando puder dormir a noite toda; uso com receita controlada.'),
  InfoMedicamento('Sulfato ferroso', 'Suplemento de ferro. Usado em anemia por falta de ferro. Pode escurecer as fezes e causar desconforto no estômago.'),
  InfoMedicamento('Ácido fólico', 'Vitamina do complexo B (B9). Usada na gravidez, em anemias e na prevenção de falhas no desenvolvimento do bebê.'),
  InfoMedicamento('Colecalciferol', 'Vitamina D. Usada para repor a deficiência e manter ossos e músculos saudáveis. Tomar com uma refeição que tenha gordura.'),
  InfoMedicamento('Lactulose', 'Laxante osmótico. Usado em prisão de ventre. O efeito pode levar de 1 a 2 dias.'),
];

String _normalizar(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  var t = s.toLowerCase().trim();
  for (var i = 0; i < de.length; i++) {
    t = t.replaceAll(de[i], para[i]);
  }
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

/// Apelidos comuns -> nome do catalogo.
const _apelidos = <String, String>{
  'aas': 'Ácido acetilsalicílico',
  'acido acetilsalicilico': 'Ácido acetilsalicílico',
  'sinvastatina': 'Sinvastatina',
  'buscopan': 'Escopolamina',
  'dramin': 'Dimenidrinato',
  'tylenol': 'Paracetamol',
  'novalgina': 'Dipirona',
  'puran t4': 'Levotiroxina',
  'puran': 'Levotiroxina',
  'glifage': 'Metformina',
  'aradois': 'Losartana',
  'cozaar': 'Losartana',
  'lipitor': 'Atorvastatina',
  'omeprazol': 'Omeprazol',
  'cataflam': 'Diclofenaco',
  'voltaren': 'Diclofenaco',
  'advil': 'Ibuprofeno',
  'alivium': 'Ibuprofeno',
  'dorflex': 'Dipirona',
};

/// Sugestoes para o que o usuario digitou (comeca com ou contem), no maximo [limite].
List<InfoMedicamento> sugerirMedicamentos(String texto, {int limite = 5}) {
  final t = _normalizar(texto);
  if (t.length < 2) return const [];
  final comeca = <InfoMedicamento>[];
  final contem = <InfoMedicamento>[];
  for (final m in catalogoMedicamentos) {
    final n = _normalizar(m.nome);
    if (n.startsWith(t)) {
      comeca.add(m);
    } else if (n.contains(t)) {
      contem.add(m);
    }
  }
  return [...comeca, ...contem].take(limite).toList();
}

/// Informacao para o nome digitado quando ele e (ou comeca com) um medicamento do catalogo,
/// ou um apelido/nome comercial conhecido. null se nao reconhecer.
InfoMedicamento? infoDoMedicamento(String nome) {
  final t = _normalizar(nome);
  if (t.length < 3) return null;
  final apelido = _apelidos[t];
  for (final m in catalogoMedicamentos) {
    final n = _normalizar(m.nome);
    if (n == t || (apelido != null && m.nome == apelido)) return m;
  }
  for (final m in catalogoMedicamentos) {
    final n = _normalizar(m.nome);
    // "Paracetamol 750 mg" ou "Losartana potássica": primeira palavra igual ao nome do catalogo.
    if (t.startsWith('$n ')) return m;
  }
  return null;
}
