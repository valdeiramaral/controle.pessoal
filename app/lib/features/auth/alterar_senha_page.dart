import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../nav/acoes_usuario.dart';
import 'sessao.dart';
import 'widgets_auth.dart';

/// Troca de senha do proprio usuario: pede a atual e a nova (duas vezes).
class AlterarSenhaPage extends ConsumerStatefulWidget {
  const AlterarSenhaPage({super.key});

  @override
  ConsumerState<AlterarSenhaPage> createState() => _AlterarSenhaPageState();
}

class _AlterarSenhaPageState extends ConsumerState<AlterarSenhaPage> {
  final _form = GlobalKey<FormState>();
  final _atual = TextEditingController();
  final _nova = TextEditingController();
  final _confirma = TextEditingController();
  bool _ver = false;
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _atual.dispose();
    _nova.dispose();
    _confirma.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref.read(sessaoProvider.notifier).alterarSenha(_atual.text, _nova.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada.')));
      Navigator.of(context).pop();
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _campo(Key chave, TextEditingController c, String rotulo, String? Function(String?) validar,
      {bool ultimo = false, bool comOlho = false}) {
    return TextFormField(
      key: chave,
      controller: c,
      obscureText: !_ver,
      textInputAction: ultimo ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: ultimo ? (_) => _salvando ? null : _salvar() : null,
      decoration: decoracaoCampo(
        context,
        rotulo,
        Icons.lock_outline,
        sufixo: comOlho
            ? IconButton(
                key: const Key('ver_senhas'),
                tooltip: _ver ? 'Ocultar senhas' : 'Mostrar senhas',
                icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _ver = !_ver),
              )
            : null,
      ),
      validator: validar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alterar senha'), actions: const [AcoesUsuario()]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _campo(const Key('campo_senha_atual'), _atual, 'Senha atual',
                      (v) => (v ?? '').isEmpty ? 'Informe a senha atual.' : null,
                      comOlho: true),
                  const SizedBox(height: 12),
                  _campo(const Key('campo_senha_nova'), _nova, 'Nova senha', (v) {
                    final t = v ?? '';
                    if (t.length < 8) return 'Use pelo menos 8 caracteres.';
                    if (t == _atual.text) return 'A nova senha deve ser diferente da atual.';
                    return null;
                  }),
                  const SizedBox(height: 12),
                  _campo(const Key('campo_senha_confirma'), _confirma, 'Repita a nova senha',
                      (v) => v != _nova.text ? 'As senhas não são iguais.' : null,
                      ultimo: true),
                  const SizedBox(height: 16),
                  if (_erro != null) ...[
                    CaixaMensagem(texto: _erro!),
                    const SizedBox(height: 12),
                  ],
                  KeyedSubtree(
                    key: const Key('botao_salvar'),
                    child: BotaoPrincipal(texto: 'Alterar senha', enviando: _salvando, aoPressionar: _salvar),
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
