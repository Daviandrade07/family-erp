import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Lê os bytes do áudio gravado (web: URL de blob criada pelo gravador).
Future<Uint8List> recordingBytes(String path) =>
    http.readBytes(Uri.parse(path));
