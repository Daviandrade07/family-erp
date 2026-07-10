import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web: dispara o download do CSV no navegador.
Future<void> saveCsv(String filename, String content) async {
  // BOM UTF-8 para o Excel abrir os acentos corretamente.
  final bytes = utf8.encode('﻿$content');
  final blob = html.Blob([bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
