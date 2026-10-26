import 'package:flutter/material.dart';

import '../../data/api/cliente_api.dart';

/// Agrupa as permissoes por modulo, mantendo a ordem do catalogo.
Map<String, List<PermissaoApi>> permissoesPorModulo(List<PermissaoApi> catalogo) {
  final m = <String, List<PermissaoApi>>{};
  for (final p in catalogo) {
    m.putIfAbsent(p.moduloCodigo, () => []).add(p);
  }
  return m;
}

/// Lista de permissoes com caixas de marcar, agrupada por modulo.
class ChecklistPermissoes extends StatelessWidget {
  const ChecklistPermissoes({
    super.key,
    required this.catalogo,
    required this.marcadas,
    required this.aoMudar,
    this.editavel = true,
  });

  final List<PermissaoApi> catalogo;
  final Set<String> marcadas;
  final ValueChanged<Set<String>> aoMudar;
  final bool editavel;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final grupos = permissoesPorModulo(catalogo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in grupos.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${e.value.first.moduloNome}  ·  ${e.value.where((p) => marcadas.contains(p.codigo)).length}/${e.value.length}',
                  style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (editavel)
                TextButton(
                  key: Key('todos_${e.key}'),
                  onPressed: () {
                    final todas = e.value.every((p) => marcadas.contains(p.codigo));
                    final novo = {...marcadas};
                    for (final p in e.value) {
                      todas ? novo.remove(p.codigo) : novo.add(p.codigo);
                    }
                    aoMudar(novo);
                  },
                  child: Text(e.value.every((p) => marcadas.contains(p.codigo)) ? 'Nenhuma' : 'Todas'),
                ),
            ]),
          ),
          for (final p in e.value)
            CheckboxListTile(
              key: Key('perm_${p.codigo}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(p.nome),
              subtitle: Text(p.codigo, style: tema.textTheme.bodySmall),
              value: marcadas.contains(p.codigo),
              onChanged: editavel
                  ? (v) {
                      final novo = {...marcadas};
                      v == true ? novo.add(p.codigo) : novo.remove(p.codigo);
                      aoMudar(novo);
                    }
                  : null,
            ),
        ],
      ],
    );
  }
}

/// Excecoes individuais: cada permissao fica em 'herdar', 'permitir' ou 'negar'.
class ExcecoesPermissoes extends StatelessWidget {
  const ExcecoesPermissoes({
    super.key,
    required this.catalogo,
    required this.valores,
    required this.efetivas,
    required this.aoMudar,
    this.editavel = true,
  });

  final List<PermissaoApi> catalogo;
  final Map<String, String> valores;

  /// Permissoes que o usuario tem hoje (perfis + grupos + excecoes salvas).
  final Set<String> efetivas;
  final void Function(String codigo, String valor) aoMudar;
  final bool editavel;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final grupos = permissoesPorModulo(catalogo);
    return Column(
      children: [
        for (final e in grupos.entries)
          Builder(builder: (_) {
            final comExcecao = e.value.where((p) => (valores[p.codigo] ?? 'herdar') != 'herdar').length;
            return ExpansionTile(
              key: Key('excecoes_${e.key}'),
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: comExcecao > 0,
              title: Text(e.value.first.moduloNome, style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text(comExcecao == 0 ? 'Sem exceções' : '$comExcecao exceção(ões)'),
              children: [
                for (final p in e.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(p.nome)),
                        Text(
                          efetivas.contains(p.codigo) ? 'Tem' : 'Não tem',
                          style: TextStyle(
                              fontSize: 12,
                              color: efetivas.contains(p.codigo) ? Colors.green.shade700 : tema.colorScheme.outline),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          key: Key('excecao_${p.codigo}'),
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 'herdar', label: Text('Herdar')),
                            ButtonSegment(value: 'permitir', label: Text('Permitir')),
                            ButtonSegment(value: 'negar', label: Text('Negar')),
                          ],
                          selected: {valores[p.codigo] ?? 'herdar'},
                          onSelectionChanged: editavel ? (s) => aoMudar(p.codigo, s.first) : null,
                        ),
                      ),
                    ]),
                  ),
              ],
            );
          }),
      ],
    );
  }
}
