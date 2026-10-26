import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import 'cadastro_page.dart';
import 'sessao.dart';
import 'validacoes.dart';
import 'widgets_auth.dart';

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
  bool _lembrar = true;
  bool _preenchido = false;
  bool _enviando = false;
  String? _erro;

  // Apenas para testes: valores vindos de --dart-define (o web.ps1 le do .env, que nao vai para o git).
  static const _emailTeste = String.fromEnvironment('LOGIN_TESTE_EMAIL');
  static const _senhaTeste = String.fromEnvironment('LOGIN_TESTE_SENHA');

  @override
  void initState() {
    super.initState();
    _email.text = _emailTeste;
    _senha.text = _senhaTeste;
  }

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
      await ref.read(sessaoProvider.notifier).entrar(_email.text, _senha.text, lembrar: _lembrar);
      // sucesso: o portao do app troca para a tela principal.
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(sessaoProvider);
    final aviso = estado.aviso;
    // Preenche o e-mail lembrado (uma vez, sem sobrescrever o que o usuario digitou).
    if (!_preenchido && estado.emailLembrado != null) {
      _preenchido = true;
      if (_email.text.isEmpty) _email.text = estado.emailLembrado!;
    }
    final tema = Theme.of(context);
    final mensagem = _erro ?? aviso;
    return Scaffold(
      body: FundoAuth(
        filho: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(child: MarcaApp()),
            const SizedBox(height: 18),
            Text('Controle Pessoal',
                textAlign: TextAlign.center,
                style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text('Finanças, saúde e agenda em um só lugar',
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            CartaoAuth(
              filho: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Bem-vindo de volta',
                        style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Entre para continuar', style: tema.textTheme.bodyMedium),
                    const SizedBox(height: 20),
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
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _enviando ? null : _entrar(),
                      decoration: decoracaoCampo(
                        context,
                        'Senha',
                        Icons.lock_outline,
                        sufixo: IconButton(
                          tooltip: _ver ? 'Ocultar senha' : 'Mostrar senha',
                          icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _ver = !_ver),
                        ),
                      ),
                      validator: validarSenhaLogin,
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      key: const Key('campo_lembrar'),
                      value: _lembrar,
                      onChanged: _enviando ? null : (v) => setState(() => _lembrar = v ?? false),
                      title: const Text('Lembrar de mim'),
                      subtitle: const Text('Não precisa digitar de novo'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    if (mensagem != null) ...[
                      const SizedBox(height: 8),
                      CaixaMensagem(texto: mensagem),
                    ],
                    const SizedBox(height: 16),
                    KeyedSubtree(
                      key: const Key('botao_entrar'),
                      child: BotaoPrincipal(texto: 'Entrar', enviando: _enviando, aoPressionar: _entrar),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Ainda não tem conta?', style: tema.textTheme.bodyMedium),
                TextButton(
                  onPressed: _enviando
                      ? null
                      : () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const CadastroPage())),
                  child: const Text('Criar conta', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _enviando ? null : () => ref.read(sessaoProvider.notifier).continuarSemConta(),
              icon: const Icon(Icons.phone_android, size: 18),
              label: const Text('Usar sem conta neste aparelho'),
            ),
          ],
        ),
      ),
    );
  }
}
