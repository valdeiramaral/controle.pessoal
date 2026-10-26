import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documentos.dart';
import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';
import 'usuario_form_page.dart';
import '../nav/acoes_usuario.dart';

/// Nome do plano para exibir (codigo -> texto).
String nomePlano(String? codigo) => switch (codigo) {
      'gratuito' => 'Gratuito',
      'mensal' => 'Mensal',
      'anual' => 'Anual',
      'vitalicio' => 'Vitalício',
      null => '—',
      _ => codigo,
    };

/// Administracao: lista de usuarios com busca, plano e situacao.
class UsuariosPage extends ConsumerStatefulWidget {
  const UsuariosPage({super.key});

  @override
  ConsumerState<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends ConsumerState<UsuariosPage> {
  final _busca = TextEditingController();
  Timer? _espera;
  ListaUsuarios? _lista;
  String? _erro;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busca.dispose();
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
      final l = await ref.read(clienteApiProvider).listarUsuarios(token, busca: _busca.text);
      if (mounted) setState(() => _lista = l);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _aoDigitar(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), _carregar);
  }

  Future<void> _abrir(String? id) async {
    final mudou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => UsuarioFormPage(usuarioId: id)),
    );
    if (mudou == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final sessao = ref.watch(sessaoProvider);
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Usuários'), actions: const [AcoesUsuario()]),
      floatingActionButton: sessao.pode('acesso.usuario.cadastrar')
          ? FloatingActionButton.extended(
              key: const Key('botao_novo_usuario'),
              onPressed: () => _abrir(null),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Novo usuário'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('campo_busca'),
              controller: _busca,
              onChanged: _aoDigitar,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por nome, e-mail ou CPF',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _carregar,
              child: _corpo(tema),
            ),
          ),
        ],
      ),
    );
  }

  Widget _corpo(ThemeData tema) {
    if (_carregando && _lista == null) return const Center(child: CircularProgressIndicator());
    if (_erro != null && _lista == null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(_erro!, key: const Key('mensagem_erro'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
          ]),
        ),
      ]);
    }
    final itens = _lista?.itens ?? const <ItemUsuario>[];
    if (itens.isEmpty) {
      return ListView(children: const [
        Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nenhum usuário encontrado.'))),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: itens.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final u = itens[i];
        return Card(
          elevation: 0,
          color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            key: Key('usuario_${u.id}'),
            onTap: () => _abrir(u.id),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: CircleAvatar(
              backgroundColor: u.ativo ? tema.colorScheme.primaryContainer : tema.colorScheme.errorContainer,
              child: Text(u.nome.isEmpty ? '?' : u.nome.characters.first.toUpperCase()),
            ),
            title: Text(u.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [u.email, if (u.cpf != null) formatarCpf(u.cpf)].join('\n'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: u.cpf != null,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(nomePlano(u.plano), style: tema.textTheme.labelLarge),
                if (!u.ativo)
                  Text('Desativado', style: tema.textTheme.labelSmall?.copyWith(color: tema.colorScheme.error)),
              ],
            ),
          ),
        );
      },
    );
  }
}
