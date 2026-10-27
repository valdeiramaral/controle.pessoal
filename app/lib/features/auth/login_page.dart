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
    final largo = MediaQuery.sizeOf(context).width >= 820;
    final formulario = _formulario(context, tema, mensagem);
    return Scaffold(
      body: FundoAuth(
        larguraMax: largo ? 940 : 440,
        filho: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (largo)
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Expanded(child: _PainelMarca()),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(36, 30, 36, 26),
                        child: Material(type: MaterialType.transparency, child: Theme(data: temaAzul(context), child: formulario)),
                      ),
                    ),
                  ]),
                ),
              )
            else ...[
              const Align(child: MarcaApp(tamanho: 60)),
              const SizedBox(height: 16),
              Text('Controle Pessoal',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Colors.white)),
              const SizedBox(height: 6),
              Text('Finanças, saúde e agenda em um só lugar',
                  textAlign: TextAlign.center, style: tema.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
              const SizedBox(height: 24),
              CartaoAuth(filho: formulario),
            ],
          ],
        ),
      ),
    );
  }

  /// Abas (Entrar / Criar conta) e o formulario de entrada.
  Widget _formulario(BuildContext context, ThemeData tema, String? mensagem) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Abas(
            aoCriarConta: _enviando
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CadastroPage())),
          ),
          const SizedBox(height: 22),
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
    );
  }
}

/// Abas no topo do formulario: "Entrar" (atual) e "Criar conta" (abre o cadastro).
class _Abas extends StatelessWidget {
  const _Abas({required this.aoCriarConta});

  final VoidCallback? aoCriarConta;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    Widget aba(String texto, {required bool ativa, VoidCallback? aoTocar}) => InkWell(
          onTap: aoTocar,
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
            margin: const EdgeInsets.only(right: 22),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: ativa ? cores.primary : Colors.transparent, width: 2.5)),
            ),
            child: Text(texto,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: ativa ? cores.primary : cores.onSurfaceVariant)),
          ),
        );
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cores.outlineVariant))),
      child: Row(children: [
        aba('Entrar', ativa: true),
        aba('Criar conta', ativa: false, aoTocar: aoCriarConta),
      ]),
    );
  }
}

/// Painel escuro da esquerda (telas largas): marca e o que o app faz.
class _PainelMarca extends StatelessWidget {
  const _PainelMarca();

  @override
  Widget build(BuildContext context) {
    Widget item(String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 5),
              width: 9,
              height: 9,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3DD6C0)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(36, 34, 36, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2A63), Color(0xFF33307F)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Theme(data: temaAzul(context), child: const MarcaApp(tamanho: 46)),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Controle Pessoal',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Finanças, saúde e agenda em um só lugar',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 30),
          item('Finanças: contas, lançamentos e orçamento do mês'),
          item('Saúde: remédios, horários e registro de cada dose'),
          item('Agenda: compromissos com lembrete'),
          item('Funciona mesmo sem internet; entrando na conta, o administrador libera seus módulos'),
          const SizedBox(height: 30),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          const Text('Seus dados ficam protegidos pela sua conta.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
