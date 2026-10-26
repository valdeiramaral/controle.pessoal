import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/documentos.dart';
import '../../data/api/cliente_api.dart';
import '../admin/usuarios_page.dart' show nomePlano;
import 'campos_pessoa.dart';
import 'sessao.dart';
import 'widgets_auth.dart';

const _nomesModulos = {
  'acesso': 'Acesso e usuários',
  'idiomas': 'Idiomas e países',
  'licencas': 'Licenças',
  'financas': 'Finanças',
  'saude': 'Saúde',
  'agenda': 'Agenda',
  'painel': 'Painel e relatórios',
  'sincronizacao': 'Sincronização',
  'administracao': 'Administração',
};

/// O proprio usuario ve e atualiza telefone, nascimento e endereco, e ve o plano
/// e os modulos liberados. CPF e e-mail so o administrador altera.
class MeusDadosPage extends ConsumerStatefulWidget {
  const MeusDadosPage({super.key});

  @override
  ConsumerState<MeusDadosPage> createState() => _MeusDadosPageState();
}

class _MeusDadosPageState extends ConsumerState<MeusDadosPage> {
  final _form = GlobalKey<FormState>();
  late final DadosPessoaisControladores _d;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _d = DadosPessoaisControladores(ref.read(sessaoProvider).usuario);
  }

  @override
  void dispose() {
    _d.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref.read(sessaoProvider.notifier).atualizarMeusDados({
        'nome': _d.nome.text.trim(),
        'telefone': soDigitos(_d.telefone.text),
        'nascimento': _d.nascimentoIso() ?? '',
        'endereco': _d.enderecoJson(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados atualizados.')));
      Navigator.of(context).pop();
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(sessaoProvider).perfil;
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Meus dados')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (perfil != null)
                    Card(
                      key: const Key('cartao_plano'),
                      elevation: 0,
                      color: tema.colorScheme.primaryContainer.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Plano ${nomePlano(perfil.plano)}',
                              style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final m in perfil.modulos)
                              Chip(
                                label: Text(_nomesModulos[m] ?? m),
                                visualDensity: VisualDensity.compact,
                              ),
                          ]),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 16),
                  campoNome(context, _d),
                  const SizedBox(height: 12),
                  campoEmail(context, _d, habilitado: false),
                  const SizedBox(height: 12),
                  campoCpf(context, _d, habilitado: false),
                  const SizedBox(height: 12),
                  campoTelefone(context, _d),
                  const SizedBox(height: 6),
                  SecaoOpcional(c: _d, aberta: _d.temOpcionais),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Text('CPF e e-mail só o administrador altera.', style: tema.textTheme.bodySmall),
                  ),
                  if (_erro != null) ...[
                    CaixaMensagem(texto: _erro!),
                    const SizedBox(height: 12),
                  ],
                  KeyedSubtree(
                    key: const Key('botao_salvar'),
                    child: BotaoPrincipal(texto: 'Salvar', enviando: _salvando, aoPressionar: _salvar),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
