import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../settings/usage_mode_controller.dart';

/// Escopo de visibilidade por modo — REGRA PURA (testável, sem I/O).
///
/// - **Solo** = visão privada: só o MEU `user_id`.
/// - **Compartilhado** = visão da família: `null` (sem filtro por autor → a RLS
///   por `family_id` cuida do resto).
///
/// Família de 1 membro: em Solo o filtro é o meu id, que já é o único autor —
/// então os dados coincidem com o Compartilhado; muda só o enquadramento.
String? scopeUserId(UsageMode mode, String? myUserId) =>
    mode == UsageMode.solo ? myUserId : null;

/// `user_id` de escopo do modo atual (null em Compartilhado). As telas KinFin
/// filtram as transações por isto. **Não** é lido pelas telas Casa Viva —
/// elas seguem mostrando a família inteira, sem mudança de comportamento.
final scopeUserIdProvider = Provider<String?>((ref) {
  final mode = ref.watch(usageModeProvider);
  final myId = ref.watch(authControllerProvider).profile?.id;
  return scopeUserId(mode, myId);
});
