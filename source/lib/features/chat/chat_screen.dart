import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/config/env.dart';
import '../../core/config/ai_config.dart';
import '../../core/theme/app_theme.dart';
import '../../services/ai/audio_transcription_service.dart';
import '../../services/ai/chat_assistant_service.dart';
import '../../services/ai/ocr_service.dart';
import '../../services/ai/claude_assistant_service.dart';
import '../../services/ai/openai_compatible_assistant_service.dart';
import '../../services/ai/recording_bytes.dart';

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
bool get _hasLiveAgent => Env.hasAnthropicKey || AiConfig.available;

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
            text: _hasLiveAgent
                ? 'Oi! Sou o assistente inteligente da família. 🤖\n'
                    'Posso analisar as finanças, registrar '
                    'gastos ("gastei 50 reais no posto" — por texto ou áudio '
                    '🎙️), montar sua lista de compras e dizer qual mercado '
                    'de Indaiatuba compensa mais.'
                : 'Oi! Sou o assistente financeiro da família. 🤖\n'
                    'Pergunte em linguagem natural — por exemplo: '
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
    final reply = await _backend(input);
    state = ChatState(messages: [...state.messages, reply]);
  }
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>(
        (ref) => ChatController(ref.watch(chatBackendProvider)));

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  bool _listening = false;
  bool _transcribing = false;

  static const _suggestions = [
    'Tem promoção nos mercados de Indaiatuba essa semana?',
    'Qual o preço do contrafilé hoje na região?',
    'Qual mercado está com o café mais barato?',
    'Adicionar arroz',
    'Monte meu planejamento de pagamentos',
    'Posso comprar um tênis de R\$ 300 agora?',
    'Temos contas atrasadas? Devo me preocupar?',
    'Onde podemos economizar?',
    'Gere um gráfico dos gastos do mês',
  ];

  bool _scanning = false;

  /// Foto da nota fiscal direto no chat: o OCR extrai os itens e a IA
  /// registra a despesa e atualiza a despensa/histórico de preços.
  Future<void> _scanReceiptToChat() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
              source: ImageSource.camera, maxWidth: 1600) ??
          await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (photo == null) return;

      final receipt = await ProviderScope.containerOf(context, listen: false)
          .read(ocrServiceProvider)
          .scanReceipt(await photo.readAsBytes());

      final itens = receipt.items
          .map((i) =>
              '${i.quantity}x ${i.name} — R\$ ${i.unitPrice.toStringAsFixed(2)} cada')
          .join('; ');
      final message = '[Nota fiscal escaneada] Mercado: '
          '${receipt.merchantName} (CNPJ ${receipt.cnpj}), data '
          '${receipt.date.toIso8601String().substring(0, 10)}, total R\$ '
          '${receipt.total.toStringAsFixed(2)}. Itens: $itens.';
      ref.read(chatControllerProvider.notifier).send(message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falha ao ler a nota: $e'),
            backgroundColor: AppColors.red));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  /// Entrada por voz inteligente: grava o áudio e transcreve com o Whisper
  /// (entende fala com sotaque e ruído, devolve em português). O texto vai
  /// para o campo para o usuário revisar e enviar.
  Future<void> _toggleVoice() async {
    // Se está gravando: para, transcreve e coloca o texto no campo.
    if (_listening) {
      final path = await _recorder.stop();
      setState(() {
        _listening = false;
        _transcribing = true;
      });
      try {
        if (path == null) throw Exception('Nada gravado.');
        final bytes = await recordingBytes(path);
        final text = await audioTranscriptionService.transcribe(
          bytes,
          filename: kIsWeb ? 'audio.webm' : 'audio.m4a',
          contentType: kIsWeb ? 'audio/webm' : 'audio/mp4',
        );
        if (text.isNotEmpty) {
          _input.text = _input.text.isEmpty ? text : '${_input.text} $text';
          _input.selection =
              TextSelection.collapsed(offset: _input.text.length);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Não entendi o áudio. Tente falar de novo.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Falha ao transcrever: $e'),
              backgroundColor: AppColors.red));
        }
      } finally {
        if (mounted) setState(() => _transcribing = false);
      }
      return;
    }

    // Começa a gravar.
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permita o uso do microfone para falar.')));
      }
      return;
    }
    var path = '';
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    await _recorder.start(
      RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
      ),
      path: path,
    );
    setState(() => _listening = true);
  }

  void _send([String? text]) {
    final msg = text ?? _input.text;
    if (msg.trim().isEmpty) return;
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(msg);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: AppColors.neonGreen, size: 20),
            SizedBox(width: 8),
            Text('Assistente IA'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: state.messages.length + (state.thinking ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= state.messages.length) {
                  return const _TypingIndicator();
                }
                return _MessageBubble(message: state.messages[i]);
              },
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ActionChip(
                label: Text(_suggestions[i],
                    style: const TextStyle(fontSize: 12)),
                onPressed: () => _send(_suggestions[i]),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _transcribing
                            ? 'Entendendo o áudio...'
                            : _listening
                                ? 'Ouvindo... fale agora 🎙️'
                                : 'Pergunte ou dite um gasto...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'receipt',
                    onPressed: _scanning ? null : _scanReceiptToChat,
                    backgroundColor: AppColors.violet.withOpacity(0.2),
                    foregroundColor: AppColors.violet,
                    elevation: 0,
                    tooltip: 'Fotografar nota fiscal',
                    child: _scanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.document_scanner_outlined,
                            size: 18),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'mic',
                    onPressed: _transcribing ? null : _toggleVoice,
                    backgroundColor: _listening
                        ? AppColors.red
                        : AppColors.techBlue.withOpacity(0.2),
                    foregroundColor:
                        _listening ? Colors.white : AppColors.techBlue,
                    elevation: 0,
                    tooltip: _listening ? 'Parar e transcrever' : 'Falar',
                    child: _transcribing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            _listening
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            size: 18),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    heroTag: 'send',
                    onPressed: _send,
                    backgroundColor: AppColors.neonGreen,
                    foregroundColor: const Color(0xFF06280F),
                    elevation: 0,
                    child: const Icon(Icons.send_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.fromUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.neonGreen.withOpacity(0.16)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: Border.all(color: scheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.text),
            if (message.table != null) ...[
              const SizedBox(height: 12),
              _ChatTableView(table: message.table!),
            ],
            if (message.chart != null && message.chart!.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 150,
                child: message.chartIsPie
                    ? _MiniPie(points: message.chart!)
                    : _MiniBars(points: message.chart!),
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).moveY(begin: 8),
    );
  }
}

