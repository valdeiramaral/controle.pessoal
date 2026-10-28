import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cofre.dart';
import '../../core/lancamento_calculo.dart' show tagsDoTexto, tagsParaTexto;
import '../../core/senha_calculo.dart';
import '../../data/local/banco.dart';
import 'forca_barra.dart';
import 'gerador_dialogo.dart';

/// Abre o cadastro (novo ou edicao). Devolve o id salvo.
Future<String?> abrirCadastroSenha(BuildContext context, {Credencial? credencial}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => SenhaFormPage(credencial: credencial)));

/// Cadastro do cofre: categoria, nome, aplicativo, e-mail, usuario, endereco, Senha ATUAL (com forca e
/// gerador), Senha PADRAO, Ultima Senha Valida, dado secreto, notas, etiquetas, favorito e autopreenchimento.
/// Senhas, dado secreto e notas sao gravados cifrados.
class SenhaFormPage extends ConsumerStatefulWidget {
  const SenhaFormPage({super.key, this.credencial});

  final Credencial? credencial;

  @override
  ConsumerState<SenhaFormPage> createState() => _SenhaFormPageState();
}

class _SenhaFormPageState extends ConsumerState<SenhaFormPage> {
  final _form = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _aplicativo = TextEditingController();
  final _email = TextEditingController();
  final _usuario = TextEditingController();
  final _url = TextEditingController();
  final _atual = TextEditingController();
  final _padrao = TextEditingController();
  final _ultima = TextEditingController();
  final _segredo = TextEditingController();
  final _notas = TextEditingController();
  final _tags = TextEditingController();
  String _tipo = 'acesso';
  bool _favorito = false;
  bool _autopreencher = true;
  final _ver = <String, bool>{'atual': false, 'padrao': false, 'ultima': false, 'segredo': false};
  String _atualOriginal = '';
  String _ultimaOriginal = '';
  bool _carregando = false;
  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.credencial != null;

  @override
  void initState() {
    super.initState();
    final c = widget.credencial;
    if (c != null) {
      _titulo.text = c.titulo;
      _tipo = tiposSenha.containsKey(c.tipo) ? c.tipo : 'acesso';
      _aplicativo.text = c.aplicativo ?? '';
      _email.text = c.email ?? '';
      _usuario.text = c.usuario ?? '';
      _url.text = c.url ?? '';
      _tags.text = tagsDaCredencial(c).join(', ');
      _favorito = c.favorito;
      _autopreencher = c.autopreencher;
      _carregando = true;
      _carregarSegredos(c);
    }
  }

