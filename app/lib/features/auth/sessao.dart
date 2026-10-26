import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../../data/auth/armazenamento_sessao.dart';

enum FaseSessao { iniciando, deslogado, logado, local }

class EstadoSessao {
  const EstadoSessao(this.fase, {this.usuario, this.token, this.aviso});

  final FaseSessao fase;
  final UsuarioApi? usuario;
  final String? token;

  /// Mensagem mostrada na tela de login (ex.: sessao expirada).
  final String? aviso;
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

  /// Reabre a sessao guardada. Sem internet, continua logado com os dados guardados
  /// (o app funciona offline); com token recusado pelo servidor, volta ao login.
  Future<void> restaurar() async {
    final salva = await _guarda.ler();
    if (salva == null) {
      state = const EstadoSessao(FaseSessao.deslogado);
      return;
    }
    if (salva.local) {
      state = const EstadoSessao(FaseSessao.local);
      return;
    }
    final token = salva.token;
    if (token == null || salva.usuario == null) {
      state = const EstadoSessao(FaseSessao.deslogado);
      return;
    }
    try {
      final u = await _api.eu(token);
      await _guarda.gravar(SessaoSalva(token: token, expiraEm: salva.expiraEm, usuario: u));
      state = EstadoSessao(FaseSessao.logado, usuario: u, token: token);
    } on ErroApi catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _guarda.limpar();
        state = EstadoSessao(FaseSessao.deslogado, aviso: e.mensagem);
      } else {
        state = EstadoSessao(FaseSessao.logado, usuario: salva.usuario, token: token);
      }
    }
  }

  /// Lanca [ErroApi] em caso de falha (a tela mostra a mensagem).
  Future<void> entrar(String email, String senha) async {
    final r = await _api.entrar(email: email, senha: senha);
    await _guarda.gravar(SessaoSalva(token: r.token, expiraEm: r.expiraEm, usuario: r.usuario));
    state = EstadoSessao(FaseSessao.logado, usuario: r.usuario, token: r.token);
  }

  Future<void> cadastrar(String nome, String email, String senha) async {
    await _api.cadastrar(nome: nome, email: email, senha: senha);
    await entrar(email, senha);
  }

  Future<void> continuarSemConta() async {
    await _guarda.gravar(const SessaoSalva(local: true));
    state = const EstadoSessao(FaseSessao.local);
  }

  Future<void> sair() async {
    await _guarda.limpar();
    state = const EstadoSessao(FaseSessao.deslogado);
  }
}
