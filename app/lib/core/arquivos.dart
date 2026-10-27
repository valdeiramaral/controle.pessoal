import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/banco.dart';

/// Arquivo escolhido pelo usuario para anexar (comprovante, cupom...).
typedef ArquivoAnexo = ArquivoParaAnexar;

typedef EscolherArquivos = Future<List<ArquivoAnexo>> Function();

String? tipoMimePelaExtensao(String nome) {
  final p = nome.toLowerCase().split('.');
  final ext = p.length > 1 ? p.last : '';
  return switch (ext) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'txt' => 'text/plain',
    _ => null,
  };
}

/// Abre o seletor de arquivos do aparelho/navegador (varios de uma vez).
Future<List<ArquivoAnexo>> escolherArquivosDoAparelho() async {
  final r = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    withData: true,
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'heic', 'txt'],
  );
  if (r == null) return const [];
  return [
    for (final f in r.files)
      if (f.bytes != null) ArquivoAnexo(nome: f.name, bytes: f.bytes!, tipoMime: tipoMimePelaExtensao(f.name)),
  ];
}

/// Trocavel nos testes (sem abrir janela de arquivos de verdade).
final escolhedorArquivosProvider = Provider<EscolherArquivos>((ref) => escolherArquivosDoAparelho);

/// Entrega o arquivo ao usuario: baixa no navegador (web) ou grava na pasta do aparelho.
typedef BaixarArquivo = Future<void> Function(String nome, Uint8List bytes, String? tipoMime);

Future<void> baixarArquivoDoAparelho(String nome, Uint8List bytes, String? tipoMime) async {
  final ponto = nome.lastIndexOf('.');
  final base = ponto > 0 ? nome.substring(0, ponto) : nome;
  final ext = ponto > 0 ? nome.substring(ponto + 1) : '';
  await FileSaver.instance.saveFile(
    name: base,
    bytes: bytes,
    fileExtension: ext,
    mimeType: MimeType.custom,
    customMimeType: tipoMime ?? 'application/octet-stream',
  );
}

/// Trocavel nos testes.
final baixadorArquivosProvider = Provider<BaixarArquivo>((ref) => baixarArquivoDoAparelho);
