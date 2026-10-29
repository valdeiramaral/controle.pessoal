import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bancos.dart';
import '../../core/conta_validacao.dart';
import '../../core/documentos.dart';
import '../../core/formatos.dart';
import '../../data/local/banco.dart';
import '../nav/acoes_usuario.dart';

/// Cadastro (e edicao, quando [conta] vem preenchida) de conta bancaria.
class ContaFormPage extends ConsumerStatefulWidget {
  const ContaFormPage({super.key, this.conta});

  final Conta? conta;

  @override
  ConsumerState<ContaFormPage> createState() => _ContaFormPageState();
}

class _ContaFormPageState extends ConsumerState<ContaFormPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _agencia;
  late final TextEditingController _numero;
  late final TextEditingController _documento;
  late final TextEditingController _pix;
  late final TextEditingController _apelido;
  late final TextEditingController _nomeBanco;
  late final TextEditingController _saldo;
  String? _titularidade;
  String? _banco;
  late String _tipo;
  String? _erro;
  bool _salvando = false;

  bool get _editando => widget.conta != null;
  bool get _dinheiro => _tipo == 'dinheiro';

  @override
  void initState() {
    super.initState();
    final c = widget.conta;
    _agencia = TextEditingController(text: c?.agencia ?? '');
    _numero = TextEditingController(text: c?.numeroConta ?? '');
    _documento = TextEditingController(text: formatarCpfOuCnpj(c?.documento));
    _pix = TextEditingController(text: c?.chavePix ?? '');
    _apelido = TextEditingController(text: c?.apelido ?? (c != null && c.banco == null ? c.nome : ''));
    _nomeBanco = TextEditingController(text: c != null && c.banco == codigoOutroBanco ? c.nome : '');
    _saldo = TextEditingController(
        text: c == null || c.saldoInicialCentavos == 0 ? '' : textoMoeda(c.saldoInicialCentavos));
    _titularidade = c?.titularidade;
    _banco = c?.banco;
    _tipo = c?.tipo ?? 'corrente';
  }

  @override
  void dispose() {
    for (final c in [_agencia, _numero, _documento, _pix, _apelido, _nomeBanco, _saldo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    final banco = ref.read(bancoProvider);
    final apelido = _apelido.text.trim();
    final saldoTxt = _saldo.text.trim();
    final saldo = saldoTxt.isEmpty ? 0 : centavosDeTexto(saldoTxt);
    if (saldo == null) {
      setState(() => _erro = 'Saldo inicial inválido.');
      return;
    }
    setState(() => _salvando = true);
    try {
      final titularidade = _dinheiro ? 'propria' : _titularidade!;
      final codigo = _dinheiro ? null : _banco;
      final agencia = _dinheiro ? null : _agencia.text.trim();
      final numero = _dinheiro ? null : _numero.text.trim();
      if (!_dinheiro &&
          await banco.existeContaBancaria(banco: codigo!, agencia: agencia!, numeroConta: numero!, ignorarId: widget.conta?.id)) {
        setState(() => _erro = 'Já existe uma conta cadastrada com este banco, agência e número.');
        return;
      }
      final nome = codigo == codigoOutroBanco
          ? _nomeBanco.text.trim()
          : (apelido.isNotEmpty ? apelido : bancoPorCodigo(codigo).nome);
      final doc = soDigitos(_documento.text);
      final pix = _pix.text.trim();
      if (_editando) {
        await banco.atualizarConta(
          widget.conta!.id,
          nome: nome,
          tipo: _tipo,
          saldoInicialCentavos: titularidade == 'externa' ? widget.conta!.saldoInicialCentavos : saldo,
          titularidade: titularidade,
          banco: codigo,
          agencia: agencia,
          numeroConta: numero,
          documento: _dinheiro || doc.isEmpty ? null : doc,
          chavePix: _dinheiro || pix.isEmpty ? null : pix,
          apelido: apelido.isEmpty ? null : apelido,
        );
      } else {
        await banco.inserirConta(
          nome: nome,
          tipo: _tipo,
          saldoInicialCentavos: titularidade == 'externa' ? 0 : saldo,
          titularidade: titularidade,
          banco: codigo,
          agencia: agencia,
          numeroConta: numero,
          documento: _dinheiro || doc.isEmpty ? null : doc,
          chavePix: _dinheiro || pix.isEmpty ? null : pix,
          apelido: apelido.isEmpty ? null : apelido,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editando ? 'Conta atualizada.' : 'Conta criada.')));
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final externa = !_dinheiro && _titularidade == 'externa';
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar conta' : 'Adicionar conta'),
        actions: const [AcoesUsuario()],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _form,
            child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                key: const Key('campo_tipo'),
                value: _tipo,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo de conta'),
                items: const [
                  DropdownMenuItem(value: 'corrente', child: Text('Conta corrente')),
                  DropdownMenuItem(value: 'poupanca', child: Text('Poupança')),
                  DropdownMenuItem(value: 'cartao', child: Text('Cartão de crédito')),
                  DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro (sem banco)')),
                ],
                onChanged: (v) => setState(() => _tipo = v ?? _tipo),
              ),
              if (!_dinheiro) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('campo_titularidade'),
                  value: _titularidade,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Conta de minha titularidade?', hintText: 'Informe se a conta é sua'),
                  items: const [
                    DropdownMenuItem(value: 'propria', child: Text('Sim, a conta é minha')),
                    DropdownMenuItem(value: 'externa', child: Text('Não, é de outra pessoa/empresa')),
                  ],
                  validator: (v) => v == null ? 'Informe se a conta é sua' : null,
                  onChanged: (v) => setState(() => _titularidade = v),
                ),
                const SizedBox(height: 8),
                FormField<String>(
                  key: const Key('campo_banco'),
                  initialValue: _banco,
                  validator: (v) => _banco == null ? 'Escolha o banco' : null,
                  builder: (campo) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final escolhido = await escolherBanco(context, _banco);
                      if (escolhido != null) {
                        setState(() => _banco = escolhido);
                        campo.didChange(escolhido);
                      }
                    },
                    child: InputDecorator(
                      isEmpty: _banco == null,
                      decoration: InputDecoration(
                        labelText: 'Banco',
                        hintText: 'Escolha o banco',
                        errorText: campo.errorText,
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                      ),
                      child: _banco == null
                          ? const SizedBox.shrink()
                          : Row(children: [
                              SeloBanco(_banco, raio: 12),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                      _banco == codigoOutroBanco
                                          ? bancoPorCodigo(_banco).nome
                                          : '${_banco!} · ${bancoPorCodigo(_banco).nome}',
                                      overflow: TextOverflow.ellipsis)),
                            ]),
                    ),
                  ),
                ),
                if (_banco == codigoOutroBanco) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('campo_nome_banco'),
                    controller: _nomeBanco,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nome do banco', hintText: 'Banco que não está na lista'),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Informe o nome do banco' : null,
                  ),
                ],
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const Key('campo_agencia'),
                      controller: _agencia,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9xX-]'))],
                      decoration: const InputDecoration(labelText: 'Agência', hintText: 'Ex: 4444'),
                      validator: validarAgencia,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: const Key('campo_numero'),
                      controller: _numero,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9xX-]'))],
                      decoration: const InputDecoration(labelText: 'Conta', hintText: 'Número da conta'),
                      validator: validarNumeroConta,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_documento'),
                  controller: _documento,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MascaraFormatter.cpfOuCnpj()],
                  decoration: const InputDecoration(labelText: 'CPF/CNPJ (opcional)', hintText: 'Insira o CPF/CNPJ'),
                  validator: validarDocumentoOpcional,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_pix'),
                  controller: _pix,
                  decoration: const InputDecoration(labelText: 'Chave PIX (opcional)', hintText: 'Insira a chave PIX associada à conta'),
                  validator: validarChavePixOpcional,
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('campo_apelido'),
                controller: _apelido,
                decoration: InputDecoration(
                  labelText: _dinheiro ? 'Nome da conta' : 'Apelido para a conta (opcional)',
                  hintText: 'Insira um apelido',
                ),
                validator: (v) => _dinheiro && (v ?? '').trim().isEmpty
                    ? 'Informe um nome para a conta'
                    : null,
              ),
              if (!externa) ...[
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('campo_saldo'),
                  controller: _saldo,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [MoedaFormatter()],
                  decoration: const InputDecoration(labelText: 'Saldo inicial (R\$, opcional)'),
                ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, key: const Key('erro_conta'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('botao_salvar_conta'),
                onPressed: _salvando ? null : _salvar,
                child: Text(_editando ? 'Salvar alterações' : 'Criar conta'),
              ),
            ])),
          ),
        ),
      ),
    );
  }
}

