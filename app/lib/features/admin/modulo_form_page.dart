import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/aparencia.dart';
import '../../core/formatos.dart';
import '../../core/icones_modulo.dart';
import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';
import '../auth/widgets_auth.dart';
import '../nav/modulos_menu.dart';
import '../nav/acoes_usuario.dart';

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
  final _buscaIcone = TextEditingController();
  String _filtroIcone = '';
  late bool _ativo = widget.modulo?.ativo ?? true;
  late bool _noPacote = widget.modulo?.noPacote ?? false;
  late Set<String> _planos = {...?widget.modulo?.planos};
  List<OpcaoCatalogo> _planosDisponiveis = const [];
  late List<_Lib> _libs = [for (final l in widget.modulo?.liberacoes ?? const <LiberacaoModulo>[]) _Lib.de(l)];
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
    _buscaIcone.dispose();
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
    for (final l in _noPacote ? const <_Lib>[] : _libs) {
      if (!l.vitalicio && (l.inicio == null || l.fim == null)) {
        setState(() => _erro = 'Informe o início e o fim da validade de ${l.nome}, ou marque como vitalício.');
        return;
      }
      if (!l.vitalicio && l.fim!.isBefore(l.inicio!)) {
        setState(() => _erro = 'A data final de ${l.nome} não pode ser antes da inicial.');
        return;
      }
    }
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
        'no_pacote': _noPacote,
        if (!_noPacote) ...{
          'planos': (_planos.toList()..sort()),
          'liberacoes': [for (final l in _libs) l.paraJson()],
        },
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
        content: Text('O módulo "${widget.modulo!.nome}" sai do menu de todos os usuários liberados.'),
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

  /// Icones por categoria, filtrados pela busca (nome do icone ou da categoria).
  List<Widget> _seletorIcones(BuildContext context, bool pode) {
    final tema = Theme.of(context);
    final blocos = <Widget>[];
    for (final c in categoriasIcones) {
      final itens = c.icones
          .where((i) => _filtroIcone.isEmpty ||
              i.nome.toLowerCase().contains(_filtroIcone) ||
              i.chave.contains(_filtroIcone) ||
              c.nome.toLowerCase().contains(_filtroIcone))
          .toList();
      if (itens.isEmpty) continue;
      blocos.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(c.nome, style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
      ));
      blocos.add(Wrap(spacing: 8, runSpacing: 8, children: [
        for (final i in itens)
          Tooltip(
            message: i.nome,
            child: ChoiceChip(
              key: Key('icone_${i.chave}'),
              label: Icon(i.icone, size: 20, color: corIcone(context, c.cor)),
              selected: _icone == i.chave,
              onSelected: pode ? (_) => setState(() => _icone = i.chave) : null,
            ),
          ),
      ]));
    }
    if (blocos.isEmpty) blocos.add(const Padding(padding: EdgeInsets.all(8), child: Text('Nenhum ícone encontrado.')));
    return blocos;
  }

  Future<void> _adicionarUsuario() async {
    final token = ref.read(sessaoProvider).token;
    if (token == null) return;
    final escolhido = await showDialog<ItemUsuario>(
      context: context,
      builder: (_) => _EscolherUsuario(
        buscar: (t) => ref.read(clienteApiProvider).listarUsuarios(token, busca: t),
        jaLiberados: {for (final l in _libs) l.usuarioId},
      ),
    );
    if (escolhido != null) {
      setState(() => _libs.add(_Lib(usuarioId: escolhido.id, nome: escolhido.nome, email: escolhido.email)));
    }
  }

  Future<void> _escolherData(_Lib l, bool inicio) async {
    final base = (inicio ? l.inicio : l.fim) ?? DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: base, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) setState(() => inicio ? l.inicio = d : l.fim = d);
  }

  Widget _cartaoLiberacao(BuildContext context, _Lib l, bool pode) {
    final tema = Theme.of(context);
    final vencida = !l.vitalicio && l.fim != null && DateTime.now().isAfter(DateTime(l.fim!.year, l.fim!.month, l.fim!.day, 23, 59, 59));
    final situacao = !l.ativa ? 'Desativada' : (vencida ? 'Vencida' : 'Vigente');
    final cor = !l.ativa ? Colors.grey : (vencida ? Colors.red : Colors.green);
    Widget data(String rotulo, DateTime? v, bool inicio) => OutlinedButton.icon(
          key: Key('${inicio ? 'inicio' : 'fim'}_${l.usuarioId}'),
          onPressed: pode ? () => _escolherData(l, inicio) : null,
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text('$rotulo: ${v == null ? 'escolher' : formatarData(v)}'),
        );
    return Card(
      key: Key('liberacao_${l.usuarioId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.nome, style: tema.textTheme.titleSmall),
                if (l.email != null) Text(l.email!, style: tema.textTheme.bodySmall),
              ]),
            ),
            Text(situacao, style: TextStyle(color: corIcone(context, cor), fontWeight: FontWeight.w700)),
            if (pode)
              IconButton(
                key: Key('remover_${l.usuarioId}'),
                tooltip: 'Remover liberação',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _libs.remove(l)),
              ),
          ]),
          SwitchListTile(
            key: Key('ativa_${l.usuarioId}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Liberação ativa'),
            value: l.ativa,
            onChanged: pode ? (v) => setState(() => l.ativa = v) : null,
          ),
          SwitchListTile(
            key: Key('vitalicio_${l.usuarioId}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Vitalício (sem data de validade)'),
            value: l.vitalicio,
            onChanged: pode ? (v) => setState(() => l.vitalicio = v) : null,
          ),
          if (!l.vitalicio)
            Wrap(spacing: 8, runSpacing: 8, children: [data('Início', l.inicio, true), data('Fim', l.fim, false)]),
        ]),
      ),
    );
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
          const AcoesUsuario(),
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
                  Row(children: [
                    Expanded(child: Text('Ícone', style: tema.textTheme.titleSmall)),
                    Icon(iconeDoModulo(_icone), color: corIcone(context, corBaseDoModulo(_icone))),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('busca_icone'),
                    controller: _buscaIcone,
                    decoration: decoracaoCampo(context, 'Buscar ícone (ex.: carro, saúde, música)', Icons.search),
                    onChanged: (v) => setState(() => _filtroIcone = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  ..._seletorIcones(context, pode),
                  const SizedBox(height: 12),
                  const SizedBox(height: 8),
                  Text('Liberação', style: tema.textTheme.titleMedium),
                  SwitchListTile(
                    key: const Key('campo_no_pacote'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Incluído no pacote'),
                    subtitle: const Text('Vale para todos os usuários, sem liberação e sem data de validade.'),
                    value: _noPacote,
                    onChanged: pode ? (v) => setState(() => _noPacote = v) : null,
                  ),
                  if (_noPacote)
                    Card(
                      key: const Key('aviso_pacote'),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.inventory_2_outlined, color: corIcone(context, Colors.teal)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Este módulo faz parte do pacote do app: todos os usuários já têm acesso. '
                                'Desligue "Incluído no pacote" para liberar só por plano ou para usuários escolhidos.'),
                          ),
                        ]),
                      ),
                    )
                  else ...[
                    if (_planosDisponiveis.isNotEmpty) ...[
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
                      const SizedBox(height: 12),
                    ],
                    Row(children: [
                      Expanded(child: Text('Usuários liberados (${_libs.length})', style: tema.textTheme.titleSmall)),
                      if (pode)
                        TextButton.icon(
                          key: const Key('botao_add_usuario'),
                          onPressed: _adicionarUsuario,
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Adicionar usuário'),
                        ),
                    ]),
                    if (_libs.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nenhum usuário liberado ainda.')),
                    for (final l in _libs) _cartaoLiberacao(context, l, pode),
                  ],
                  SwitchListTile(
                    key: const Key('campo_ativo_modulo'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo'),
                    subtitle: Text(_sistema
                        ? 'Módulo de fábrica: não pode ser desativado nem excluído.'
                        : 'Desativado, ele some do menu do dono.'),
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

/// Liberacao em edicao na tela.
class _Lib {
  _Lib({
    required this.usuarioId,
    required this.nome,
    this.email,
    this.ativa = true,
    this.vitalicio = true,
    this.inicio,
    this.fim,
  });

  factory _Lib.de(LiberacaoModulo l) => _Lib(
      usuarioId: l.usuarioId, nome: l.nome, email: l.email, ativa: l.ativa, vitalicio: l.vitalicio, inicio: l.inicio, fim: l.fim);

  final String usuarioId;
  final String nome;
  final String? email;
  bool ativa;
  bool vitalicio;
  DateTime? inicio;
  DateTime? fim;

  /// Inicio vale desde o comeco do dia e o fim ate o ultimo segundo do dia escolhido.
  Map<String, dynamic> paraJson() => {
        'usuario_id': usuarioId,
        'ativa': ativa,
        'vitalicio': vitalicio,
        if (!vitalicio && inicio != null) 'inicio': DateTime(inicio!.year, inicio!.month, inicio!.day).toUtc().toIso8601String(),
        if (!vitalicio && fim != null) 'fim': DateTime(fim!.year, fim!.month, fim!.day, 23, 59, 59).toUtc().toIso8601String(),
      };
}

/// Escolha de um usuario (com busca) para liberar o modulo.
class _EscolherUsuario extends StatefulWidget {
  const _EscolherUsuario({required this.buscar, required this.jaLiberados});

  final Future<ListaUsuarios> Function(String) buscar;
  final Set<String> jaLiberados;

  @override
  State<_EscolherUsuario> createState() => _EscolherUsuarioState();
}

class _EscolherUsuarioState extends State<_EscolherUsuario> {
  final _busca = TextEditingController();
  List<ItemUsuario> _itens = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await widget.buscar(_busca.text);
      if (mounted) setState(() => _itens = r.itens.where((u) => !widget.jaLiberados.contains(u.id)).toList());
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Liberar para'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(children: [
          TextField(
            key: const Key('busca_usuario'),
            controller: _busca,
            decoration: const InputDecoration(labelText: 'Buscar por nome, e-mail ou CPF', prefixIcon: Icon(Icons.search)),
            onSubmitted: (_) => _carregar(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _erro != null
                    ? Center(child: Text(_erro!))
                    : _itens.isEmpty
                        ? const Center(child: Text('Nenhum usuário disponível.'))
                        : ListView(children: [
                            for (final u in _itens)
                              ListTile(
                                key: Key('usuario_op_${u.id}'),
                                title: Text(u.nome),
                                subtitle: Text(u.email),
                                onTap: () => Navigator.of(context).pop(u),
                              ),
                          ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))],
    );
  }
}
