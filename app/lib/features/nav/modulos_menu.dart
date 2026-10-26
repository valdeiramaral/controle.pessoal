import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/cliente_api.dart';
import '../auth/sessao.dart';

/// Modulos cadastrados pelo administrador que o usuario logado pode usar.
/// Viram itens do menu; use `ref.invalidate(modulosMenuProvider)` depois de mudar o cadastro.
final modulosMenuProvider = FutureProvider<List<ModuloMenu>>((ref) async {
  final s = ref.watch(sessaoProvider);
  final token = s.token;
  if (s.fase != FaseSessao.logado || token == null) return const [];
  try {
    return await ref.watch(clienteApiProvider).meusModulos(token);
  } on ErroApi {
    return const [];
  }
});
