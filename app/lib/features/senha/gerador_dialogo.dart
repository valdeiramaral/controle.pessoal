import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/senha_calculo.dart';

/// Gerador de senhas. Devolve a senha escolhida ("Usar") ou null.
Future<String?> abrirGeradorDeSenhas(BuildContext context, {Random? random, bool permitirUsar = true}) =>
    showDialog<String>(context: context, builder: (_) => GeradorDialogo(random: random, permitirUsar: permitirUsar));

class GeradorDialogo extends StatefulWidget {
  const GeradorDialogo({super.key, this.random, this.permitirUsar = true});

  final Random? random;
  final bool permitirUsar;

  @override
  State<GeradorDialogo> createState() => _GeradorDialogoState();
}

class _GeradorDialogoState extends State<GeradorDialogo> {
  double _tamanho = 16;
  bool _maiusculas = true;
  bool _minusculas = true;
  bool _numeros = true;
  bool _simbolos = true;
  late String _senha;

  @override
  void initState() {
    super.initState();
    _senha = _gerar();
  }

  String _gerar() => gerarSenha(
      tamanho: _tamanho.round(),
      maiusculas: _maiusculas,
      minusculas: _minusculas,
      numeros: _numeros,
      simbolos: _simbolos,
      random: widget.random);

  void _regerar() => setState(() => _senha = _gerar());

  Widget _chave(String chave, String texto, bool v, ValueChanged<bool> f) => SwitchListTile(
        key: Key(chave),
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(texto),
        value: v,
        onChanged: (x) {
          f(x);
          _regerar();
        },
      );

  @override
  Widget build(BuildContext context) {
    final forca = avaliarSenha(_senha);
    return AlertDialog(
      title: const Text('Gerador de senhas'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(_senha, key: const Key('senha_gerada'), style: const TextStyle(fontFamily: 'monospace', fontSize: 20)),
            const SizedBox(height: 4),
            Text('Tempo para quebrar: ${forca.tempo}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('Tamanho: ${_tamanho.round()}'),
            Slider(
              key: const Key('gerador_tamanho'),
              min: 8,
              max: 40,
              divisions: 32,
              value: _tamanho,
              onChanged: (v) => setState(() {
                _tamanho = v;
                _senha = _gerar();
              }),
            ),
            _chave('gerador_maiusculas', 'Letras maiúsculas', _maiusculas, (v) => _maiusculas = v),
            _chave('gerador_minusculas', 'Letras minúsculas', _minusculas, (v) => _minusculas = v),
            _chave('gerador_numeros', 'Números', _numeros, (v) => _numeros = v),
            _chave('gerador_simbolos', 'Símbolos', _simbolos, (v) => _simbolos = v),
          ]),
        ),
      ),
      actions: [
        TextButton(key: const Key('gerar_outra'), onPressed: _regerar, child: const Text('Gerar outra')),
        TextButton(
          key: const Key('copiar_gerada'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _senha));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha copiada')));
            }
          },
          child: const Text('Copiar'),
        ),
        if (widget.permitirUsar)
          FilledButton(key: const Key('usar_gerada'), onPressed: () => Navigator.pop(context, _senha), child: const Text('Usar')),
        if (!widget.permitirUsar) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    );
  }
}
