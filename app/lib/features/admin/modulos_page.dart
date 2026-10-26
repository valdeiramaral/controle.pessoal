import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/aparencia.dart';
import '../../core/icones_modulo.dart';
import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';
import '../nav/menu_lateral.dart';
import 'modulo_form_page.dart';
import '../nav/acoes_usuario.dart';

/// Cadastro de modulos: lista, cria e edita. Modulos novos aparecem no menu.
class ModulosPage extends ConsumerStatefulWidget {
  const ModulosPage({super.key});

  @override
  ConsumerState<ModulosPage> createState() => _ModulosPageState();
}

class _ModulosPageState extends ConsumerState<ModulosPage> {
  List<ModuloAdmin> _itens = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final token = ref.read(sessaoProvider).token;
    if (token == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = await ref.read(clienteApiProvider).listarModulos(token);
      if (mounted) setState(() => _itens = l);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrir(ModuloAdmin? m) async {
    final mudou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ModuloFormPage(modulo: m)),
    );
    if (mudou == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final pode = ref.watch(sessaoProvider).pode('administracao.modulo.gerenciar');
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Módulos'), actions: const [AcoesUsuario()]),
      floatingActionButton: pode
          ? FloatingActionButton.extended(
              key: const Key('botao_novo_modulo'),
              icon: const Icon(Icons.add),
              label: const Text('Novo módulo'),
              onPressed: () => _abrir(null),
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
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    children: [
                      for (final m in _itens)
                        Card(
                          child: ListTile(
                            key: Key('modulo_item_${m.codigo}'),
                            leading: Icon(iconeDoModulo(m.icone), color: corIcone(context, corBaseDoModulo(m.icone))),
                            title: Text(m.nome),
                            subtitle: Text([
                              m.codigo,
                              if (m.sistema) 'de fábrica' else 'dono: ${m.donoNome ?? '—'}',
                            ].join(' · ')),
                            trailing: m.ativo
                                ? const Icon(Icons.chevron_right)
                                : Text('Inativo', style: TextStyle(color: tema.colorScheme.error)),
                            onTap: () => _abrir(m),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
