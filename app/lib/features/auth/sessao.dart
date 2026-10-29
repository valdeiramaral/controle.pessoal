import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/aparencia.dart';
import '../../data/api/cliente_api.dart';
import '../../data/auth/acesso_offline.dart';
import '../../data/auth/armazenamento_sessao.dart';

enum FaseSessao { iniciando, deslogado, logado, local }

class EstadoSessao {
  const EstadoSessao(this.fase, {this.usuario, this.token, this.aviso, this.emailLembrado, this.perfil, this.offline = false});

  final FaseSessao fase;
  final UsuarioApi? usuario;
  final String? token;

  /// Entrou sem internet (senha conferida no aparelho): trabalha nos dados locais e,
  /// assim que a internet voltar, o app liga a conta e sincroniza sozinho.
  final bool offline;

  /// Plano, modulos e permissoes do usuario (de GET /me). Nulo offline ou sem conta.
  final PerfilApi? perfil;

  bool pode(String permissao) => perfil?.pode(permissao) ?? false;

  bool get superusuario => perfil?.superusuario ?? false;

  /// Aparencia da conta; sem login (ou offline) vale o padrao.
  Aparencia get aparencia => fase == FaseSessao.logado ? (perfil?.aparencia ?? Aparencia.padrao) : Aparencia.padrao;

  /// Mensagem mostrada na tela de login (ex.: sessao expirada).
  final String? aviso;

  /// E-mail para preencher a tela de login ("Lembrar de mim").
  final String? emailLembrado;
}

final clienteApiProvider = Provider<ClienteApi>((ref) => ClienteApi(baseUrl: urlPadraoApi()));

final cofreOfflineProvider = Provider<CofreOffline>((ref) => CofreOfflineSeguro());

final armazenamentoSessaoProvider =
    Provider<ArmazenamentoSessao>((ref) => ArmazenamentoSeguro());

/// Aparencia do usuario logado (padrao quando ninguem esta logado).
final aparenciaProvider = Provider<Aparencia>((ref) => ref.watch(sessaoProvider.select((s) => s.aparencia)));

final sessaoProvider =
    NotifierProvider<SessaoNotifier, EstadoSessao>(SessaoNotifier.new);

class SessaoNotifier extends Notifier<EstadoSessao> {
  ClienteApi get _api => ref.read(clienteApiProvider);
  ArmazenamentoSessao get _guarda => ref.read(armazenamentoSessaoProvider);
  CofreOffline get _cofre => ref.read(cofreOfflineProvider);

  // Entrada offline: a senha digitada fica so na memoria, para ligar a conta quando a internet voltar.
  String? _senhaOffline;
  Timer? _religar;
  bool _religando = false;
  static const _intervaloReligar = Duration(seconds: 30);

  @override
  EstadoSessao build() {
    ref.onDispose(() => _religar?.cancel());
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
    final ResultadoLogin r;
    try {
      r = await _api.entrar(email: email, senha: senha);
    } on ErroApi catch (e) {
      if (!e.semConexao) rethrow;
      await _entrarOffline(email, senha, e);
      return;
    }
    _pararReligar();
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
    // Deixa o aparelho pronto para abrir sem internet da proxima vez.
    unawaited(_cofre.guardar(email, senha, usuario, perfil));
  }

  /// Sem internet: confere e-mail e senha com a verificacao guardada neste aparelho.
  Future<void> _entrarOffline(String email, String senha, ErroApi semRede) async {
    final acesso = await _cofre.verificar(email, senha);
    if (acesso == null) {
      if (await _cofre.existe(email)) {
        throw ErroApi('credenciais_invalidas', 'E-mail ou senha incorretos. (Sem internet: conferido só neste aparelho.)');
      }
      throw ErroApi('sem_conexao',
          'Sem internet, e este aparelho ainda não tem acesso offline para esse e-mail. Entre uma vez com internet.');
    }
    _senhaOffline = senha;
    state = EstadoSessao(FaseSessao.logado,
        usuario: acesso.usuario, perfil: acesso.perfil, emailLembrado: state.emailLembrado, offline: true);
    _religar?.cancel();
    _religar = Timer.periodic(_intervaloReligar, (_) => religarConta());
  }

