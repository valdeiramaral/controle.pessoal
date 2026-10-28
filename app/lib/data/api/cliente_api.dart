import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/aparencia.dart';

/// Endereco da API. Use --dart-define=API_URL=http://... para trocar.
/// No emulador Android, 10.0.2.2 e o computador que roda o emulador.
String urlPadraoApi() {
  const definida = String.fromEnvironment('API_URL');
  if (definida.isNotEmpty) return definida;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://localhost:3000';
}

/// Erro devolvido pela API (ou falta de conexao), ja com texto para o usuario.
class ErroApi implements Exception {
  ErroApi(this.codigo, this.mensagem, {this.status, this.campo});

  final String codigo;
  final String mensagem;
  final int? status;

  /// Campo do formulario a que o erro se refere (ex.: 'cpf'), quando a API informa.
  final String? campo;

  bool get semConexao => codigo == 'sem_conexao';
  bool get naoAutenticado => status == 401 && codigo == 'nao_autenticado';

  @override
  String toString() => mensagem;
}

class EnderecoApi {
  const EnderecoApi({this.cep, this.logradouro, this.numero, this.complemento, this.bairro, this.cidade, this.uf});

  final String? cep;
  final String? logradouro;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? cidade;
  final String? uf;

  factory EnderecoApi.deJson(Map<String, dynamic>? j) => EnderecoApi(
        cep: j?['cep'] as String?,
        logradouro: j?['logradouro'] as String?,
        numero: j?['numero'] as String?,
        complemento: j?['complemento'] as String?,
        bairro: j?['bairro'] as String?,
        cidade: j?['cidade'] as String?,
        uf: j?['uf'] as String?,
      );

  Map<String, dynamic> paraJson() => {
        'cep': cep,
        'logradouro': logradouro,
        'numero': numero,
        'complemento': complemento,
        'bairro': bairro,
        'cidade': cidade,
        'uf': uf,
      };
}

class UsuarioApi {
  const UsuarioApi({
    required this.id,
    required this.nome,
    this.email,
    this.idioma,
    this.pais,
    this.cpf,
    this.telefone,
    this.nascimento,
    this.endereco = const EnderecoApi(),
    this.ativo = true,
  });

  final String id;
  final String nome;
  final String? email;
  final String? idioma;
  final String? pais;

  /// Somente digitos.
  final String? cpf;
  final String? telefone;

  /// ISO 'AAAA-MM-DD'.
  final String? nascimento;
  final EnderecoApi endereco;
  final bool ativo;

  factory UsuarioApi.deJson(Map<String, dynamic> j) => UsuarioApi(
        id: j['id'] as String,
        nome: j['nome'] as String,
        email: j['email'] as String?,
        idioma: j['idioma'] as String?,
        pais: j['pais'] as String?,
        cpf: j['cpf'] as String?,
        telefone: j['telefone'] as String?,
        nascimento: j['nascimento'] as String?,
        endereco: EnderecoApi.deJson(j['endereco'] as Map<String, dynamic>?),
        ativo: j['ativo'] as bool? ?? true,
      );

  Map<String, dynamic> paraJson() => {
        'id': id,
        'nome': nome,
        'email': email,
        'idioma': idioma,
        'pais': pais,
        'cpf': cpf,
        'telefone': telefone,
        'nascimento': nascimento,
        'endereco': endereco.paraJson(),
        'ativo': ativo,
      };
}

/// Resposta de GET /me: dados da pessoa, plano, modulos liberados e permissoes.
class PerfilApi {
  const PerfilApi(
      {required this.usuario, this.plano, this.modulos = const [], this.permissoes = const [], this.superusuario = false, this.aparencia = Aparencia.padrao});

  final UsuarioApi usuario;
  final String? plano;
  final List<String> modulos;
  final List<String> permissoes;

  /// Unico que enxerga e administra os dados de todos os usuarios.
  final bool superusuario;

  /// Preferencias de aparencia (modo, tamanho da letra, cor) da conta.
  final Aparencia aparencia;

  PerfilApi copiarCom({UsuarioApi? usuario, Aparencia? aparencia}) => PerfilApi(
        usuario: usuario ?? this.usuario,
        plano: plano,
        modulos: modulos,
        permissoes: permissoes,
        superusuario: superusuario,
        aparencia: aparencia ?? this.aparencia,
      );

