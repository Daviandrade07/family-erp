import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'write_safety.dart';

/// Resultado da confirmação: se o usuário confirmou e os valores (possivelmente
/// CORRIGIDOS no card) que devem ser gravados, mesclados sobre o input original.
class ConfirmationResult {
  const ConfirmationResult(this.confirmed, this.values);
  final bool confirmed;
  final Map<String, dynamic> values;

  static const cancelled = ConfirmationResult(false, {});
}

/// Uma confirmação pendente aguardando o usuário.
class PendingConfirmation {
  PendingConfirmation(this.confirmation, this.completer);
  final WriteConfirmation confirmation;
  final Completer<ConfirmationResult> completer;
}

/// Ponte determinística entre o executor de ferramentas da IA e a UI do chat.
///
/// O executor chama [request] ANTES de gravar; isso publica a confirmação e
/// devolve um Future que só completa quando a UI chama [resolve] com os campos
/// (possivelmente editados). A gravação fica fisicamente bloqueada até o usuário
/// confirmar — é isso que torna "nunca inventar" uma garantia de engenharia.
class WriteConfirmationController
    extends StateNotifier<PendingConfirmation?> {
  WriteConfirmationController() : super(null);

  Future<ConfirmationResult> request(WriteConfirmation confirmation) {
    // Se já houver uma pendente (turno abandonado), libera a anterior como
    // cancelada para não deixar o executor travado para sempre.
    state?.completer.complete(ConfirmationResult.cancelled);
    final completer = Completer<ConfirmationResult>();
    state = PendingConfirmation(confirmation, completer);
    return completer.future;
  }

  void resolve(bool confirmed, [Map<String, dynamic> values = const {}]) {
    final pending = state;
    state = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(ConfirmationResult(confirmed, values));
    }
  }

  @override
  void dispose() {
    final pending = state;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(ConfirmationResult.cancelled);
    }
    super.dispose();
  }
}

final writeConfirmationControllerProvider =
    StateNotifierProvider<WriteConfirmationController, PendingConfirmation?>(
        (ref) => WriteConfirmationController());
