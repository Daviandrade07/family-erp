import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/ai_config.dart';
import '../../core/config/env.dart';
import '../../services/ai/chat_assistant_service.dart';
import '../../services/ai/claude_assistant_service.dart';
import '../../services/ai/openai_compatible_assistant_service.dart';
import '../../services/ai/write_safety.dart';

/// Estado e controller da conversa com a assistente — compartilhados entre a
/// tela de chat e o Registro Rápido (P2): os dois falam com o MESMO cérebro,
/// no mesmo histórico, com as mesmas guardas de segurança.

/// Backend do chat, por prioridade: Claude (Anthropic) > provedor
/// OpenAI-compatible (Groq/Ollama) > motor offline de demonstração.
final chatBackendProvider =
    Provider<Future<ChatMessage> Function(String)>((ref) {
  if (Env.hasAnthropicKey) {
    return ref.watch(claudeAssistantProvider).send;
  }
  if (AiConfig.available) {
    return ref.watch(openAiCompatibleAssistantProvider).send;
  }
  return ref.watch(chatAssistantProvider).interpret;
});

/// Há um agente de IA real (com function calling) configurado?
bool get hasLiveAgent => Env.hasAnthropicKey || AiConfig.available;

class ChatState {
  const ChatState({this.messages = const [], this.thinking = false});

  final List<ChatMessage> messages;
  final bool thinking;
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._backend)
      : super(ChatState(messages: [
          ChatMessage(
            fromUser: false,
            text: hasLiveAgent
                ? 'Oi! Eu cuido das finanças e da casa com vocês.\n'
                    'Pode falar do seu jeito: "gastei 50 reais no posto" '
                    '(texto ou áudio), "monta minha lista de compras" ou '
                    '"qual mercado compensa mais hoje?".'
                : 'Oi! Eu cuido das finanças da família com vocês.\n'
                    'Pergunte do seu jeito — por exemplo: '
                    '"Quanto gastamos com lazer esse mês?" ou '
                    '"Qual mercado compensa mais ir hoje?"',
          ),
        ]));

  final Future<ChatMessage> Function(String) _backend;

  Future<void> send(String input) async {
    if (input.trim().isEmpty || state.thinking) return;
    state = ChatState(
      messages: [
        ...state.messages,
        ChatMessage(fromUser: true, text: input.trim()),
      ],
      thinking: true,
    );
    try {
      final reply = await _backend(input);
      state = ChatState(messages: [...state.messages, reply]);
    } catch (error) {
      // Mesmo se um provedor externo falhar fora das guardas do serviço, o
      // chat volta a aceitar mensagens e nunca deixa a família em "pensando".
      state = ChatState(messages: [
        ...state.messages,
        ChatMessage(fromUser: false, text: humanizeError(error)),
      ]);
    }
  }
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
    (ref) => ChatController(ref.watch(chatBackendProvider)));
