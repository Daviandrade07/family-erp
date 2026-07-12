import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ai/confirmation_service.dart';
import '../../services/ai/write_safety.dart';
import '../theme/app_theme.dart';

/// Card de confirmação inteligente e EDITÁVEL: mostra o que a assistente
/// entendeu e deixa o usuário CORRIGIR cada campo antes de gravar. Confirmar
/// grava os valores já ajustados; Cancelar não grava nada. Compartilhado entre
/// o chat e o Registro Rápido — a mesma trava de segurança em toda entrada.
class WriteConfirmationCard extends ConsumerStatefulWidget {
  const WriteConfirmationCard({super.key, required this.pending});

  final PendingConfirmation pending;

  @override
  ConsumerState<WriteConfirmationCard> createState() =>
      _WriteConfirmationCardState();
}

class _WriteConfirmationCardState extends ConsumerState<WriteConfirmationCard> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, String?> _choice = {};
  final Map<String, DateTime?> _date = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.pending.confirmation.fields) {
      switch (f.kind) {
        case ConfirmFieldKind.text:
        case ConfirmFieldKind.money:
        case ConfirmFieldKind.integer:
          _text[f.key] = TextEditingController(text: f.value);
        case ConfirmFieldKind.choice:
          _choice[f.key] = f.value.isEmpty ? null : f.value;
        case ConfirmFieldKind.date:
          _date[f.key] = f.value.isEmpty ? null : DateTime.tryParse(f.value);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _resolve(bool confirmed) {
    final notifier = ref.read(writeConfirmationControllerProvider.notifier);
    if (!confirmed) {
      notifier.resolve(false);
      return;
    }
    final values = <String, dynamic>{};
    for (final f in widget.pending.confirmation.fields) {
      switch (f.kind) {
        case ConfirmFieldKind.text:
        case ConfirmFieldKind.integer:
          values[f.key] = _text[f.key]!.text.trim();
        case ConfirmFieldKind.money:
          values[f.key] = _text[f.key]!.text.trim().replaceAll(',', '.');
        case ConfirmFieldKind.choice:
          values[f.key] = _choice[f.key] ?? '';
        case ConfirmFieldKind.date:
          final d = _date[f.key];
          values[f.key] = d == null ? '' : d.toIso8601String().substring(0, 10);
      }
    }
    notifier.resolve(true, values);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _editor(ConfirmField f) {
    switch (f.kind) {
      case ConfirmFieldKind.text:
        return TextField(
          controller: _text[f.key],
          decoration: InputDecoration(
              labelText: f.label, hintText: f.hint, isDense: true),
        );
      case ConfirmFieldKind.money:
        return TextField(
          controller: _text[f.key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: f.label,
              prefixText: 'R\$ ',
              hintText: f.hint,
              isDense: true),
        );
      case ConfirmFieldKind.integer:
        return TextField(
          controller: _text[f.key],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: f.label, hintText: f.hint, isDense: true),
        );
      case ConfirmFieldKind.choice:
        return DropdownButtonFormField<String>(
          value: _choice[f.key],
          isExpanded: true,
          decoration: InputDecoration(
              labelText: f.label, hintText: f.hint, isDense: true),
          items: [
            for (final o in f.options ?? const <String>[])
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => setState(() => _choice[f.key] = v),
        );
      case ConfirmFieldKind.date:
        final d = _date[f.key];
        return InputDecorator(
          decoration: InputDecoration(labelText: f.label, isDense: true),
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: d ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (picked != null) setState(() => _date[f.key] = picked);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(d != null ? _fmt(d) : (f.hint ?? 'Escolher data')),
                const Icon(Icons.calendar_today_outlined, size: 16),
              ],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.pending.confirmation;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neonGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined,
                  size: 18, color: AppColors.neonGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(c.title,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(c.understood, style: text.bodySmall),
          const SizedBox(height: 12),
          for (final f in c.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _editor(f),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _resolve(false),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _resolve(true),
                  child: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    )
        // Entrada suave: o card "surge" ao aparecer, sem exagero.
        .animate()
        .fadeIn(duration: 160.ms)
        .moveY(begin: 10, curve: Curves.easeOutCubic);
  }
}
