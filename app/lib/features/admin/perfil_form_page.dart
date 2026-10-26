import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';
import '../auth/widgets_auth.dart';
import 'widgets_acesso.dart';
import '../nav/acoes_usuario.dart';

/// Cria ou edita um perfil: nome, descricao e as permissoes marcadas.
class PerfilFormPage extends ConsumerStatefulWidget {
  const PerfilFormPage({super.key, this.perfilId});

  /// Nulo = novo perfil.
  final String? perfilId;

  @override
  ConsumerState<PerfilFormPage> createState() => _PerfilFormPageState();
}

class _PerfilFormPageState extends ConsumerState<PerfilFormPage> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  List<PermissaoApi> _catalogo = const [];
  PerfilItem? _original;
  Set<String> _marcadas = {};
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  bool get _novo => widget.perfilId == null;
  bool get _fixo => _original?.codigo == 'administrador';

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
      final cat = await api.listarPermissoes(token);
      final p = _novo ? null : await api.detalhePerfil(token, widget.perfilId!);
      if (!mounted) return;
      setState(() {
        _catalogo = cat;
        _original = p;
        if (p != null) {
          _nome.text = p.nome;
          _descricao.text = p.descricao ?? '';
          _marcadas = p.permissoes.toSet();
        }
      });
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
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
      if (_novo) {
        await api.criarPerfil(token, nome: _nome.text, descricao: desc, permissoes: _marcadas.toList()..sort());
      } else {
        await api.atualizarPerfil(token, widget.perfilId!,
            nome: _nome.text, descricao: desc, permissoes: _fixo ? null : (_marcadas.toList()..sort()));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_novo ? 'Perfil criado.' : 'Perfil salvo.')));
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
        title: const Text('Excluir perfil?'),
        content: Text('O perfil "${_original?.nome}" será removido.'),
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
      await ref.read(clienteApiProvider).excluirPerfil(token, widget.perfilId!);
      if (mounted) Navigator.of(context).pop(true);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessao = ref.watch(sessaoProvider);
    final pode = sessao.pode('acesso.perfil.gerenciar');
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_novo ? 'Novo perfil' : 'Perfil'),
        actions: [
          if (!_novo && pode && _original != null && !_original!.sistema)
            IconButton(key: const Key('botao_excluir'), tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
          const AcoesUsuario(),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : (_catalogo.isEmpty && _erro != null)
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_erro!, key: const Key('mensagem_erro')),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                  ]),
                )
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
                              key: const Key('campo_nome_perfil'),
                              controller: _nome,
                              enabled: pode,
                              decoration: decoracaoCampo(context, 'Nome do perfil', Icons.badge_outlined),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome.' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('campo_descricao_perfil'),
                              controller: _descricao,
                              enabled: pode,
                              decoration: decoracaoCampo(context, 'Descrição (opcional)', Icons.notes_outlined),
                            ),
                            const SizedBox(height: 16),
                            Text('Permissões', style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            if (_fixo)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('O perfil Administrador é fixo e tem todas as permissões.',
                                    key: const Key('aviso_fixo'), style: tema.textTheme.bodySmall),
                              ),
                            ChecklistPermissoes(
                              catalogo: _catalogo,
                              marcadas: _fixo ? _catalogo.map((p) => p.codigo).toSet() : _marcadas,
                              editavel: pode && !_fixo,
                              aoMudar: (s) => setState(() => _marcadas = s),
                            ),
                            const SizedBox(height: 16),
                            if (_erro != null) ...[
                              CaixaMensagem(texto: _erro!),
                              const SizedBox(height: 12),
                            ],
                            if (pode)
                              KeyedSubtree(
                                key: const Key('botao_salvar'),
                                child: BotaoPrincipal(
                                    texto: _novo ? 'Criar perfil' : 'Salvar perfil', enviando: _salvando, aoPressionar: _salvar),
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
