import 'dart:developer' as developer;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/linkified_text.dart';
import '../../core/widgets/write_confirmation_card.dart';
import '../../services/ai/audio_transcription_service.dart';
import '../../services/ai/chat_assistant_service.dart';
import '../../services/ai/confirmation_service.dart';
import '../../services/ai/ocr_service.dart';
import '../../services/ai/write_safety.dart';
import '../../services/auth_bridge.dart';
import '../../services/receipt_import_service.dart';
import '../capture/voice_capture.dart';
import 'chat_controller.dart';

// Estado/controller da conversa: movidos para chat_controller.dart — são
// compartilhados com o Registro Rápido (P2), que fala com o mesmo cérebro.

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final VoiceCaptureController _voice;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(voiceCaptureFactoryProvider)(
      ref.read(transcriptionProvider),
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

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

  /// Foto da nota fiscal: o OCR extrai os itens e o app registra a despesa e
  /// atualiza a despensa/histórico de preços de forma DETERMINÍSTICA — sem
  /// passar pela IA/chat (evita dupla persistência).
  Future<void> _scanReceiptToChat() async {
    // Gate (Bloco 2C): enquanto não há OCR real, o "escanear nota" NÃO grava
    // nada — o OCR atual é mock e persistiria dados fabricados como reais.
    // Reativar com --dart-define=OCR_ENABLED=true quando houver OCR de verdade.
    if (!Env.ocrEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Leitura de nota fiscal chega em breve. Por enquanto, '
              'registre a compra pela conversa com a IA.')));
      return;
    }
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

      final profile = ref.read(currentProfileProvider);
      if (profile?.familyId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Entre na sua conta para importar a nota.')));
        }
        return;
      }

      // Persiste direto (sem enviar nada ao chat/LLM): despesa + despensa.
      final result = await ref.read(receiptImportServiceProvider).import(
            receipt,
            familyId: profile!.familyId!,
            userId: profile.id,
          );

      if (mounted) {
        final n = result.itemsCreated + result.itemsUpdated;
        AppFeedback.success(
            context, 'Nota importada: 1 despesa e $n item(ns) na despensa.');
      }
    } catch (e, st) {
      developer.log('receipt import failed',
          name: 'chat', error: e, stackTrace: st);
      if (mounted) {
        AppFeedback.error(context, humanizeError(e));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _voice.dispose();
    super.dispose();
  }

  /// Botão de microfone conforme o estado: inicia (com feedback imediato),
  /// pausa ou retoma. Parar+enviar fica no botão de ENVIAR (P2.2).
  Future<void> _micAction() async {
    switch (_voice.state) {
      case VoiceState.idle:
        final err = await _voice.begin();
        if (err != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(err)));
        }
      case VoiceState.recording:
      case VoiceState.paused:
        await _voice.togglePause();
      case VoiceState.preparing:
      case VoiceState.transcribing:
        break;
    }
  }

  /// Enviar: gravando/pausado → PARA a gravação, transcreve e envia numa ação
  /// só ("parar e enviar"). Nunca envia sem esse toque explícito do usuário.
  Future<void> _sendAction() async {
    if (_voice.isActive) {
      final (text, err) = await _voice.finish();
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: AppColors.red));
      }
      if (text != null) _send(text);
      return;
    }
    if (_voice.state != VoiceState.idle) return; // preparando/transcrevendo
    _send();
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
    final pending = ref.watch(writeConfirmationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.explore_outlined, color: AppColors.neonGreen, size: 20),
            SizedBox(width: 8),
            Text('Assistente da família'),
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
                label:
                    Text(_suggestions[i], style: const TextStyle(fontSize: 12)),
                onPressed: () => _send(_suggestions[i]),
              ),
            ),
          ),
          if (pending != null)
            WriteConfirmationCard(key: ValueKey(pending), pending: pending),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _voice.state == VoiceState.idle
                        ? TextField(
                            controller: _input,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              hintText: 'Pergunte ou dite um gasto...',
                            ),
                          )
                        // Gravando/pausado/transcrevendo: o campo vira o
                        // indicador vivo, com cancelar sempre à mão.
                        : Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Theme.of(context).colorScheme.outline),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                    child: RecordingIndicator(
                                        state: _voice.state)),
                                if (_voice.isActive)
                                  IconButton(
                                    tooltip: 'Cancelar gravação',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _voice.cancel,
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  // Utilitários NEUTROS (Design System): a única ação verde da
                  // linha é o enviar. Vermelho no mic só enquanto grava (sinal
                  // vivo), nunca como decoração.
                  // OCR honesto: sem leitura real (OCR_ENABLED), o botão de
                  // nota não aparece.
                  if (Env.ocrEnabled) ...[
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      heroTag: 'receipt',
                      onPressed: _scanning ? null : _scanReceiptToChat,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      elevation: 0,
                      tooltip: 'Fotografar nota fiscal',
                      child: _scanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.document_scanner_outlined,
                              size: 18),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // Mic: inicia → vira pausa/retomar durante a gravação.
                  FloatingActionButton.small(
                    heroTag: 'mic',
                    onPressed: _voice.state == VoiceState.transcribing ||
                            _voice.state == VoiceState.preparing
                        ? null
                        : _micAction,
                    backgroundColor: _voice.state == VoiceState.recording
                        ? AppColors.red
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    foregroundColor: _voice.state == VoiceState.recording
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                    elevation: 0,
                    tooltip: switch (_voice.state) {
                      VoiceState.recording => 'Pausar',
                      VoiceState.paused => 'Continuar gravando',
                      _ => 'Falar',
                    },
                    child: Icon(
                        switch (_voice.state) {
                          VoiceState.recording => Icons.pause_rounded,
                          VoiceState.paused => Icons.play_arrow_rounded,
                          _ => Icons.mic_outlined,
                        },
                        size: 18),
                  ),
                  const SizedBox(width: 8),
                  // Enviar: durante a gravação vira "parar e enviar".
                  FloatingActionButton.small(
                    heroTag: 'send',
                    onPressed: _sendAction,
                    backgroundColor: AppColors.neonGreen,
                    foregroundColor: const Color(0xFF06280F),
                    elevation: 0,
                    tooltip: _voice.isActive ? 'Parar e enviar' : 'Enviar',
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

// Card de confirmação: extraído para core/widgets/write_confirmation_card.dart
// (compartilhado entre o chat e o Registro Rápido).

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
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.neonGreen.withValues(alpha: 0.16)
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
            // Mensagens da assistente: URLs reais viram links clicáveis
            // (sites dos mercados abrem no navegador, sem copiar/colar).
            if (isUser) Text(message.text) else LinkifiedText(message.text),
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
            WidgetStatePropertyAll(scheme.outline.withValues(alpha: 0.25)),
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
          border: Border.all(color: Theme.of(context).colorScheme.outline),
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
                  .animate(onPlay: (c) => c.repeat(), delay: (i * 160).ms)
                  .fadeIn(duration: 350.ms)
                  .then()
                  .fadeOut(duration: 350.ms),
          ],
        ),
      ),
    );
  }
}