/// Lista pesquisavel com todos os bancos (codigo ou nome). Devolve o codigo escolhido.
Future<String?> escolherBanco(BuildContext context, String? atual) {
  return showDialog<String>(
    context: context,
    builder: (c) => const _EscolherBanco(),
  );
}

class _EscolherBanco extends StatefulWidget {
  const _EscolherBanco();
  @override
  State<_EscolherBanco> createState() => _EscolherBancoState();
}

class _EscolherBancoState extends State<_EscolherBanco> {
  String _busca = '';

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll(RegExp('[úü]'), 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final q = _norm(_busca.trim());
    final lista = [
      for (final b in catalogoBancos)
        if (b.codigo == codigoOutroBanco || q.isEmpty || _norm('${b.codigo} ${b.nome}').contains(q)) b,
    ];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('busca_banco'),
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar banco por nome ou código'),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: lista.length,
              itemBuilder: (_, i) {
                final b = lista[i];
                return ListTile(
                  key: Key('banco_${b.codigo}'),
                  leading: SeloBanco(b.codigo, raio: 14),
                  title: Text(b.codigo == codigoOutroBanco ? 'Novo banco (cadastrar um que não está na lista)' : '${b.codigo} · ${b.nome}'),
                  onTap: () => Navigator.pop(context, b.codigo),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
