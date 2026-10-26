import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import 'sessao.dart';
import 'validacoes.dart';
import 'widgets_auth.dart';

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
    Widget olho() => IconButton(
          tooltip: _ver ? 'Ocultar senha' : 'Mostrar senha',
          icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _ver = !_ver),
        );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Criar conta'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: FundoAuth(
        filho: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            const Align(child: MarcaApp(tamanho: 60)),
            const SizedBox(height: 14),
            Text('Comece agora',
                textAlign: TextAlign.center,
                style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Crie sua conta em poucos segundos',
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            CartaoAuth(
              filho: Form(
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
                      decoration: decoracaoCampo(context, 'Nome', Icons.person_outline),
                      validator: validarNome,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('campo_email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: decoracaoCampo(context, 'E-mail', Icons.mail_outline),
                      validator: validarEmail,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('campo_senha'),
                      controller: _senha,
                      obscureText: !_ver,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: decoracaoCampo(context, 'Senha (mínimo 8 caracteres)', Icons.lock_outline,
                          sufixo: olho()),
                      validator: validarSenhaNova,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('campo_confirma'),
                      controller: _confirma,
                      obscureText: !_ver,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _enviando ? null : _criar(),
                      decoration: decoracaoCampo(context, 'Repita a senha', Icons.lock_reset_outlined),
                      validator: (v) => v == _senha.text ? null : 'As senhas não são iguais.',
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 14),
                      CaixaMensagem(texto: _erro!),
                    ],
                    const SizedBox(height: 22),
                    KeyedSubtree(
                      key: const Key('botao_criar'),
                      child: BotaoPrincipal(texto: 'Criar conta', enviando: _enviando, aoPressionar: _criar),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
