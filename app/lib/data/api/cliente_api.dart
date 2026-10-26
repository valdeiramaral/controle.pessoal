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
  ErroApi(this.codigo, this.mensagem, {this.status});

  final String codigo;
  final String mensagem;
  final int? status;

  bool get semConexao => codigo == 'sem_conexao';
  bool get naoAutenticado => status == 401 && codigo == 'nao_autenticado';

  @override
  String toString() => mensagem;
}

class UsuarioApi {
  const UsuarioApi({required this.id, required this.nome, this.email, this.idioma, this.pais});

  final String id;
  final String nome;
  final String? email;
  final String? idioma;
  final String? pais;

  factory UsuarioApi.deJson(Map<String, dynamic> j) => UsuarioApi(
        id: j['id'] as String,
        nome: j['nome'] as String,
        email: j['email'] as String?,
        idioma: j['idioma'] as String?,
        pais: j['pais'] as String?,
      );

  Map<String, dynamic> paraJson() =>
      {'id': id, 'nome': nome, 'email': email, 'idioma': idioma, 'pais': pais};
}

class ResultadoLogin {
  const ResultadoLogin({required this.token, required this.expiraEm, required this.usuario});

  final String token;
  final DateTime expiraEm;
  final UsuarioApi usuario;
}

class ClienteApi {
  ClienteApi({required this.baseUrl, http.Client? cliente, this.limite = const Duration(seconds: 15)})
      : _http = cliente ?? http.Client();

  final String baseUrl;
  final Duration limite;
  final http.Client _http;

  Future<void> cadastrar({required String nome, required String email, required String senha}) async {
    await _chamar('POST', '/cadastro', corpo: {'nome': nome.trim(), 'email': email.trim(), 'senha': senha});
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
  Future<UsuarioApi> eu(String token) async {
    final j = await _chamar('GET', '/me', token: token);
    return UsuarioApi.deJson(j['usuario'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _chamar(String metodo, String caminho,
      {Map<String, dynamic>? corpo, String? token}) async {
    final uri = Uri.parse('$baseUrl$caminho');
    final cabecalhos = <String, String>{
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    http.Response r;
    try {
      r = metodo == 'GET'
          ? await _http.get(uri, headers: cabecalhos).timeout(limite)
          : await _http.post(uri, headers: cabecalhos, body: jsonEncode(corpo)).timeout(limite);
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
    throw ErroApi(codigo, _mensagem(r.statusCode, codigo, dados), status: r.statusCode);
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
      case 'email_invalido':
        return 'E-mail inválido.';
      case 'dados_invalidos':
        return 'Confira os dados informados.';
      case 'nao_autenticado':
        return 'Sua sessão expirou. Entre de novo.';
    }
    if (status == 429) return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
    if (status >= 500) return 'O servidor teve um problema. Tente de novo em instantes.';
    return 'Não foi possível concluir a operação.';
  }
}
