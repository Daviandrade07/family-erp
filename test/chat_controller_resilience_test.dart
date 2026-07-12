import 'package:kinfin/features/chat/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('falha do provedor não deixa o chat preso em carregamento', () async {
    final controller = ChatController((_) async {
      throw Exception('network unavailable');
    });
    addTearDown(controller.dispose);

    await controller.send('tem promoção hoje?');

    expect(controller.state.thinking, isFalse);
    expect(controller.state.messages.last.fromUser, isFalse);
    expect(controller.state.messages.last.text, contains('conexão'));
  });
}
