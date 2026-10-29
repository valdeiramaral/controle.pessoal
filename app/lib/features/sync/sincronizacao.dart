import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../../data/local/banco.dart';
import '../../data/sync/servico_sincronizacao.dart';
import '../auth/sessao.dart';

class EstadoSincronizacao {
  const EstadoSincronizacao({this.sincronizando = false, this.ultimaVez, this.erro, this.ultimo});

  final bool sincronizando;
  final DateTime? ultimaVez;

  /// Mensagem da ultima tentativa que falhou (sem internet, API fora do ar...). Nulo se deu certo.
  final String? erro;
  final ResultadoSync? ultimo;
}

/// Mantem este aparelho igual ao servidor: sincroniza ao entrar, alguns segundos depois de salvar
/// qualquer dado, a cada poucos minutos e quando o usuario pede. Sem internet nao atrapalha:
/// tenta de novo depois.
final sincronizacaoProvider =
    NotifierProvider<SincronizacaoNotifier, EstadoSincronizacao>(SincronizacaoNotifier.new);

class SincronizacaoNotifier extends Notifier<EstadoSincronizacao> {
  Timer? _periodico;
  Timer? _adiar;
  StreamSubscription<Set<TableUpdate>>? _mudancas;
  bool _rodando = false;

  /// Liga a sincronizacao sozinha (ao entrar, ao salvar e a cada poucos minutos). Os testes desligam.
  static bool automatica = true;

  static const _depoisDeSalvar = Duration(seconds: 4);
  static const _intervalo = Duration(minutes: 3);

  @override
  EstadoSincronizacao build() {
    ref.onDispose(_parar);
    // Entrou (ou trocou de conta): comeca a sincronizar; saiu: para.
    ref.listen<String?>(sessaoProvider.select((s) => s.fase == FaseSessao.logado ? s.token : null),
        (antes, agora) {
      _parar();
      if (agora != null) _iniciar();
    }, fireImmediately: true);
    return const EstadoSincronizacao();
  }

  bool get _habilitado {
    final s = ref.read(sessaoProvider);
    // So com conta e se o plano/perfil liberou a sincronizacao (offline sem perfil: tenta mesmo assim).
    return s.fase == FaseSessao.logado && s.token != null && (s.perfil == null || s.pode('sincronizacao.sincronizar'));
  }

  void _iniciar() {
    if (!automatica) return;
    _periodico = Timer.periodic(_intervalo, (_) => sincronizar());
    _escutarBanco(); // o Banco troca junto com a conta: _parar/_iniciar rodam de novo
    _adiarSincronizacao(const Duration(seconds: 1));
  }

  void _escutarBanco() {
    _mudancas?.cancel();
    _mudancas = ref.read(bancoProvider).tableUpdates().listen((_) {
      if (!_rodando) _adiarSincronizacao(_depoisDeSalvar);
    });
  }

  void _adiarSincronizacao(Duration espera) {
    _adiar?.cancel();
    _adiar = Timer(espera, sincronizar);
  }

  void _parar() {
    _periodico?.cancel();
    _adiar?.cancel();
    _mudancas?.cancel();
    _periodico = _adiar = null;
    _mudancas = null;
  }

  /// Sincroniza agora. Devolve o resultado, ou null se nao deu (sem conta, ja rodando ou erro; veja [state]).
  Future<ResultadoSync?> sincronizar() async {
    if (_rodando || !_habilitado) return null;
    final token = ref.read(sessaoProvider).token!;
    _rodando = true;
    state = EstadoSincronizacao(sincronizando: true, ultimaVez: state.ultimaVez, erro: null, ultimo: state.ultimo);
    try {
      final r = await ServicoSincronizacao(
        banco: ref.read(bancoProvider),
        api: ref.read(clienteApiProvider),
        token: token,
      ).sincronizar();
      state = EstadoSincronizacao(ultimaVez: DateTime.now(), ultimo: r);
      return r;
    } on ErroApi catch (e) {
      state = EstadoSincronizacao(ultimaVez: state.ultimaVez, erro: e.mensagem, ultimo: state.ultimo);
      return null;
    } catch (e) {
      state = EstadoSincronizacao(
          ultimaVez: state.ultimaVez, erro: 'Não foi possível sincronizar agora.', ultimo: state.ultimo);
      return null;
    } finally {
      _rodando = false;
    }
  }
}

/// Texto curto com a situacao da sincronizacao (para o menu).
String textoSincronizacao(EstadoSincronizacao e) {
  if (e.sincronizando) return 'Sincronizando...';
  if (e.erro != null) return e.erro!;
  final v = e.ultimaVez;
  if (v == null) return 'Ainda não sincronizado nesta sessão';
  String dois(int n) => n.toString().padLeft(2, '0');
  return 'Última vez às ${dois(v.hour)}:${dois(v.minute)}';
}

/// Botao "Sincronizar agora": roda e mostra o resultado numa mensagem.
Future<void> sincronizarAgora(BuildContext context, WidgetRef ref) async {
  final msg = ScaffoldMessenger.maybeOf(context);
  final r = await ref.read(sincronizacaoProvider.notifier).sincronizar();
  final e = ref.read(sincronizacaoProvider);
  final texto = r == null
      ? (e.erro ?? 'A sincronização já está em andamento ou não está liberada para esta conta.')
      : r.aplicados == 0
          ? 'Tudo sincronizado.'
          : 'Sincronizado: ${r.aplicados} ${r.aplicados == 1 ? 'registro novo ou alterado' : 'registros novos ou alterados'} neste aparelho.';
  msg?.showSnackBar(SnackBar(content: Text(texto)));
}
