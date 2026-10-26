import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

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
  const PerfilApi({required this.usuario, this.plano, this.modulos = const [], this.permissoes = const []});

  final UsuarioApi usuario;
  final String? plano;
  final List<String> modulos;
  final List<String> permissoes;

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
  const DetalheUsuario({required this.usuario, this.plano, this.perfis = const [], this.modulos = const []});

  final UsuarioApi usuario;
  final String? plano;
  final List<String> perfis;
  final List<ModuloUsuario> modulos;

  factory DetalheUsuario.deJson(Map<String, dynamic> j) => DetalheUsuario(
        usuario: UsuarioApi.deJson(j['usuario'] as Map<String, dynamic>),
        plano: (j['licenca'] as Map<String, dynamic>?)?['plano'] as String?,
        perfis: (j['perfis'] as List? ?? const []).cast<String>(),
        modulos: (j['modulos'] as List? ?? const [])
            .map((e) => ModuloUsuario.deJson(e as Map<String, dynamic>))
            .toList(),
      );
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
    );
  }

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
      case 'referencia_invalida':
        return 'Plano, perfil ou módulo inexistente.';
    }
    if (status == 429) return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
    if (status >= 500) return 'O servidor teve um problema. Tente de novo em instantes.';
    return 'Não foi possível concluir a operação.';
  }
}
