import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';
import 'grupo_form_page.dart';
import 'perfil_form_page.dart';
import '../nav/acoes_usuario.dart';

/// Administracao de perfis (conjuntos de permissoes) e grupos (perfis + membros).
class PerfisGruposPage extends ConsumerStatefulWidget {
  const PerfisGruposPage({super.key});

  @override
  ConsumerState<PerfisGruposPage> createState() => _PerfisGruposPageState();
}

class _PerfisGruposPageState extends ConsumerState<PerfisGruposPage> with SingleTickerProviderStateMixin {
  late final TabController _abas = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  List<PerfilItem> _perfis = const [];
  List<GrupoItem> _grupos = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _abas.dispose();
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
      final grupos = await api.listarGrupos(token);
      if (mounted) {
        setState(() {
          _perfis = perfis;
          _grupos = grupos;
        });
      }
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirPerfil(String? id) async {
    final mudou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PerfilFormPage(perfilId: id)),
    );
    if (mudou == true) _carregar();
  }

  Future<void> _abrirGrupo(String? id) async {
    final mudou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GrupoFormPage(grupoId: id)),
    );
    if (mudou == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final sessao = ref.watch(sessaoProvider);
    final emPerfis = _abas.index == 0;
    final podeCriar = emPerfis ? sessao.pode('acesso.perfil.gerenciar') : sessao.pode('acesso.grupo.gerenciar');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfis e grupos'),
        actions: const [AcoesUsuario()],
        bottom: TabBar(controller: _abas, tabs: const [
          Tab(key: Key('aba_perfis'), text: 'Perfis'),
          Tab(key: Key('aba_grupos'), text: 'Grupos'),
        ]),
      ),
      floatingActionButton: podeCriar
          ? FloatingActionButton.extended(
              key: const Key('botao_novo_item'),
              icon: const Icon(Icons.add),
              label: Text(emPerfis ? 'Novo perfil' : 'Novo grupo'),
              onPressed: () => emPerfis ? _abrirPerfil(null) : _abrirGrupo(null),
            )
          : null,
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_erro!, key: const Key('mensagem_erro')),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                  ]),
                )
              : TabBarView(controller: _abas, children: [_listaPerfis(), _listaGrupos()]),
    );
  }

  Widget _listaPerfis() => RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            for (final p in _perfis)
              Card(
                elevation: 0,
                child: ListTile(
                  key: Key('item_perfil_${p.codigo}'),
                  leading: Icon(p.sistema ? Icons.shield_outlined : Icons.badge_outlined),
                  title: Text(p.nome),
                  subtitle: Text('${p.totalPermissoes} permissões · ${p.totalUsuarios} usuário(s)'
                      '${p.sistema ? ' · do sistema' : ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _abrirPerfil(p.id),
                ),
              ),
          ],
        ),
      );

  Widget _listaGrupos() => RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            if (_grupos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhum grupo ainda. Crie um para dar o mesmo acesso a várias pessoas de uma vez.',
                    key: Key('grupos_vazio')),
              ),
            for (final g in _grupos)
              Card(
                elevation: 0,
                child: ListTile(
                  key: Key('item_grupo_${g.id}'),
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(g.nome),
                  subtitle: Text('${g.totalMembros} membro(s)'
                      '${g.perfis.isEmpty ? '' : ' · ${g.perfis.join(', ')}'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _abrirGrupo(g.id),
                ),
              ),
          ],
        ),
      );
}
