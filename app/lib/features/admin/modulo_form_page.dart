import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icones_modulo.dart';
import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';
import '../auth/widgets_auth.dart';
import '../nav/modulos_menu.dart';

/// Cria ou edita um modulo. Ao salvar, o menu lateral se atualiza.
class ModuloFormPage extends ConsumerStatefulWidget {
  const ModuloFormPage({super.key, this.modulo});

  /// Nulo = novo modulo.
  final ModuloAdmin? modulo;

  @override
  ConsumerState<ModuloFormPage> createState() => _ModuloFormPageState();
}

class _ModuloFormPageState extends ConsumerState<ModuloFormPage> {
  final _form = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.modulo?.nome ?? '');
  late final _descricao = TextEditingController(text: widget.modulo?.descricao ?? '');
  late final _ordem = TextEditingController(text: widget.modulo == null ? '' : '${widget.modulo!.ordem}');
  late String _icone = widget.modulo?.icone ?? 'extension';
  late bool _ativo = widget.modulo?.ativo ?? true;
  late bool _paraTodos = widget.modulo?.liberadoParaTodos ?? true;
  late Set<String> _planos = {...?widget.modulo?.planos};
  List<OpcaoCatalogo> _planosDisponiveis = const [];
  bool _salvando = false;
  String? _erro;

  bool get _novo => widget.modulo == null;
  bool get _sistema => widget.modulo?.sistema ?? false;

  @override
  void initState() {
    super.initState();
    _carregarPlanos();
  }

  @override
  void dispose() {
    _nome.dispose();
    _descricao.dispose();
    _ordem.dispose();
    super.dispose();
  }

  Future<void> _carregarPlanos() async {
    final token = ref.read(sessaoProvider).token;
    if (token == null) return;
    try {
      final c = await ref.read(clienteApiProvider).catalogo(token);
      if (mounted) setState(() => _planosDisponiveis = c.planos);
    } on ErroApi {
      // sem permissao para ver o catalogo: segue sem a escolha de planos
    }
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final token = ref.read(sessaoProvider).token;
    if (token == null) return;
    final api = ref.read(clienteApiProvider);
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final ordem = int.tryParse(_ordem.text.trim());
      final desc = _descricao.text.trim().isEmpty ? null : _descricao.text.trim();
      final corpo = <String, dynamic>{
        'nome': _nome.text.trim(),
        'descricao': desc,
        'icone': _icone,
        'liberado_para_todos': _paraTodos,
        'planos': (_planos.toList()..sort()),
        if (ordem != null) 'ordem': ordem,
        if (!_sistema) 'ativo': _ativo,
      };
      if (_novo) {
        await api.criarModulo(token, corpo);
      } else {
        await api.atualizarModulo(token, widget.modulo!.codigo, corpo);
      }
      ref.invalidate(modulosMenuProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_novo ? 'Módulo criado. Ele já aparece no menu.' : 'Módulo salvo.')));
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
        title: const Text('Excluir módulo?'),
        content: Text('O módulo "${widget.modulo!.nome}" sai do menu de todos.'),
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
      await ref.read(clienteApiProvider).excluirModulo(token, widget.modulo!.codigo);
      ref.invalidate(modulosMenuProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pode = ref.watch(sessaoProvider).pode('administracao.modulo.gerenciar');
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_novo ? 'Novo módulo' : 'Módulo'),
        actions: [
          if (!_novo && pode && !_sistema)
            IconButton(key: const Key('botao_excluir'), tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    key: const Key('campo_nome_modulo'),
                    controller: _nome,
                    enabled: pode,
                    decoration: decoracaoCampo(context, 'Nome do módulo', Icons.extension_outlined),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Informe o nome (ao menos 2 letras).' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('campo_descricao_modulo'),
                    controller: _descricao,
                    enabled: pode,
                    decoration: decoracaoCampo(context, 'Descrição (opcional)', Icons.notes_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('campo_ordem_modulo'),
                    controller: _ordem,
                    enabled: pode,
                    keyboardType: TextInputType.number,
                    decoration: decoracaoCampo(context, 'Posição no menu (opcional)', Icons.format_list_numbered),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return null;
                      final n = int.tryParse(t);
                      return (n == null || n < 1) ? 'Use um número a partir de 1.' : null;
                    },
                  ),
                  const SizedBox(height: 18),
                  Text('Ícone', style: tema.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in iconesModulo.entries)
                      ChoiceChip(
                        key: Key('icone_${e.key}'),
                        label: Icon(e.value, size: 20),
                        selected: _icone == e.key,
                        onSelected: pode ? (_) => setState(() => _icone = e.key) : null,
                      ),
                  ]),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const Key('campo_para_todos'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Liberado para todos os usuários'),
                    subtitle: const Text('Desligue para liberar só por plano ou por usuário.'),
                    value: _paraTodos,
                    onChanged: pode ? (v) => setState(() => _paraTodos = v) : null,
                  ),
                  if (!_paraTodos && _planosDisponiveis.isNotEmpty) ...[
                    Text('Planos que liberam este módulo', style: tema.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final p in _planosDisponiveis)
                        FilterChip(
                          key: Key('plano_${p.codigo}'),
                          label: Text(p.nome),
                          selected: _planos.contains(p.codigo),
                          onSelected: pode
                              ? (v) => setState(() => v ? _planos.add(p.codigo) : _planos.remove(p.codigo))
                              : null,
                        ),
                    ]),
                    const SizedBox(height: 8),
                  ],
                  SwitchListTile(
                    key: const Key('campo_ativo_modulo'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo'),
                    subtitle: Text(_sistema
                        ? 'Módulo de fábrica: não pode ser desativado nem excluído.'
                        : 'Desativado, ele some do menu de todos.'),
                    value: _ativo,
                    onChanged: (pode && !_sistema) ? (v) => setState(() => _ativo = v) : null,
                  ),
                  const SizedBox(height: 12),
                  if (_erro != null) ...[
                    CaixaMensagem(texto: _erro!),
                    const SizedBox(height: 12),
                  ],
                  if (pode)
                    KeyedSubtree(
                      key: const Key('botao_salvar'),
                      child: BotaoPrincipal(
                          texto: _novo ? 'Criar módulo' : 'Salvar módulo', enviando: _salvando, aoPressionar: _salvar),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
