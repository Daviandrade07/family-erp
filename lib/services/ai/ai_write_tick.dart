import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incrementado sempre que a IA grava algo. Os providers de dados das telas
/// visíveis (Início, Finanças, Casa) observam este tick e refazem a busca —
/// então o que a IA registra aparece na hora, sem o usuário recarregar a
/// página. É a "camada de dados viva" da promessa "Agora ficou fácil usar".
final aiWriteTickProvider = StateProvider<int>((ref) => 0);
