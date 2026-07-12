import 'dart:io';
import 'dart:typed_data';

/// Lê os bytes do áudio gravado (mobile/desktop: caminho de arquivo).
Future<Uint8List> recordingBytes(String path) => File(path).readAsBytes();