  Future<void> _carregarSegredos(Credencial c) async {
    final cofre = ref.read(cofreProvider);
    try {
      final v = await Future.wait([
        cofre.decifrar(c.senhaAtual),
        cofre.decifrar(c.senhaPadrao),
        cofre.decifrar(c.senhaUltimaValida),
        cofre.decifrar(c.segredo),
        cofre.decifrar(c.notas),
      ]);
      if (!mounted) return;
      setState(() {
        _atual.text = _atualOriginal = v[0];
        _padrao.text = v[1];
        _ultima.text = _ultimaOriginal = v[2];
        _segredo.text = v[3];
        _notas.text = v[4];
        _carregando = false;
      });
    } on CofreIndisponivel catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = '$e Para não perder o que está gravado, não salve esta ficha.';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_titulo, _aplicativo, _email, _usuario, _url, _atual, _padrao, _ultima, _segredo, _notas, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _gerar() async {
    final s = await abrirGeradorDeSenhas(context);
    if (s != null) setState(() => _atual.text = s);
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _salvando = true);
    final banco = ref.read(bancoProvider);
    final cofre = ref.read(cofreProvider);
    try {
      // Ao trocar a Senha ATUAL, a anterior vira a "Ultima Senha Valida" (se voce nao mexeu nela).
      var ultima = _ultima.text;
      if (_editando && _atual.text != _atualOriginal && _atualOriginal.isNotEmpty && ultima == _ultimaOriginal) {
        ultima = _atualOriginal;
      }
      final dados = CredenciaisCompanion(
        titulo: Value(_titulo.text.trim()),
        tipo: Value(_tipo),
        aplicativo: Value(_t(_aplicativo)),
        email: Value(_t(_email)),
        usuario: Value(_t(_usuario)),
        url: Value(_t(_url)),
        senhaAtual: Value(await cofre.cifrar(_atual.text)),
        senhaPadrao: Value(await cofre.cifrar(_padrao.text)),
        senhaUltimaValida: Value(await cofre.cifrar(ultima)),
        segredo: Value(await cofre.cifrar(_segredo.text)),
        notas: Value(await cofre.cifrar(_notas.text)),
        tags: Value(tagsParaTexto(tagsDoTexto(_tags.text))),
        favorito: Value(_favorito),
        autopreencher: Value(_autopreencher),
      );
      final String id;
      if (_editando) {
        id = widget.credencial!.id;
        await banco.atualizarCredencial(id, dados);
      } else {
        id = await banco.inserirCredencial(dados);
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível salvar: $e';
        });
      }
    }
  }

  Widget _campoSenha(String chave, String rotulo, TextEditingController c, {Widget? extra, bool numeroNoRotulo = false}) {
    final k = chave;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        key: Key('campo_${k}_senha'),
        controller: c,
        obscureText: !(_ver[k] ?? false),
        enableSuggestions: false,
        autocorrect: false,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: rotulo,
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (extra != null) extra,
            IconButton(
              key: Key('ver_$k'),
              tooltip: (_ver[k] ?? false) ? 'Ocultar' : 'Mostrar',
              icon: Icon((_ver[k] ?? false) ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _ver[k] = !(_ver[k] ?? false)),
            ),
          ]),
        ),
      ),
      if (k != 'segredo') Padding(padding: const EdgeInsets.only(top: 4), child: ForcaBarra(senha: c.text)),
    ]);
  }

  Widget _espaco() => const SizedBox(height: 12);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar' : 'Novo item do cofre')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final e in tiposSenha.entries)
                      ChoiceChip(
                        key: Key('tipo_${e.key}'),
                        avatar: Icon(iconesTipoSenha[e.key], size: 18),
                        label: Text(e.value),
                        selected: _tipo == e.key,
                        onSelected: (_) => setState(() => _tipo = e.key),
                      ),
                  ]),
                  _espaco(),
                  TextFormField(
                    key: const Key('campo_titulo_senha'),
                    controller: _titulo,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
                  ),
                  _espaco(),
                  TextFormField(key: const Key('campo_aplicativo_senha'), controller: _aplicativo, decoration: const InputDecoration(labelText: 'Aplicativo')),
                  _espaco(),
                  TextFormField(
                      key: const Key('campo_email_senha'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-mail')),
                  _espaco(),
                  TextFormField(key: const Key('campo_usuario_senha'), controller: _usuario, decoration: const InputDecoration(labelText: 'Usuário')),
                  _espaco(),
                  TextFormField(
                      key: const Key('campo_url_senha'),
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Endereço (site)')),
                  _espaco(),
                  _campoSenha(
                    'atual',
                    'Senha ATUAL',
                    _atual,
                    extra: IconButton(key: const Key('gerar_senha'), tooltip: 'Gerar senha', icon: const Icon(Icons.auto_awesome_outlined), onPressed: _gerar),
                  ),
                  _espaco(),
                  _campoSenha('padrao', 'Senha PADRÃO', _padrao),
                  _espaco(),
                  _campoSenha('ultima', 'Última Senha Válida', _ultima),
                  _espaco(),
                  _campoSenha('segredo', rotuloSegredo(_tipo), _segredo),
                  _espaco(),
                  TextFormField(
                    key: const Key('campo_notas_senha'),
                    controller: _notas,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'Notas (cifradas)', alignLabelWithHint: true),
                  ),
                  _espaco(),
                  TextFormField(
                    key: const Key('campo_tags_senha'),
                    controller: _tags,
                    decoration: const InputDecoration(labelText: 'Etiquetas', helperText: 'Separe por vírgula. Ex.: aplicativo, banco'),
                  ),
                  SwitchListTile(
                    key: const Key('campo_favorito_senha'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Favorito'),
                    value: _favorito,
                    onChanged: (v) => setState(() => _favorito = v),
                  ),
                  CheckboxListTile(
                    key: const Key('campo_autopreencher_senha'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Utilizar para preenchimento automático'),
                    value: _autopreencher,
                    onChanged: (v) => setState(() => _autopreencher = v ?? true),
                  ),
                  if (_erro != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_erro!, key: const Key('erro_senha'), style: TextStyle(color: tema.colorScheme.error)),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            FilledButton(key: const Key('botao_salvar_senha'), onPressed: (_salvando || _carregando) ? null : _salvar, child: const Text('Salvar')),
          ]),
        ),
      ),
    );
  }
}
