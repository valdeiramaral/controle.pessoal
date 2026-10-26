import '../local/banco.dart';

/// Sincronizacao entre o banco local (Drift) e o servidor (PostgreSQL).
///
/// Regras definidas no escopo:
///  - ids sao UUID gerados no aparelho;
///  - envia o que mudou desde o ultimo envio (atualizado_em > ultimoSync);
///  - recebe o que mudou no servidor desde o ultimo recebimento;
///  - conflito: a ultima edicao vence, campo a campo;
///  - exclusoes sao logicas (excluido_em), nunca apagadas na hora.
///
/// ESQUELETO: ainda sem chamadas de rede. Falta definir o servidor
/// (API propria ou Supabase) para implementar [enviar] e [receber].
class ServicoSincronizacao {
  ServicoSincronizacao(this.banco);

  final Banco banco;

  Future<void> sincronizar() async {
    final desde = await _ultimoSync();
    await enviar(desde);
    await receber(desde);
    await _gravarUltimoSync(DateTime.now().toUtc());
  }

  Future<void> enviar(DateTime? desde) async {
    // TODO: ler registros com atualizado_em > desde de cada tabela
    // e enviar em lote para a API.
  }

  Future<void> receber(DateTime? desde) async {
    // TODO: buscar alteracoes do servidor e aplicar com a regra de conflito.
  }

  Future<DateTime?> _ultimoSync() async => null; // TODO: guardar em preferencias
  Future<void> _gravarUltimoSync(DateTime quando) async {}
}
