import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import 'sessao.dart';
import 'validacoes.dart';

class CadastroPage extends ConsumerStatefulWidget {
  const CadastroPage({super.key});

  @override
  ConsumerState<CadastroPage> createState() => _CadastroPageState();
}

class _CadastroPageState extends ConsumerState<CadastroPage> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _confirma = TextEditingController();
  bool _ver = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    _confirma.dispose();
    super.dispose();
  }

  Future<void> _criar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(sessaoProvider.notifier).cadastrar(_nome.text, _email.text, _senha.text);
      // Conta criada e login feito: volta ao portao, que mostra a tela principal.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('campo_nome'),
                      controller: _nome,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
                      validator: validarNome,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('campo_email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                      validator: validarEmail,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('campo_senha'),
                      controller: _senha,
                      obscureText: !_ver,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Senha (mínimo 8 caracteres)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _ver ? 'Ocultar senha' : 'Mostrar senha',
                          icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _ver = !_ver),
                        ),
                      ),
                      validator: validarSenhaNova,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('campo_confirma'),
                      controller: _confirma,
                      obscureText: !_ver,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _enviando ? null : _criar(),
                      decoration: const InputDecoration(labelText: 'Repita a senha', border: OutlineInputBorder()),
                      validator: (v) => v == _senha.text ? null : 'As senhas não são iguais.',
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 12),
                      Text(_erro!,
                          key: const Key('mensagem_erro'),
                          style: TextStyle(color: tema.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('botao_criar'),
                      onPressed: _enviando ? null : _criar,
                      child: _enviando
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Criar conta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
