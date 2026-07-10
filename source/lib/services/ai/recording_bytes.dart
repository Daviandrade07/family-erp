// Lê os bytes de uma gravação de áudio de forma multiplataforma.
//
// - Mobile/desktop: `dart:io` File (o gravador salva num arquivo).
// - Web: fetch da URL de blob que o gravador cria.
export 'recording_bytes_io.dart'
    if (dart.library.html) 'recording_bytes_web.dart';