  bool pode(String permissao) => permissoes.contains(permissao);
}

class ResultadoLogin {
  const ResultadoLogin({required this.token, required this.expiraEm, required this.usuario});

  final String token;
  final DateTime expiraEm;
  final UsuarioApi usuario;
}

// ----------------------------------------------------------- administracao

class ItemUsuario {
  const ItemUsuario({required this.id, required this.nome, required this.email, this.cpf, this.plano, this.ativo = true});

  final String id;
  final String nome;
  final String email;
  final String? cpf;
  final String? plano;
  final bool ativo;

  factory ItemUsuario.deJson(Map<String, dynamic> j) => ItemUsuario(
        id: j['id'] as String,
        nome: j['nome'] as String,
        email: j['email'] as String,
        cpf: j['cpf'] as String?,
        plano: j['plano'] as String?,
        ativo: j['ativo'] as bool? ?? true,
      );
}

class ListaUsuarios {
  const ListaUsuarios({required this.total, required this.itens});

  final int total;
  final List<ItemUsuario> itens;
}

class OpcaoCatalogo {
  const OpcaoCatalogo(this.codigo, this.nome, {this.descricao});

  final String codigo;
  final String nome;
  final String? descricao;

  factory OpcaoCatalogo.deJson(Map<String, dynamic> j) =>
      OpcaoCatalogo(j['codigo'] as String, j['nome'] as String, descricao: j['descricao'] as String?);
}

class CatalogoApi {
  const CatalogoApi({required this.planos, required this.modulos, required this.perfis});

  final List<OpcaoCatalogo> planos;
  final List<OpcaoCatalogo> modulos;
  final List<OpcaoCatalogo> perfis;

  factory CatalogoApi.deJson(Map<String, dynamic> j) {
    List<OpcaoCatalogo> lista(String k) =>
        (j[k] as List).map((e) => OpcaoCatalogo.deJson(e as Map<String, dynamic>)).toList();
    return CatalogoApi(planos: lista('planos'), modulos: lista('modulos'), perfis: lista('perfis'));
  }
}

/// Liberacao de um modulo para UM usuario: 'padrao' (vale o plano), 'liberado' ou 'bloqueado'.
class ModuloUsuario {
  const ModuloUsuario({required this.codigo, required this.nome, required this.liberacao, required this.efetivo});

  final String codigo;
  final String nome;
  final String liberacao;
  final bool efetivo;

  factory ModuloUsuario.deJson(Map<String, dynamic> j) => ModuloUsuario(
        codigo: j['codigo'] as String,
        nome: j['nome'] as String,
        liberacao: j['liberacao'] as String,
        efetivo: j['efetivo'] as bool? ?? false,
      );
}

class DetalheUsuario {
  const DetalheUsuario({
    required this.usuario,
    this.plano,
    this.perfis = const [],
    this.modulos = const [],
    this.grupos = const [],
    this.excecoes = const {},
    this.permissoes = const [],
  });

  final UsuarioApi usuario;
  final String? plano;
  final List<String> perfis;
  final List<ModuloUsuario> modulos;

  /// Grupos do usuario (id + nome).
  final List<GrupoResumo> grupos;

  /// Excecoes individuais: codigo -> true (concede) ou false (nega).
  final Map<String, bool> excecoes;

  /// Permissoes efetivas (perfis + grupos + excecoes).
  final List<String> permissoes;

  factory DetalheUsuario.deJson(Map<String, dynamic> j) => DetalheUsuario(
        usuario: UsuarioApi.deJson(j['usuario'] as Map<String, dynamic>),
        plano: (j['licenca'] as Map<String, dynamic>?)?['plano'] as String?,
        perfis: (j['perfis'] as List? ?? const []).cast<String>(),
        modulos: (j['modulos'] as List? ?? const [])
            .map((e) => ModuloUsuario.deJson(e as Map<String, dynamic>))
            .toList(),
        grupos: (j['grupos'] as List? ?? const [])
            .map((e) => GrupoResumo.deJson(e as Map<String, dynamic>))
            .toList(),
        excecoes: {
          for (final e in (j['excecoes'] as Map? ?? const {}).entries) e.key as String: e.value as bool,
        },
        permissoes: (j['permissoes'] as List? ?? const []).cast<String>(),
      );
}

