import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import 'cadastro_page.dart';
import 'sessao.dart';
import 'validacoes.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _ver = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(sessaoProvider.notifier).entrar(_email.text, _senha.text);
      // sucesso: o portao do app troca para a tela principal.
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = ref.watch(sessaoProvider).aviso;
    final tema = Theme.of(context);
    final mensagem = _erro ?? aviso;
    return Scaffold(
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
                    Icon(Icons.account_circle_outlined, size: 64, color: tema.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Controle Pessoal',
                        textAlign: TextAlign.center, style: tema.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text('Entre na sua conta',
                        textAlign: TextAlign.center, style: tema.textTheme.bodyMedium),
                    const SizedBox(height: 24),
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
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _enviando ? null : _entrar(),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _ver ? 'Ocultar senha' : 'Mostrar senha',
                          icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _ver = !_ver),
                        ),
                      ),
                      validator: validarSenhaLogin,
                    ),
                    if (mensagem != null) ...[
                      const SizedBox(height: 12),
                      Text(mensagem,
                          key: const Key('mensagem_erro'),
                          style: TextStyle(color: tema.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('botao_entrar'),
                      onPressed: _enviando ? null : _entrar,
                      child: _enviando
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _enviando
                          ? null
                          : () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => const CadastroPage())),
                      child: const Text('Criar conta'),
                    ),
                    TextButton(
                      onPressed: _enviando
                          ? null
                          : () => ref.read(sessaoProvider.notifier).continuarSemConta(),
                      child: const Text('Usar sem conta neste aparelho'),
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