  /// Offline: tenta de novo o login de verdade. Se a internet voltou, passa a sessao para online
  /// (com token), o que liga a sincronizacao. Devolve true se religou.
  Future<bool> religarConta() async {
    final senha = _senhaOffline;
    final email = state.usuario?.email;
    if (!state.offline || senha == null || email == null || _religando) return false;
    _religando = true;
    try {
      final r = await _api.entrar(email: email, senha: senha);
      PerfilApi? perfil;
      try {
        perfil = await _api.eu(r.token);
      } catch (_) {}
      final usuario = perfil?.usuario ?? r.usuario;
      if (usuario.id != state.usuario?.id) return false;
      final salva = await _guarda.ler();
      await _guarda.gravar(SessaoSalva(
        token: r.token,
        expiraEm: r.expiraEm,
        usuario: usuario,
        emailLembrado: salva?.emailLembrado,
        senhaLembrada: salva?.senhaLembrada,
      ));
      _pararReligar();
      state = EstadoSessao(FaseSessao.logado,
          usuario: usuario, token: r.token, emailLembrado: state.emailLembrado, perfil: perfil ?? state.perfil);
      unawaited(_cofre.guardar(email, senha, usuario, perfil ?? state.perfil));
      return true;
    } on ErroApi catch (e) {
      // Sem internet: segue offline. Senha que mudou no servidor: para de tentar e mantem offline.
      if (!e.semConexao && e.status != null && e.status! < 500) _pararReligar(manterOffline: true);
      return false;
    } catch (_) {
      return false;
    } finally {
      _religando = false;
    }
  }

  void _pararReligar({bool manterOffline = false}) {
    _religar?.cancel();
    _religar = null;
    if (!manterOffline) _senhaOffline = null;
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
        perfil: p?.copiarCom(usuario: u));
  }

  /// Troca a senha da conta. Lanca [ErroApi] se a atual estiver errada.
  /// Se o aparelho lembra a senha ("Lembrar de mim"), guarda a nova no lugar da antiga.
  Future<void> alterarSenha(String senhaAtual, String senhaNova) async {
    final token = state.token;
    if (token == null) return;
    await _api.alterarSenha(token, senhaAtual: senhaAtual, senhaNova: senhaNova);
    final u = state.usuario;
    if (u?.email != null) unawaited(_cofre.guardar(u!.email!, senhaNova, u, state.perfil));
    final salva = await _guarda.ler();
    if (salva != null && salva.senhaLembrada != null) {
      await _guarda.gravar(SessaoSalva(
        token: salva.token,
        expiraEm: salva.expiraEm,
        usuario: salva.usuario,
        emailLembrado: salva.emailLembrado,
        senhaLembrada: senhaNova,
      ));
    }
  }

  /// Aplica na hora a aparencia escolhida e guarda na conta (a tela nao espera a rede).
  /// Devolve a mensagem de erro se nao conseguiu guardar; a aparencia continua valendo ate sair.
  Future<String?> definirAparencia(Aparencia nova) async {
    final p = state.perfil;
    final token = state.token;
    if (p == null || token == null) return null;
    state = EstadoSessao(FaseSessao.logado,
        usuario: state.usuario, token: token, emailLembrado: state.emailLembrado, perfil: p.copiarCom(aparencia: nova));
    try {
      await _api.salvarAparencia(token, nova);
      return null;
    } on ErroApi catch (e) {
      return e.mensagem;
    }
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
    _pararReligar();
    final email = (await _guarda.ler())?.emailLembrado;
    if (email != null) {
      await _guarda.gravar(SessaoSalva(emailLembrado: email));
    } else {
      await _guarda.limpar();
    }
    state = EstadoSessao(FaseSessao.deslogado, emailLembrado: email);
  }
}