class _ChatTableView extends StatelessWidget {
  const _ChatTableView({required this.table});

  final ChatTable table;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        horizontalMargin: 8,
        columnSpacing: 20,
        headingRowColor:
            WidgetStatePropertyAll(scheme.outline.withOpacity(0.25)),
        columns: [
          for (final h in table.headers)
            DataColumn(
                label: Text(h,
                    style: text.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w800))),
        ],
        rows: [
          for (final row in table.rows)
            DataRow(cells: [
              for (final cell in row)
                DataCell(Text(cell, style: text.bodySmall)),
            ]),
        ],
      ),
    );
  }
}

class _MiniPie extends StatelessWidget {
  const _MiniPie({required this.points});

  final List<ChatChartPoint> points;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 24,
              sections: [
                for (final p in points)
                  PieChartSectionData(
                    value: p.value,
                    color: AppColors.categoryColor(p.label),
                    radius: 34,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in points.take(5))
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.categoryColor(p.label),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(p.label,
                          style: Theme.of(context).textTheme.labelSmall,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.points});

  final List<ChatChartPoint> points;

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= points.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    points[i].label.length > 6
                        ? points[i].label.substring(0, 6)
                        : points[i].label,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: points[i].value,
                width: 14,
                borderRadius: BorderRadius.circular(4),
                color: AppColors.categoryColor(points[i].label),
              ),
            ]),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  color: AppColors.neonGreen,
                  shape: BoxShape.circle,
                ),
              )
                  .animate(
                      onPlay: (c) => c.repeat(),
                      delay: (i * 160).ms)
                  .fadeIn(duration: 350.ms)
                  .then()
                  .fadeOut(duration: 350.ms),
          ],
        ),
      ),
    );
  }
}
