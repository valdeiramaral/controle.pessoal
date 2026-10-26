import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';
import '../auth/widgets_auth.dart';

/// Cria ou edita um grupo: nome, perfis que ele concede e membros.
class GrupoFormPage extends ConsumerStatefulWidget {
  const GrupoFormPage({super.key, this.grupoId});

  /// Nulo = novo grupo.
  final String? grupoId;

  @override
  ConsumerState<GrupoFormPage> createState() => _GrupoFormPageState();
}

class _GrupoFormPageState extends ConsumerState<GrupoFormPage> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  List<PerfilItem> _perfisDisponiveis = const [];
  Set<String> _perfis = {};
  final Map<String, MembroGrupo> _membros = {};
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  bool get _novo => widget.grupoId == null;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nome.dispose();
    _descricao.dispose();
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
      final perfis = await api.listarPerfis(token);
      final g = _novo ? null : await api.detalheGrupo(token, widget.grupoId!);
      if (!mounted) return;
      setState(() {
        _perfisDisponiveis = perfis;
        if (g != null) {
          _nome.text = g.nome;
          _descricao.text = g.descricao ?? '';
          _perfis = g.perfis.toSet();
          _membros
            ..clear()
            ..addEntries(g.membros.map((m) => MapEntry(m.id, m)));
        }
      });
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _escolherMembros() async {
    final escolhidos = await showDialog<Map<String, MembroGrupo>>(
      context: context,
      builder: (_) => _SeletorMembros(inicial: Map.of(_membros)),
    );
    if (escolhidos != null) {
      setState(() {
        _membros
          ..clear()
          ..addAll(escolhidos);
      });
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
      final desc = _descricao.text.trim().isEmpty ? null : _descricao.text.trim();
      final perfis = _perfis.toList()..sort();
      final membros = _membros.keys.toList();
      if (_novo) {
        await api.criarGrupo(token, nome: _nome.text, descricao: desc, perfis: perfis, membros: membros);
      } else {
        await api.atualizarGrupo(token, widget.grupoId!, nome: _nome.text, descricao: desc, perfis: perfis, membros: membros);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_novo ? 'Grupo criado.' : 'Grupo salvo.')));
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
        title: const Text('Excluir grupo?'),
        content: Text('Os membros perdem o acesso que vinha deste grupo.'),
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
      await ref.read(clienteApiProvider).excluirGrupo(token, widget.grupoId!);
      if (mounted) Navigator.of(context).pop(true);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pode = ref.watch(sessaoProvider).pode('acesso.grupo.gerenciar');
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_novo ? 'Novo grupo' : 'Grupo'),
        actions: [
          if (!_novo && pode)
            IconButton(key: const Key('botao_excluir'), tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        TextFormField(
                          key: const Key('campo_nome_grupo'),
                          controller: _nome,
                          enabled: pode,
                          decoration: decoracaoCampo(context, 'Nome do grupo', Icons.groups_outlined),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('campo_descricao_grupo'),
                          controller: _descricao,
                          enabled: pode,
                          decoration: decoracaoCampo(context, 'Descrição (opcional)', Icons.notes_outlined),
                        ),
                        const SizedBox(height: 16),
                        Text('Perfis do grupo', style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Todo membro recebe as permissões destes perfis.', style: tema.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          for (final p in _perfisDisponiveis)
                            FilterChip(
                              key: Key('grupo_perfil_${p.codigo}'),
                              label: Text(p.nome),
                              selected: _perfis.contains(p.codigo),
                              onSelected: pode
                                  ? (v) => setState(() => v ? _perfis.add(p.codigo) : _perfis.remove(p.codigo))
                                  : null,
                            ),
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                            child: Text('Membros (${_membros.length})',
                                style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          if (pode)
                            TextButton.icon(
                              key: const Key('botao_membros'),
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              label: const Text('Escolher'),
                              onPressed: _escolherMembros,
                            ),
                        ]),
                        if (_membros.isEmpty) const Text('Ninguém ainda.', key: Key('sem_membros')),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          for (final m in _membros.values)
                            InputChip(
                              key: Key('membro_${m.id}'),
                              label: Text(m.nome),
                              onDeleted: pode ? () => setState(() => _membros.remove(m.id)) : null,
                            ),
                        ]),
                        const SizedBox(height: 16),
                        if (_erro != null) ...[
                          CaixaMensagem(texto: _erro!),
                          const SizedBox(height: 12),
                        ],
                        if (pode)
                          KeyedSubtree(
                            key: const Key('botao_salvar'),
                            child: BotaoPrincipal(
                                texto: _novo ? 'Criar grupo' : 'Salvar grupo', enviando: _salvando, aoPressionar: _salvar),
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

/// Dialogo para marcar os usuarios que fazem parte do grupo.
class _SeletorMembros extends ConsumerStatefulWidget {
  const _SeletorMembros({required this.inicial});

  final Map<String, MembroGrupo> inicial;

  @override
  ConsumerState<_SeletorMembros> createState() => _SeletorMembrosState();
}

class _SeletorMembrosState extends ConsumerState<_SeletorMembros> {
  final _busca = TextEditingController();
  late final Map<String, MembroGrupo> _sel = Map.of(widget.inicial);
  List<ItemUsuario> _itens = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final token = ref.read(sessaoProvider).token;
    if (token == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = await ref.read(clienteApiProvider).listarUsuarios(token, busca: _busca.text);
      if (mounted) setState(() => _itens = l.itens);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Membros do grupo'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
            key: const Key('busca_membros'),
            controller: _busca,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nome ou e-mail'),
            onSubmitted: (_) => _buscar(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _erro != null
                    ? Text(_erro!)
                    : ListView(children: [
                        for (final u in _itens)
                          CheckboxListTile(
                            key: Key('escolher_${u.id}'),
                            dense: true,
                            title: Text(u.nome),
                            subtitle: Text(u.email),
                            value: _sel.containsKey(u.id),
                            onChanged: (v) => setState(() =>
                                v == true ? _sel[u.id] = MembroGrupo(u.id, u.nome, u.email) : _sel.remove(u.id)),
                          ),
                      ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(key: const Key('confirmar_membros'), onPressed: () => Navigator.pop(context, _sel), child: const Text('Confirmar')),
      ],
    );
  }
}
