import 'package:flutter/material.dart';

/// Pecas visuais compartilhadas pelas telas de login e cadastro.

/// Azul da marca usado nas telas de entrada.
const azulMarca = Color(0xFF0052CC);

/// Tema claro com o azul da marca (campos, botoes e caixas sobre cartoes brancos).
ThemeData temaAzul(BuildContext context) => ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: azulMarca, brightness: Brightness.light)
          .copyWith(primary: azulMarca, onPrimary: Colors.white),
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      scaffoldBackgroundColor: Colors.white,
    );

/// Fundo azul em degrade com cartoes translucidos; usado atras de todas as telas.
class FundoAzul extends StatelessWidget {
  const FundoAzul({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B54D9), Color(0xFF2B48B8), Color(0xFF3B3AA4)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: _Decoracao())),
          child,
        ],
      ),
    );
  }
}

/// Telas de entrada: fundo azul e conteudo centralizado e rolavel.
class FundoAuth extends StatelessWidget {
  const FundoAuth({super.key, required this.filho, this.larguraMax = 440});

  final Widget filho;
  final double larguraMax;

  @override
  Widget build(BuildContext context) {
    return FundoAzul(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: larguraMax),
              child: _Entrada(child: filho),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartoes translucidos espalhados pelo fundo (so enfeite).
class _Decoracao extends StatelessWidget {
  const _Decoracao();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      Widget cartao(double x, double y, double largura, double altura, double giro) => Positioned(
            left: x * w,
            top: y * h,
            child: Transform.rotate(
              angle: giro,
              child: Container(
                width: largura,
                height: altura,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 7, width: largura * 0.6, decoration: _barra()),
                  const SizedBox(height: 10),
                  Container(height: 7, width: largura * 0.35, decoration: _barra()),
                ]),
              ),
            ),
          );
      return ClipRect(
        child: Stack(children: [
          cartao(-0.06, 0.05, 260, 110, -0.12),
          cartao(0.55, -0.04, 240, 100, 0.10),
          cartao(0.80, 0.14, 280, 120, -0.10),
          cartao(-0.04, 0.62, 250, 110, 0.14),
          cartao(0.48, 0.90, 280, 110, -0.08),
          cartao(0.86, 0.68, 240, 110, 0.12),
        ]),
      );
    });
  }

  BoxDecoration _barra() =>
      BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4));
}

/// Aparece suavemente (fade + leve subida).
class _Entrada extends StatelessWidget {
  const _Entrada({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, filho) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: filho),
      ),
      child: child,
    );
  }
}

/// Logotipo: quadrado arredondado com degrade e icone.
class MarcaApp extends StatelessWidget {
  const MarcaApp({super.key, this.tamanho = 72});

  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tamanho * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cores.primary, Color.alphaBlend(Colors.black.withValues(alpha: 0.28), cores.primary)],
        ),
        boxShadow: [
          BoxShadow(
            color: cores.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(Icons.dashboard_customize_rounded, color: cores.onPrimary, size: tamanho * 0.5),
    );
  }
}

/// Cartao branco (ou da cor da superficie) com cantos bem arredondados.
class CartaoAuth extends StatelessWidget {
  const CartaoAuth({super.key, required this.filho});

  final Widget filho;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Theme(data: temaAzul(context), child: filho),
    );
  }
}

/// Campo preenchido, sem borda ate receber foco.
InputDecoration decoracaoCampo(BuildContext context, String rotulo, IconData icone, {Widget? sufixo}) {
  final cores = Theme.of(context).colorScheme;
  OutlineInputBorder borda(Color cor, [double largura = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cor, width: largura),
      );
  return InputDecoration(
    labelText: rotulo,
    prefixIcon: Icon(icone),
    suffixIcon: sufixo,
    filled: true,
    fillColor: cores.surfaceContainerHighest.withValues(alpha: 0.45),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: borda(Colors.transparent),
    enabledBorder: borda(Colors.transparent),
    focusedBorder: borda(cores.primary, 2),
    errorBorder: borda(cores.error),
    focusedErrorBorder: borda(cores.error, 2),
  );
}

/// Botao principal: largo, alto e com spinner enquanto envia.
class BotaoPrincipal extends StatelessWidget {
  const BotaoPrincipal({super.key, required this.texto, required this.enviando, required this.aoPressionar});

  final String texto;
  final bool enviando;
  final VoidCallback aoPressionar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: enviando ? null : aoPressionar,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: enviando
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Text(texto),
      ),
    );
  }
}

/// Caixa de erro/aviso com icone.
class CaixaMensagem extends StatelessWidget {
  const CaixaMensagem({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cores.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: cores.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, key: const Key('mensagem_erro'), style: TextStyle(color: cores.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
