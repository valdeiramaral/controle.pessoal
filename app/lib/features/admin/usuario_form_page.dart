import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documentos.dart';
import '../../data/api/cliente_api.dart';
import '../auth/campos_pessoa.dart';
import '../auth/sessao.dart';
import '../auth/validacoes.dart';
import '../auth/widgets_auth.dart';
import 'widgets_acesso.dart';
import '../nav/acoes_usuario.dart';

/// Cadastro e edicao de usuario pelo administrador: dados da pessoa, plano,
/// perfis e modulos liberados.
class UsuarioFormPage extends ConsumerStatefulWidget {
  const UsuarioFormPage({super.key, this.usuarioId});

  /// Nulo = novo usuario.
  final String? usuarioId;

  @override
  ConsumerState<UsuarioFormPage> createState() => _UsuarioFormPageState();
}

class _UsuarioFormPageState extends ConsumerState<UsuarioFormPage> {
  final _form = GlobalKey<FormState>();
  final _senha = TextEditingController();
  DadosPessoaisControladores _d = DadosPessoaisControladores();

  CatalogoApi? _catalogo;
  DetalheUsuario? _original;
  String _plano = 'gratuito';
  Set<String> _perfis = {'usuario'};
  Map<String, String> _modulos = {}; // codigo -> padrao | liberado | bloqueado
  bool _ativo = true;
  bool _ver = false;
  List<GrupoItem> _gruposDisponiveis = const [];
  Set<String> _grupos = {};
  List<PermissaoApi> _catalogoPermissoes = const [];
  Map<String, String> _excecoes = {}; // codigo -> herdar | permitir | negar

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  bool get _novo => widget.usuarioId == null;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _d.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final token = ref.read(sessaoProvider).token;
    if (token == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final api = ref.read(clienteApiProvider);
      final cat = await api.catalogo(token);
      DetalheUsuario? det;
      if (!_novo) det = await api.detalheUsuario(token, widget.usuarioId!);
      var grupos = const <GrupoItem>[];
      var permissoes = const <PermissaoApi>[];
      grupos = await api.listarGrupos(token);
      if (ref.read(sessaoProvider).pode('acesso.perfil.gerenciar')) permissoes = await api.listarPermissoes(token);
      if (!mounted) return;
      setState(() {
        _catalogo = cat;
        _original = det;
        _gruposDisponiveis = grupos;
        _catalogoPermissoes = permissoes;
        if (det != null) {
          _grupos = det.grupos.map((g) => g.id).toSet();
          _excecoes = {for (final e in det.excecoes.entries) e.key: e.value ? 'permitir' : 'negar'};
          _d.dispose();
          _d = DadosPessoaisControladores(det.usuario);
          _plano = det.plano ?? 'gratuito';
          _perfis = det.perfis.toSet();
          _ativo = det.usuario.ativo;
          _modulos = {for (final m in det.modulos) m.codigo: m.liberacao};
        } else {
          _modulos = {for (final m in cat.modulos) m.codigo: 'padrao'};
        }
      });
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Map<String, dynamic> _corpoPessoa() => {
        'nome': _d.nome.text.trim(),
        'email': _d.email.text.trim(),
        'cpf': soDigitos(_d.cpf.text),
        'telefone': soDigitos(_d.telefone.text),
        'nascimento': _d.nascimentoIso(),
        'endereco': _d.enderecoJson(),
      };

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final sessao = ref.read(sessaoProvider);
    final token = sessao.token;
    if (token == null) return;
    final api = ref.read(clienteApiProvider);
    final podePlano = sessao.pode('licencas.licenca.conceder');
    final podePerfis = sessao.pode('acesso.perfil.gerenciar');
    final podeModulos = sessao.pode('administracao.liberacao.gerenciar');
    final podeGrupos = sessao.pode('acesso.grupo.gerenciar');
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      if (_novo) {
        final corpo = _corpoPessoa()
          ..['senha'] = _senha.text
          ..['endereco'] = (_d.enderecoJson()..removeWhere((_, v) => v == null))
          ..removeWhere((k, v) => v == null || (v is Map && v.isEmpty));
        if (podePlano) corpo['plano'] = _plano;
        if (podePerfis) corpo['perfis'] = _perfis.toList();
        if (podeModulos) {
          corpo['modulos'] = {
            for (final e in _modulos.entries)
              if (e.value != 'padrao') e.key: e.value == 'liberado',
          };
        }
        final criado = await api.criarUsuario(token, corpo);
        final novoId = criado.usuario.id;
        if (podeGrupos && _grupos.isNotEmpty) await api.definirGrupos(token, novoId, _grupos.toList());
        if (podePerfis) {
          final ex = <String, bool?>{
            for (final e in _excecoes.entries)
              if (e.value != 'herdar') e.key: e.value == 'permitir',
          };
          if (ex.isNotEmpty) await api.definirExcecoes(token, novoId, ex);
        }
      } else {
        final id = widget.usuarioId!;
        final original = _original!;
        final corpo = _corpoPessoa()..['nascimento'] = _d.nascimentoIso() ?? '';
        if (id != sessao.usuario?.id) corpo['ativo'] = _ativo;
        await api.atualizarUsuario(token, id, corpo);
        if (podePlano && _plano != (original.plano ?? 'gratuito')) await api.definirPlano(token, id, _plano);
        if (podePerfis && !_mesmos(_perfis, original.perfis.toSet())) {
          await api.definirPerfis(token, id, _perfis.toList());
        }
        if (podeGrupos && !_mesmos(_grupos, original.grupos.map((g) => g.id).toSet())) {
          await api.definirGrupos(token, id, _grupos.toList());
        }
        if (podePerfis) {
          final antesEx = {for (final e in original.excecoes.entries) e.key: e.value ? 'permitir' : 'negar'};
          final mud = <String, bool?>{};
          for (final cod in {...antesEx.keys, ..._excecoes.keys}) {
            final antes = antesEx[cod] ?? 'herdar';
            final agora = _excecoes[cod] ?? 'herdar';
            if (antes != agora) mud[cod] = switch (agora) { 'permitir' => true, 'negar' => false, _ => null };
          }
          if (mud.isNotEmpty) await api.definirExcecoes(token, id, mud);
        }
        if (podeModulos) {
          final antes = {for (final m in original.modulos) m.codigo: m.liberacao};
          final mudancas = <String, bool?>{
            for (final e in _modulos.entries)
              if (antes[e.key] != e.value)
                e.key: switch (e.value) { 'liberado' => true, 'bloqueado' => false, _ => null },
          };
          if (mudancas.isNotEmpty) await api.definirModulos(token, id, mudancas);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_novo ? 'Usuário cadastrado.' : 'Alterações salvas.')),
      );
      Navigator.of(context).pop(true);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir usuário?'),
        content: Text('A conta de "${_original?.usuario.nome}" será removida e a pessoa não conseguirá mais entrar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('confirmar_exclusao'), onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    final token = ref.read(sessaoProvider).token;
    if (token == null) return;
    try {
      await ref.read(clienteApiProvider).excluirUsuario(token, widget.usuarioId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuário excluído.')));
      Navigator.of(context).pop(true);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  bool _mesmos(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  Widget _cartao(String titulo, IconData icone, List<Widget> filhos) {
    final tema = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icone, color: tema.colorScheme.primary),
              const SizedBox(width: 8),
              Text(titulo, style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 14),
            ...filhos,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessao = ref.watch(sessaoProvider);
    final cat = _catalogo;
    return Scaffold(
      appBar: AppBar(
        title: Text(_novo ? 'Novo usuário' : 'Editar usuário'),
        actions: [
          if (!_novo && sessao.pode('acesso.usuario.editar') && widget.usuarioId != sessao.usuario?.id)
            IconButton(key: const Key('botao_excluir'), tooltip: 'Excluir usuário', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
          const AcoesUsuario(),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : cat == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_erro ?? 'Não foi possível carregar.', key: const Key('mensagem_erro')),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                    ]),
                  ),
                )
              : _formulario(cat, sessao),
    );
  }

  Widget _formulario(CatalogoApi cat, EstadoSessao sessao) {
    final podePlano = sessao.pode('licencas.licenca.conceder');
    final podePerfis = sessao.pode('acesso.perfil.gerenciar');
    final podeModulos = sessao.pode('administracao.liberacao.gerenciar');
    final ehEu = widget.usuarioId != null && widget.usuarioId == sessao.usuario?.id;
    final tema = Theme.of(context);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _cartao('Dados da pessoa', Icons.person_outline, [
                  campoNome(context, _d),
                  const SizedBox(height: 12),
                  campoEmail(context, _d),
                  const SizedBox(height: 12),
                  campoCpf(context, _d),
                  const SizedBox(height: 12),
                  campoTelefone(context, _d),
                  if (_novo) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('campo_senha'),
                      controller: _senha,
                      obscureText: !_ver,
                      decoration: decoracaoCampo(context, 'Senha inicial (mínimo 8 caracteres)', Icons.lock_outline,
                          sufixo: IconButton(
                            icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _ver = !_ver),
                          )),
                      validator: validarSenhaNova,
                    ),
                  ],
                  const SizedBox(height: 6),
                  SecaoOpcional(c: _d, aberta: _d.temOpcionais),
                ]),
                _cartao('Plano e perfil', Icons.workspace_premium_outlined, [
                  DropdownButtonFormField<String>(
                    key: const Key('campo_plano'),
                    value: cat.planos.any((p) => p.codigo == _plano) ? _plano : null,
                    decoration: decoracaoCampo(context, 'Tipo de plano', Icons.card_membership_outlined),
                    items: [for (final p in cat.planos) DropdownMenuItem(value: p.codigo, child: Text(p.nome))],
                    onChanged: podePlano ? (v) => setState(() => _plano = v ?? _plano) : null,
                  ),
                  const SizedBox(height: 14),
                  Text('Perfil de acesso', style: tema.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final p in cat.perfis)
                      FilterChip(
                        key: Key('perfil_${p.codigo}'),
                        label: Text(p.nome),
                        selected: _perfis.contains(p.codigo),
                        onSelected: podePerfis
                            ? (v) => setState(() {
                                  if (v) {
                                    _perfis.add(p.codigo);
                                  } else if (_perfis.length > 1) {
                                    _perfis.remove(p.codigo);
                                  }
                                })
                            : null,
                      ),
                  ]),
                  if (!_novo) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('campo_ativo'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Conta ativa'),
                      subtitle: Text(ehEu ? 'Você não pode desativar a própria conta.' : 'Desativada, a pessoa não consegue entrar.'),
                      value: _ativo,
                      onChanged: ehEu ? null : (v) => setState(() => _ativo = v),
                    ),
                  ],
                ]),
                ...[
                  _cartao('Grupos', Icons.groups_outlined, [
                    Text('O usuário recebe também as permissões dos perfis de cada grupo.', style: tema.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (_gruposDisponiveis.isEmpty)
                      const Text('Nenhum grupo criado ainda.', key: Key('sem_grupos'))
                    else
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final g in _gruposDisponiveis)
                          FilterChip(
                            key: Key('grupo_${g.id}'),
                            label: Text(g.nome),
                            selected: _grupos.contains(g.id),
                            onSelected: sessao.pode('acesso.grupo.gerenciar')
                                ? (v) => setState(() => v ? _grupos.add(g.id) : _grupos.remove(g.id))
                                : null,
                          ),
                      ]),
                  ]),
                  if (podePerfis && _catalogoPermissoes.isNotEmpty)
                    _cartao('Exceções de permissão', Icons.tune_outlined, [
                      Text('Herdar = vale o que vem dos perfis e grupos. Negar sempre vence.',
                          style: tema.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      ExcecoesPermissoes(
                        catalogo: _catalogoPermissoes,
                        valores: _excecoes,
                        efetivas: (_original?.permissoes ?? const <String>[]).toSet(),
                        aoMudar: (cod, v) => setState(() => _excecoes[cod] = v),
                      ),
                    ]),
                ],
                _cartao('Módulos liberados', Icons.apps_outlined, [
                  Text('Padrão = vale o que o plano libera. Libere ou bloqueie para este usuário.',
                      style: tema.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (final m in cat.modulos) _linhaModulo(m, podeModulos),
                ]),
                if (_erro != null) ...[
                  CaixaMensagem(texto: _erro!),
                  const SizedBox(height: 12),
                ],
                KeyedSubtree(
                  key: const Key('botao_salvar'),
                  child: BotaoPrincipal(
                    texto: _novo ? 'Cadastrar usuário' : 'Salvar alterações',
                    enviando: _salvando,
                    aoPressionar: _salvar,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linhaModulo(OpcaoCatalogo m, bool pode) {
    final atual = _modulos[m.codigo] ?? 'padrao';
    final efetivo = _original?.modulos.where((x) => x.codigo == m.codigo).firstOrNull?.efetivo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(m.nome, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (efetivo != null)
              Text(efetivo ? 'Ativo' : 'Inativo',
                  style: TextStyle(
                      fontSize: 12,
                      color: efetivo ? Colors.green.shade700 : Theme.of(context).colorScheme.error)),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              key: Key('modulo_${m.codigo}'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'padrao', label: Text('Padrão')),
                ButtonSegment(value: 'liberado', label: Text('Liberado')),
                ButtonSegment(value: 'bloqueado', label: Text('Bloqueado')),
              ],
              selected: {atual},
              onSelectionChanged: pode ? (s) => setState(() => _modulos[m.codigo] = s.first) : null,
            ),
          ),
        ],
      ),
    );
  }
}
