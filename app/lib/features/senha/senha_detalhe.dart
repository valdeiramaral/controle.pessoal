import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cofre.dart';
import '../../core/formatos.dart';
import '../../core/lancamento_calculo.dart' show tagsDoTexto, tagsParaTexto;
import '../../core/senha_calculo.dart';
import '../../data/local/banco.dart';
import 'forca_barra.dart';
import 'senha_form_page.dart';

/// Detalhe de um item do cofre (painel da direita): campos, senhas ocultas com o "olho" e a forca,
/// datas, autopreenchimento, Editar, Excluir e Definir etiquetas.
class SenhaDetalhe extends ConsumerStatefulWidget {
  const SenhaDetalhe({super.key, required this.id, this.aoExcluir});

  final String id;
  final VoidCallback? aoExcluir;

  @override
  ConsumerState<SenhaDetalhe> createState() => _SenhaDetalheState();
}

class _Segredos {
  const _Segredos(this.atual, this.padrao, this.ultima, this.segredo, this.notas);
  final String atual, padrao, ultima, segredo, notas;
}

class _SenhaDetalheState extends ConsumerState<SenhaDetalhe> {
  final _ver = <String>{};

  @override
  void initState() {
    super.initState();
    _registrarAcesso();
  }

  @override
  void didUpdateWidget(covariant SenhaDetalhe old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _ver.clear();
      _registrarAcesso();
    }
  }

  void _registrarAcesso() => ref.read(bancoProvider).registrarAcessoCredencial(widget.id);

  Future<_Segredos> _abrir(Credencial c) async {
    final cofre = ref.read(cofreProvider);
    final v = await Future.wait([
      cofre.decifrar(c.senhaAtual),
      cofre.decifrar(c.senhaPadrao),
      cofre.decifrar(c.senhaUltimaValida),
      cofre.decifrar(c.segredo),
      cofre.decifrar(c.notas),
    ]);
    return _Segredos(v[0], v[1], v[2], v[3], v[4]);
  }

  Future<void> _copiar(String texto, String o) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$o copiado(a)')));
  }

  Widget _linha(String chave, String rotulo, String valor,
      {bool secreto = false, bool forca = false, bool copiar = true, Widget? extra}) {
    if (valor.isEmpty) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final aberto = !secreto || _ver.contains(chave);
    return Container(
      key: Key('linha_$chave'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tema.colorScheme.outlineVariant))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: tema.textTheme.bodySmall),
            const SizedBox(height: 2),
            SelectableText(aberto ? valor : '••••••••', key: Key('valor_$chave'), style: tema.textTheme.titleMedium),
            if (forca) Padding(padding: const EdgeInsets.only(top: 4), child: ForcaBarra(senha: valor)),
          ]),
        ),
        if (secreto)
          IconButton(
            key: Key('olho_$chave'),
            tooltip: aberto ? 'Ocultar' : 'Mostrar',
            icon: Icon(aberto ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => aberto ? _ver.remove(chave) : _ver.add(chave)),
          ),
        if (copiar)
          IconButton(key: Key('copiar_$chave'), tooltip: 'Copiar', icon: const Icon(Icons.copy_outlined), onPressed: () => _copiar(valor, rotulo)),
        if (extra != null) extra,
      ]),
    );
  }

  Future<void> _definirEtiquetas(Credencial c) async {
    final ctl = TextEditingController(text: tagsDaCredencial(c).join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Definir etiquetas'),
        content: TextField(
          key: const Key('campo_etiquetas_dialogo'),
          controller: ctl,
          decoration: const InputDecoration(helperText: 'Separe por vírgula. Ex.: aplicativo, banco'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('salvar_etiquetas'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    final texto = ctl.text; // o controlador nao e descartado aqui: o dialogo ainda esta saindo da tela
    if (ok == true) await ref.read(bancoProvider).definirTagsCredencial(c.id, tagsParaTexto(tagsDoTexto(texto)));
  }

  Future<void> _excluir(Credencial c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir item?'),
        content: Text('"${c.titulo}" será excluído do cofre.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('confirmar_exclusao_senha'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(bancoProvider).excluirCredencial(c.id);
    widget.aoExcluir?.call();
  }

  @override
  Widget build(BuildContext context) {
    final banco = ref.watch(bancoProvider);
    return StreamBuilder<List<Credencial>>(
      stream: banco.observarCredenciais(),
      builder: (context, snap) {
        final lista = snap.data ?? const <Credencial>[];
        final achados = lista.where((c) => c.id == widget.id);
        if (achados.isEmpty) return const SizedBox.shrink();
        final c = achados.first;
        final tema = Theme.of(context);
        return FutureBuilder<_Segredos>(
          key: ValueKey('${c.id}_${c.atualizadoEm.microsecondsSinceEpoch}'),
          future: _abrir(c),
          builder: (context, s) {
            if (s.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${s.error}', key: const Key('erro_cofre'), style: TextStyle(color: tema.colorScheme.error)),
              );
            }
            final v = s.data;
            if (v == null) return const Center(child: CircularProgressIndicator());
            final subtitulo = [tiposSenha[c.tipo] ?? c.tipo, ...tagsDaCredencial(c)].join(', ');
            return ListView(
              key: Key('detalhe_${c.id}'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.titulo, key: const Key('detalhe_titulo'), style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(subtitulo, style: tema.textTheme.bodyMedium),
                    ]),
                  ),
                  IconButton(
                    key: const Key('favorito_senha'),
                    tooltip: c.favorito ? 'Remover dos favoritos' : 'Favoritar',
                    icon: Icon(c.favorito ? Icons.star : Icons.star_border, color: Colors.amber.shade700, size: 30),
                    onPressed: () => banco.definirFavoritoCredencial(c.id, !c.favorito),
                  ),
                ]),
                const SizedBox(height: 8),
                _linha('aplicativo', 'Aplicativo', c.aplicativo ?? ''),
                _linha('email', 'E-mail', c.email ?? ''),
                _linha('usuario', 'Usuário', c.usuario ?? ''),
                _linha('url', 'Endereço (site)', c.url ?? ''),
                _linha('atual', 'Senha ATUAL', v.atual, secreto: true, forca: true),
                _linha('padrao', 'Senha PADRÃO', v.padrao, secreto: true, forca: true),
                _linha('ultima', 'Última Senha Válida', v.ultima, secreto: true, forca: true),
                _linha('segredo', rotuloSegredo(c.tipo), v.segredo, secreto: true),
                _linha('notas', 'Notas', v.notas, copiar: false),
                const SizedBox(height: 16),
                Center(
                  child: Column(children: [
                    Text('Modificado: ${formatarDataHora(c.atualizadoEm)}', key: const Key('detalhe_modificado')),
                    const SizedBox(height: 4),
                    Text('Criado: ${formatarDataHora(c.criadoEm)}', key: const Key('detalhe_criado')),
                  ]),
                ),
                CheckboxListTile(
                  key: const Key('detalhe_autopreencher'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Utilizar para preenchimento automático'),
                  value: c.autopreencher,
                  onChanged: (x) => banco.definirAutopreencherCredencial(c.id, x ?? true),
                ),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton(
                    key: const Key('editar_senha'),
                    onPressed: () => abrirCadastroSenha(context, credencial: c),
                    child: const Text('Editar'),
                  ),
                  OutlinedButton(key: const Key('definir_etiquetas'), onPressed: () => _definirEtiquetas(c), child: const Text('Definir etiquetas')),
                  OutlinedButton.icon(
                    key: const Key('excluir_senha'),
                    onPressed: () => _excluir(c),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Excluir'),
                  ),
                ]),
              ],
            );
          },
        );
      },
    );
  }
}

/// Detalhe em tela cheia (celular).
class SenhaDetalhePage extends StatelessWidget {
  const SenhaDetalhePage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cofre de senhas')),
        body: SenhaDetalhe(id: id, aoExcluir: () => Navigator.of(context).maybePop()),
      );
}
