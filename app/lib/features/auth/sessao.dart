import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../../data/auth/armazenamento_sessao.dart';

enum FaseSessao { iniciando, deslogado, logado, local }

class EstadoSessao {
  const EstadoSessao(this.fase, {this.usuario, this.token, this.aviso, this.emailLembrado, this.perfil});

  final FaseSessao fase;
  final UsuarioApi? usuario;
  final String? token;

  /// Plano, modulos e permissoes do usuario (de GET /me). Nulo offline ou sem conta.
  final PerfilApi? perfil;

  bool pode(String permissao) => perfil?.pode(permissao) ?? false;

  bool get superusuario => perfil?.superusuario ?? false;

  /// Mensagem mostrada na tela de login (ex.: sessao expirada).
  final String? aviso;

  /// E-mail para preencher a tela de login ("Lembrar de mim").
  final String? emailLembrado;
}

final clienteApiProvider = Provider<ClienteApi>((ref) => ClienteApi(baseUrl: urlPadraoApi()));

final armazenamentoSessaoProvider =
    Provider<ArmazenamentoSessao>((ref) => ArmazenamentoSeguro());

final sessaoProvider =
    NotifierProvider<SessaoNotifier, EstadoSessao>(SessaoNotifier.new);

class SessaoNotifier extends Notifier<EstadoSessao> {
  ClienteApi get _api => ref.read(clienteApiProvider);
  ArmazenamentoSessao get _guarda => ref.read(armazenamentoSessaoProvider);

  @override
  EstadoSessao build() {
    Future.microtask(restaurar);
    return const EstadoSessao(FaseSessao.iniciando);
  }

  /// Ao abrir o app, o login e sempre obrigatorio: nenhuma sessao guardada reabre sozinha.
  /// So o e-mail lembrado (se o usuario pediu) volta preenchido; token e senha guardados sao apagados.
  Future<void> restaurar() async {
    final salva = await _guarda.ler();
    final email = salva?.emailLembrado;
    if (salva != null) {
      if (email != null) {
        await _guarda.gravar(SessaoSalva(emailLembrado: email));
      } else {
        await _guarda.limpar();
      }
    }
    state = EstadoSessao(FaseSessao.deslogado, emailLembrado: email);
  }

  /// Lanca [ErroApi] em caso de falha (a tela mostra a mensagem).
  ///
  /// [lembrar]: guarda o e-mail (para preencher o login) e, fora da web, a senha
  /// no cofre do aparelho, para entrar sozinho quando o token vencer.
  Future<void> entrar(String email, String senha, {bool lembrar = false}) async {
    final r = await _api.entrar(email: email, senha: senha);
    final emailGuardado = lembrar ? email.trim() : null;
    // Busca dados completos, plano e permissoes; se falhar, segue so com o basico do login.
    PerfilApi? perfil;
    try {
      perfil = await _api.eu(r.token);
    } on ErroApi {
      perfil = null;
    } catch (_) {
      perfil = null;
    }
    final usuario = perfil?.usuario ?? r.usuario;
    await _guarda.gravar(SessaoSalva(
      token: r.token,
      expiraEm: r.expiraEm,
      usuario: usuario,
      emailLembrado: emailGuardado,
      senhaLembrada: (lembrar && !kIsWeb) ? senha : null,
    ));
    state = EstadoSessao(FaseSessao.logado,
        usuario: usuario, token: r.token, emailLembrado: emailGuardado, perfil: perfil);
  }

  /// Atualiza os dados do proprio usuario (PATCH /me) e a sessao.
  Future<void> atualizarMeusDados(Map<String, dynamic> corpo) async {
    final token = state.token;
    if (token == null) return;
    final u = await _api.atualizarMeusDados(token, corpo);
    final salva = await _guarda.ler();
    if (salva != null) {
      await _guarda.gravar(SessaoSalva(
        token: salva.token,
        expiraEm: salva.expiraEm,
        usuario: u,
        emailLembrado: salva.emailLembrado,
        senhaLembrada: salva.senhaLembrada,
      ));
    }
    final p = state.perfil;
    state = EstadoSessao(FaseSessao.logado,
        usuario: u,
        token: token,
        emailLembrado: state.emailLembrado,
        perfil: p == null
            ? null
            : PerfilApi(
                usuario: u,
                plano: p.plano,
                modulos: p.modulos,
                permissoes: p.permissoes,
                superusuario: p.superusuario));
  }

  Future<void> cadastrar(
    String nome,
    String email,
    String senha, {
    required String cpf,
    required String telefone,
    String? nascimento,
    Map<String, dynamic>? endereco,
    bool lembrar = false,
  }) async {
    await _api.cadastrar(
        nome: nome, email: email, senha: senha, cpf: cpf, telefone: telefone, nascimento: nascimento, endereco: endereco);
    await entrar(email, senha, lembrar: lembrar);
  }

  /// Busca de novo os dados e permissoes da conta (GET /me). Devolve a mensagem de erro, ou null se deu certo.
  Future<String?> recarregarPerfil() async {
    final token = state.token;
    if (token == null) return 'Sem sessão.';
    try {
      final p = await _api.eu(token);
      state = EstadoSessao(FaseSessao.logado,
          usuario: p.usuario, token: token, emailLembrado: state.emailLembrado, perfil: p);
      return null;
    } on ErroApi catch (e) {
      return e.mensagem;
    } catch (e) {
      return 'Resposta inesperada do servidor: $e';
    }
  }

  /// Sair apaga o token e a senha guardada; so o e-mail lembrado continua.
  Future<void> sair() async {
    final email = (await _guarda.ler())?.emailLembrado;
    if (email != null) {
      await _guarda.gravar(SessaoSalva(emailLembrado: email));
    } else {
      await _guarda.limpar();
    }
    state = EstadoSessao(FaseSessao.deslogado, emailLembrado: email);
  }
}
