import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/documentos.dart';
import '../../data/api/cliente_api.dart';
import 'validacoes.dart';
import 'widgets_auth.dart';

/// Controladores dos campos de dados pessoais, compartilhados pelo cadastro,
/// por "Meus dados" e pelo cadastro feito pelo administrador.
class DadosPessoaisControladores {
  DadosPessoaisControladores([UsuarioApi? u])
      : nome = TextEditingController(text: u?.nome ?? ''),
        email = TextEditingController(text: u?.email ?? ''),
        cpf = TextEditingController(text: formatarCpf(u?.cpf)),
        telefone = TextEditingController(text: formatarTelefone(u?.telefone)),
        nascimento = TextEditingController(text: isoParaDataBr(u?.nascimento)),
        cep = TextEditingController(text: formatarCep(u?.endereco.cep)),
        logradouro = TextEditingController(text: u?.endereco.logradouro ?? ''),
        numero = TextEditingController(text: u?.endereco.numero ?? ''),
        complemento = TextEditingController(text: u?.endereco.complemento ?? ''),
        bairro = TextEditingController(text: u?.endereco.bairro ?? ''),
        cidade = TextEditingController(text: u?.endereco.cidade ?? ''),
        uf = TextEditingController(text: u?.endereco.uf ?? '');

  final TextEditingController nome, email, cpf, telefone, nascimento;
  final TextEditingController cep, logradouro, numero, complemento, bairro, cidade, uf;

  /// Algum campo de endereco ou o nascimento foi preenchido (para abrir a secao opcional).
  bool get temOpcionais =>
      [nascimento, cep, logradouro, numero, complemento, bairro, cidade, uf].any((c) => c.text.trim().isNotEmpty);

  /// Endereco no formato da API (so digitos no CEP; texto vazio vira null).
  Map<String, dynamic> enderecoJson() {
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return {
      'cep': soDigitos(cep.text).isEmpty ? null : soDigitos(cep.text),
      'logradouro': v(logradouro),
      'numero': v(numero),
      'complemento': v(complemento),
      'bairro': v(bairro),
      'cidade': v(cidade),
      'uf': v(uf)?.toUpperCase(),
    };
  }

  /// 'AAAA-MM-DD' ou null quando vazio.
  String? nascimentoIso() => dataBrParaIso(nascimento.text);

  void dispose() {
    for (final c in [nome, email, cpf, telefone, nascimento, cep, logradouro, numero, complemento, bairro, cidade, uf]) {
      c.dispose();
    }
  }
}

// -------------------------------------------------------------- campos

Widget campoNome(BuildContext context, DadosPessoaisControladores c) => TextFormField(
      key: const Key('campo_nome'),
      controller: c.nome,
      textCapitalization: TextCapitalization.words,
      autofillHints: const [AutofillHints.name],
      textInputAction: TextInputAction.next,
      decoration: decoracaoCampo(context, 'Nome completo', Icons.person_outline),
      validator: validarNome,
    );

Widget campoEmail(BuildContext context, DadosPessoaisControladores c, {bool habilitado = true}) => TextFormField(
      key: const Key('campo_email'),
      controller: c.email,
      enabled: habilitado,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.next,
      decoration: decoracaoCampo(context, 'E-mail', Icons.mail_outline),
      validator: validarEmail,
    );

Widget campoCpf(BuildContext context, DadosPessoaisControladores c, {bool habilitado = true}) => TextFormField(
      key: const Key('campo_cpf'),
      controller: c.cpf,
      enabled: habilitado,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')), MascaraFormatter.cpf()],
      textInputAction: TextInputAction.next,
      decoration: decoracaoCampo(context, 'CPF', Icons.badge_outlined),
      validator: validarCpf,
    );

Widget campoTelefone(BuildContext context, DadosPessoaisControladores c) => TextFormField(
      key: const Key('campo_telefone'),
      controller: c.telefone,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9()\- ]')), MascaraFormatter.telefone()],
      textInputAction: TextInputAction.next,
      decoration: decoracaoCampo(context, 'Telefone (com DDD)', Icons.phone_outlined),
      validator: validarTelefone,
    );

/// Nascimento e endereco: tudo opcional.
class SecaoOpcional extends StatelessWidget {
  const SecaoOpcional({super.key, required this.c, this.aberta = false});

  final DadosPessoaisControladores c;
  final bool aberta;

  Widget _linha(List<Widget> filhos, {List<int>? pesos}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < filhos.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(flex: pesos?[i] ?? 1, child: filhos[i]),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Theme(
      data: tema.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('secao_endereco'),
        initiallyExpanded: aberta,
        maintainState: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: const Text('Endereço e nascimento (opcional)'),
        leading: const Icon(Icons.home_outlined),
        children: [
          TextFormField(
            key: const Key('campo_nascimento'),
            controller: c.nascimento,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, MascaraFormatter.data()],
            textInputAction: TextInputAction.next,
            decoration: decoracaoCampo(context, 'Data de nascimento (dd/mm/aaaa)', Icons.cake_outlined),
            validator: validarNascimentoOpcional,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('campo_cep'),
            controller: c.cep,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, MascaraFormatter.cep()],
            textInputAction: TextInputAction.next,
            decoration: decoracaoCampo(context, 'CEP', Icons.pin_drop_outlined),
            validator: validarCepOpcional,
          ),
          const SizedBox(height: 12),
          _linha([
            TextFormField(
              key: const Key('campo_logradouro'),
              controller: c.logradouro,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: decoracaoCampo(context, 'Rua / Avenida', Icons.signpost_outlined),
            ),
            TextFormField(
              key: const Key('campo_numero'),
              controller: c.numero,
              textInputAction: TextInputAction.next,
              decoration: decoracaoCampo(context, 'Nº', Icons.numbers),
            ),
          ], pesos: const [3, 2]),
          const SizedBox(height: 12),
          _linha([
            TextFormField(
              key: const Key('campo_complemento'),
              controller: c.complemento,
              textInputAction: TextInputAction.next,
              decoration: decoracaoCampo(context, 'Complemento', Icons.apartment_outlined),
            ),
            TextFormField(
              key: const Key('campo_bairro'),
              controller: c.bairro,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: decoracaoCampo(context, 'Bairro', Icons.holiday_village_outlined),
            ),
          ]),
          const SizedBox(height: 12),
          _linha([
            TextFormField(
              key: const Key('campo_cidade'),
              controller: c.cidade,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: decoracaoCampo(context, 'Cidade', Icons.location_city_outlined),
            ),
            TextFormField(
              key: const Key('campo_uf'),
              controller: c.uf,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                LengthLimitingTextInputFormatter(2),
              ],
              textInputAction: TextInputAction.done,
              decoration: decoracaoCampo(context, 'UF', Icons.map_outlined),
              validator: validarUfOpcional,
            ),
          ], pesos: const [3, 2]),
        ],
      ),
    );
  }
}
