// Salva/compartilha um CSV de forma multiplataforma.
//
// - Web: dispara o download do arquivo pelo navegador.
// - Mobile/desktop: grava num arquivo temporário e abre a folha de
//   compartilhamento (salvar, enviar por WhatsApp/e-mail etc.).
export 'csv_saver_io.dart' if (dart.library.html) 'csv_saver_web.dart';