/// Modulo no cadastro do administrador.
class ModuloAdmin {
  const ModuloAdmin({
    required this.codigo,
    required this.nome,
    this.descricao,
    this.ordem = 0,
    this.ativo = true,
    this.liberadoParaTodos = true,
    this.noPacote = false,
    this.icone = 'extension',
    this.sistema = false,
    this.planos = const [],
    this.liberacoes = const [],
  });

  final String codigo;
  final String nome;
  final String? descricao;
  final int ordem;
  final bool ativo;
  final bool liberadoParaTodos;

  /// Coluna legada no_pacote (valia para todos); o cadastro nao a usa mais: o "fixo" agora e escolhido por usuario na liberacao.
  final bool noPacote;
  final String icone;

  /// De fabrica (Financas, Saude...): nao pode ser excluido nem desativado.
  final bool sistema;

  /// Planos que liberam o modulo (usado quando nao e liberado para todos).
  final List<String> planos;

  /// Usuarios a quem o modulo foi liberado (cada um com sua validade ou vitalicio).
  final List<LiberacaoModulo> liberacoes;

  factory ModuloAdmin.deJson(Map<String, dynamic> j) => ModuloAdmin(
        codigo: j['codigo'] as String,
        nome: j['nome'] as String,
        descricao: j['descricao'] as String?,
        ordem: (j['ordem'] as num?)?.toInt() ?? 0,
        ativo: j['ativo'] as bool? ?? true,
        liberadoParaTodos: j['liberado_para_todos'] as bool? ?? false,
        noPacote: j['no_pacote'] as bool? ?? false,
        icone: j['icone'] as String? ?? 'extension',
        sistema: j['sistema'] as bool? ?? false,
        planos: (j['planos'] as List? ?? const []).cast<String>(),
        liberacoes: (j['liberacoes'] as List? ?? const [])
            .map((e) => LiberacaoModulo.deJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Liberacao de um modulo para um usuario: vitalicia ou valida entre duas datas; pode ser desativada.
class LiberacaoModulo {
  const LiberacaoModulo({
    required this.usuarioId,
    required this.nome,
    this.email,
    this.ativa = true,
    this.fixo = false,
    this.vitalicio = true,
    this.inicio,
    this.fim,
    this.vigente = true,
  });

  final String usuarioId;
  final String nome;
  final String? email;
  final bool ativa;

  /// Modulo fixado no topo do menu deste usuario.
  final bool fixo;
  final bool vitalicio;
  final DateTime? inicio;
  final DateTime? fim;

  /// Vale agora: ativa e dentro da validade (calculado pela API).
  final bool vigente;

  factory LiberacaoModulo.deJson(Map<String, dynamic> j) => LiberacaoModulo(
        usuarioId: j['usuario_id'] as String,
        nome: j['usuario_nome'] as String? ?? '',
        email: j['usuario_email'] as String?,
        ativa: j['ativa'] as bool? ?? true,
        fixo: j['fixo'] as bool? ?? false,
        vitalicio: j['vitalicio'] as bool? ?? true,
        inicio: DateTime.tryParse((j['inicio'] as String?) ?? '')?.toLocal(),
        fim: DateTime.tryParse((j['fim'] as String?) ?? '')?.toLocal(),
        vigente: j['vigente'] as bool? ?? true,
      );
}

/// Modulo que aparece no menu do usuario logado.
class ModuloMenu {
  const ModuloMenu({required this.codigo, required this.nome, this.descricao, this.icone = 'extension', this.fixo = false});

  final String codigo;
  final String nome;
  final String? descricao;
  final String icone;

  /// Fixado no topo do menu deste usuario (definido ao liberar o modulo para ele).
  final bool fixo;

  factory ModuloMenu.deJson(Map<String, dynamic> j) => ModuloMenu(
        codigo: j['codigo'] as String,
        nome: j['nome'] as String,
        descricao: j['descricao'] as String?,
        icone: j['icone'] as String? ?? 'extension',
        fixo: j['fixo'] as bool? ?? false,
      );
}

class GrupoResumo {
  const GrupoResumo(this.id, this.nome);

  final String id;
  final String nome;

  factory GrupoResumo.deJson(Map<String, dynamic> j) => GrupoResumo(j['id'] as String, j['nome'] as String);
}

/// Uma permissao do catalogo, com o modulo a que pertence.
class PermissaoApi {
  const PermissaoApi({required this.codigo, required this.nome, required this.moduloCodigo, required this.moduloNome});

  final String codigo;
  final String nome;
  final String moduloCodigo;
  final String moduloNome;

  factory PermissaoApi.deJson(Map<String, dynamic> j) => PermissaoApi(
        codigo: j['codigo'] as String,
        nome: j['nome'] as String,
        moduloCodigo: j['modulo_codigo'] as String,
        moduloNome: j['modulo_nome'] as String,
      );
}

class PerfilItem {
  const PerfilItem({
    required this.id,
    required this.codigo,
    required this.nome,
    this.descricao,
    this.sistema = false,
    this.totalPermissoes = 0,
    this.totalUsuarios = 0,
    this.permissoes = const [],
  });

  final String id;
  final String codigo;
  final String nome;
  final String? descricao;
  final bool sistema;
  final int totalPermissoes;
  final int totalUsuarios;

  /// So vem no detalhe (GET /perfis/:id).
  final List<String> permissoes;

  factory PerfilItem.deJson(Map<String, dynamic> j) => PerfilItem(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        nome: j['nome'] as String,
        descricao: j['descricao'] as String?,
        sistema: j['sistema'] == true,
        totalPermissoes: (j['total_permissoes'] as num?)?.toInt() ?? (j['permissoes'] as List?)?.length ?? 0,
        totalUsuarios: (j['total_usuarios'] as num?)?.toInt() ?? 0,
        permissoes: (j['permissoes'] as List? ?? const []).cast<String>(),
      );
}

class MembroGrupo {
  const MembroGrupo(this.id, this.nome, this.email);

  final String id;
  final String nome;
  final String? email;

  factory MembroGrupo.deJson(Map<String, dynamic> j) =>
      MembroGrupo(j['id'] as String, j['nome'] as String, j['email'] as String?);
}

class GrupoItem {
  const GrupoItem({
    required this.id,
    required this.nome,
    this.descricao,
    this.totalMembros = 0,
    this.perfis = const [],
    this.membros = const [],
  });

  final String id;
  final String nome;
  final String? descricao;
  final int totalMembros;

  /// Codigos dos perfis do grupo.
  final List<String> perfis;

  /// So vem no detalhe (GET /grupos/:id).
  final List<MembroGrupo> membros;

  factory GrupoItem.deJson(Map<String, dynamic> j) {
    final membros = (j['membros'] as List? ?? const [])
        .map((e) => MembroGrupo.deJson(e as Map<String, dynamic>))
        .toList();
    return GrupoItem(
      id: j['id'] as String,
      nome: j['nome'] as String,
      descricao: j['descricao'] as String?,
      totalMembros: (j['total_membros'] as num?)?.toInt() ?? membros.length,
      perfis: (j['perfis'] as List? ?? const []).cast<String>(),
      membros: membros,
    );
  }
}

class ClienteApi {
  ClienteApi({required this.baseUrl, http.Client? cliente, this.limite = const Duration(seconds: 15)})
      : _http = cliente ?? http.Client();

  final String baseUrl;
  final Duration limite;
  final http.Client _http;

  /// [dados]: cpf, telefone e, opcionalmente, nascimento ('AAAA-MM-DD') e endereco.
  Future<void> cadastrar({
    required String nome,
    required String email,
    required String senha,
    required String cpf,
    required String telefone,
    String? nascimento,
    Map<String, dynamic>? endereco,
  }) async {
    await _chamar('POST', '/cadastro', corpo: {
      'nome': nome.trim(),
      'email': email.trim(),
      'senha': senha,
      'cpf': cpf,
      'telefone': telefone,
      if (nascimento != null) 'nascimento': nascimento,
      if (endereco != null && endereco.isNotEmpty) 'endereco': endereco,
    });
  }

  Future<ResultadoLogin> entrar({required String email, required String senha}) async {
    final j = await _chamar('POST', '/login', corpo: {'email': email.trim(), 'senha': senha});
    final segundos = (j['expira_em_segundos'] as num?)?.toInt() ?? 3600;
    return ResultadoLogin(
      token: j['token'] as String,
      expiraEm: DateTime.now().add(Duration(seconds: segundos)),
      usuario: UsuarioApi.deJson(j['usuario'] as Map<String, dynamic>),
    );
  }

  /// Dados do usuario logado (GET /me).
  Future<PerfilApi> eu(String token) async {
    final j = await _chamar('GET', '/me', token: token);
    return PerfilApi(
      usuario: UsuarioApi.deJson(j['usuario'] as Map<String, dynamic>),
      plano: (j['licenca'] as Map<String, dynamic>?)?['plano'] as String?,
      modulos: (j['modulos'] as List? ?? const []).cast<String>(),
      permissoes: (j['permissoes'] as List? ?? const []).cast<String>(),
      superusuario: j['superusuario'] as bool? ?? false,
      aparencia: Aparencia.deJson(j['preferencias']),
    );
  }

  /// Guarda a aparencia escolhida na conta do usuario.
  Future<void> salvarAparencia(String token, Aparencia a) async =>
      _chamar('PUT', '/me/preferencias', corpo: a.paraJson(), token: token);

  /// O proprio usuario atualiza nome, telefone, nascimento e endereco.
  Future<UsuarioApi> atualizarMeusDados(String token, Map<String, dynamic> corpo) async {
    final j = await _chamar('PATCH', '/me', corpo: corpo, token: token);
    return UsuarioApi.deJson(j['usuario'] as Map<String, dynamic>);
  }

  // ------------------------------------------------------ administracao

  Future<CatalogoApi> catalogo(String token) async =>
      CatalogoApi.deJson(await _chamar('GET', '/catalogo', token: token));

  Future<ListaUsuarios> listarUsuarios(String token, {String busca = '', int pagina = 1}) async {
    final q = Uri(queryParameters: {
      'limite': '50',
      'pagina': '$pagina',
      if (busca.trim().isNotEmpty) 'busca': busca.trim(),
    }).query;
    final j = await _chamar('GET', '/usuarios?$q', token: token);
    return ListaUsuarios(
      total: (j['total'] as num).toInt(),
      itens: (j['itens'] as List).map((e) => ItemUsuario.deJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<DetalheUsuario> detalheUsuario(String token, String id) async =>
      DetalheUsuario.deJson(await _chamar('GET', '/usuarios/$id', token: token));

  /// Cadastra com plano, perfis e modulos ja definidos (cada um e opcional).
  Future<DetalheUsuario> criarUsuario(String token, Map<String, dynamic> corpo) async =>
      DetalheUsuario.deJson(await _chamar('POST', '/usuarios', corpo: corpo, token: token));

  Future<void> excluirUsuario(String token, String id) async {
    await _chamar('DELETE', '/usuarios/$id', token: token);
  }

  Future<void> atualizarUsuario(String token, String id, Map<String, dynamic> corpo) async {
    await _chamar('PATCH', '/usuarios/$id', corpo: corpo, token: token);
  }

  Future<DetalheUsuario> definirPlano(String token, String id, String plano) async =>
      DetalheUsuario.deJson(await _chamar('PUT', '/usuarios/$id/plano', corpo: {'plano': plano}, token: token));

  /// true libera, false bloqueia, null volta ao padrao do plano.
  Future<DetalheUsuario> definirModulos(String token, String id, Map<String, bool?> modulos) async =>
      DetalheUsuario.deJson(await _chamar('PUT', '/usuarios/$id/modulos', corpo: {'modulos': modulos}, token: token));

  Future<DetalheUsuario> definirPerfis(String token, String id, List<String> perfis) async =>
      DetalheUsuario.deJson(await _chamar('PUT', '/usuarios/$id/perfis', corpo: {'perfis': perfis}, token: token));

  // ------------------------------------------------- cadastro de modulos

  Future<List<ModuloAdmin>> listarModulos(String token) async {
    final j = await _chamar('GET', '/modulos', token: token);
    return (j['itens'] as List).map((e) => ModuloAdmin.deJson(e as Map<String, dynamic>)).toList();
  }

  Future<ModuloAdmin> criarModulo(String token, Map<String, dynamic> corpo) async =>
      ModuloAdmin.deJson(await _chamar('POST', '/modulos', corpo: corpo, token: token));

  Future<ModuloAdmin> atualizarModulo(String token, String codigo, Map<String, dynamic> corpo) async =>
      ModuloAdmin.deJson(await _chamar('PUT', '/modulos/$codigo', corpo: corpo, token: token));

  Future<void> excluirModulo(String token, String codigo) async {
    await _chamar('DELETE', '/modulos/$codigo', token: token);
  }

  /// Modulos cadastrados pelo administrador que o usuario logado pode usar (itens do menu).
  Future<List<ModuloMenu>> meusModulos(String token) async {
    final j = await _chamar('GET', '/meus-modulos', token: token);
    return (j['itens'] as List).map((e) => ModuloMenu.deJson(e as Map<String, dynamic>)).toList();
  }

  // ------------------------------------------- perfis, grupos e permissoes

  Future<List<PermissaoApi>> listarPermissoes(String token) async {
    final j = await _chamar('GET', '/permissoes', token: token);
    return (j['permissoes'] as List).map((e) => PermissaoApi.deJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<PerfilItem>> listarPerfis(String token) async {
    final j = await _chamar('GET', '/perfis', token: token);
    return (j['itens'] as List).map((e) => PerfilItem.deJson(e as Map<String, dynamic>)).toList();
  }

  Future<PerfilItem> detalhePerfil(String token, String id) async =>
      PerfilItem.deJson(await _chamar('GET', '/perfis/$id', token: token));

  Future<PerfilItem> criarPerfil(String token,
          {required String nome, String? descricao, required List<String> permissoes}) async =>
      PerfilItem.deJson(await _chamar('POST', '/perfis',
          corpo: {'nome': nome.trim(), 'descricao': descricao, 'permissoes': permissoes}, token: token));

  /// [permissoes] nulo = nao mexe nas permissoes (o perfil administrador e fixo).
  Future<PerfilItem> atualizarPerfil(String token, String id,
          {String? nome, String? descricao, List<String>? permissoes}) async =>
      PerfilItem.deJson(await _chamar('PUT', '/perfis/$id',
          corpo: {
            if (nome != null) 'nome': nome.trim(),
            'descricao': descricao,
            if (permissoes != null) 'permissoes': permissoes,
          },
          token: token));

  Future<void> excluirPerfil(String token, String id) async {
    await _chamar('DELETE', '/perfis/$id', token: token);
  }

  Future<List<GrupoItem>> listarGrupos(String token) async {
    final j = await _chamar('GET', '/grupos', token: token);
    return (j['itens'] as List).map((e) => GrupoItem.deJson(e as Map<String, dynamic>)).toList();
  }

  Future<GrupoItem> detalheGrupo(String token, String id) async =>
      GrupoItem.deJson(await _chamar('GET', '/grupos/$id', token: token));

  Future<GrupoItem> criarGrupo(String token,
          {required String nome, String? descricao, required List<String> perfis, required List<String> membros}) async =>
      GrupoItem.deJson(await _chamar('POST', '/grupos',
          corpo: {'nome': nome.trim(), 'descricao': descricao, 'perfis': perfis, 'membros': membros},
          token: token));

  Future<GrupoItem> atualizarGrupo(String token, String id,
          {required String nome, String? descricao, required List<String> perfis, required List<String> membros}) async =>
      GrupoItem.deJson(await _chamar('PUT', '/grupos/$id',
          corpo: {'nome': nome.trim(), 'descricao': descricao, 'perfis': perfis, 'membros': membros},
          token: token));

  Future<void> excluirGrupo(String token, String id) async {
    await _chamar('DELETE', '/grupos/$id', token: token);
  }

  Future<DetalheUsuario> definirGrupos(String token, String id, List<String> grupos) async =>
      DetalheUsuario.deJson(await _chamar('PUT', '/usuarios/$id/grupos', corpo: {'grupos': grupos}, token: token));

  /// true concede, false nega (a negacao vence), null remove a excecao.
  Future<DetalheUsuario> definirExcecoes(String token, String id, Map<String, bool?> permissoes) async =>
      DetalheUsuario.deJson(
          await _chamar('PUT', '/usuarios/$id/permissoes', corpo: {'permissoes': permissoes}, token: token));

  Future<Map<String, dynamic>> _chamar(String metodo, String caminho,
      {Map<String, dynamic>? corpo, String? token}) async {
    final req = http.Request(metodo, Uri.parse('$baseUrl$caminho'))
      ..headers['content-type'] = 'application/json'
      ..headers.addAll({if (token != null) 'authorization': 'Bearer $token'});
    if (corpo != null) req.body = jsonEncode(corpo);
    http.Response r;
    try {
      r = await http.Response.fromStream(await _http.send(req).timeout(limite));
    } on Exception {
      throw ErroApi('sem_conexao', 'Sem conexão com o servidor. Verifique a internet e tente de novo.');
    }
    Map<String, dynamic> dados = {};
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) dados = d;
    } on FormatException {
      // corpo vazio ou nao JSON: segue com o status
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return dados;
    final codigo = (dados['erro'] as String?) ?? 'erro_${r.statusCode}';
    throw ErroApi(codigo, _mensagem(r.statusCode, codigo, dados),
        status: r.statusCode, campo: dados['campo'] as String?);
  }

  static String _mensagem(int status, String codigo, Map<String, dynamic> dados) {
    switch (codigo) {
      case 'credenciais_invalidas':
        return 'E-mail ou senha incorretos.';
      case 'conta_bloqueada':
        final ate = DateTime.tryParse((dados['ate'] as String?) ?? '');
        final hora = ate == null ? '' : ' às ${DateFormat('HH:mm').format(ate.toLocal())}';
        return 'Conta bloqueada por excesso de tentativas. Tente de novo$hora.';
      case 'conta_inativa':
        return 'Esta conta está desativada.';
      case 'email_ja_cadastrado':
        return 'Já existe uma conta com este e-mail.';
      case 'cpf_ja_cadastrado':
        return 'Já existe uma conta com este CPF.';
      case 'email_invalido':
        return 'E-mail inválido.';
      case 'dados_invalidos':
        final detalhe = dados['detalhe'];
        return (dados['campo'] != null && detalhe is String) ? detalhe : 'Confira os dados informados.';
      case 'nao_autenticado':
        return 'Sua sessão expirou. Entre de novo.';
      case 'sem_permissao':
        return 'Você não tem permissão para isso.';
      case 'usuario_nao_encontrado':
        return 'Usuário não encontrado.';
      case 'nao_pode_desativar_a_si_mesmo':
        return 'Você não pode desativar a própria conta.';
      case 'nao_pode_remover_o_proprio_perfil_administrador':
        return 'Você não pode tirar o seu próprio perfil de administrador.';
      case 'nao_pode_excluir_a_si_mesmo':
        return 'Você não pode excluir a própria conta.';
      case 'modulo_ja_existe':
        return 'Já existe um módulo com este nome.';
      case 'modulo_de_pacote':
        return 'Este módulo vale para todos os usuários e não precisa de liberação.';
      case 'modulo_de_sistema':
        return 'Este módulo é de fábrica: não pode ser excluído nem desativado.';
      case 'modulo_em_uso':
        return 'Este módulo está em uso e não pode ser excluído. Desative-o.';
      case 'modulo_nao_encontrado':
        return 'Módulo não encontrado.';
      case 'perfil_ja_existe':
        return 'Já existe um perfil com este nome.';
      case 'grupo_ja_existe':
        return 'Já existe um grupo com este nome.';
      case 'perfil_administrador_fixo':
        return 'O perfil Administrador é fixo: não dá para mudar suas permissões.';
      case 'perfil_de_sistema':
        return 'Perfis do sistema não podem ser excluídos.';
      case 'perfil_em_uso':
        return 'Este perfil está em uso por usuários ou grupos. Tire-o deles antes de excluir.';
      case 'perfil_nao_encontrado':
        return 'Perfil não encontrado.';
      case 'grupo_nao_encontrado':
        return 'Grupo não encontrado.';
      case 'nao_pode_negar_a_si_mesmo':
        return 'Você não pode negar a si mesmo permissões de administração.';
      case 'referencia_invalida':
        return 'Plano, perfil ou módulo inexistente.';
    }
    if (status == 429) return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
    if (status >= 500) return 'O servidor teve um problema. Tente de novo em instantes.';
    return 'Não foi possível concluir a operação.';
  }
}
