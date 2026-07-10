import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Mobile/desktop: grava o CSV num arquivo temporário e abre a folha de
/// compartilhamento (salvar no dispositivo, enviar por WhatsApp/e-mail...).
Future<void> saveCsv(String filename, String content) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  // BOM UTF-8 para abrir acentos corretamente no Excel.
  await file.writeAsString('﻿$content');
  await Share.shareXFiles([XFile(file.path)], subject: filename);
}
