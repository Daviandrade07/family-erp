import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kinfin_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/kinfin_scope.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/auth_controller.dart';

final _membersProvider = FutureProvider.autoDispose.family<List<AppUser>, String>(
  (ref, familyId) => ref.watch(authRepositoryProvider).familyMembers(familyId),
);

/// Sugestão inicial reaproveitando o mesmo cálculo de "quem contribuiu no
/// mês" já usado na Home KinFin (`_expenseByUserProvider`) — sem chamada
/// nova à IA, e usando SEMPRE a mesma fonte real de dado (resolve sozinho
/// a divergência de % que existia entre os mockups de Início e Alocação).
final _monthExpenseByUserProvider = FutureProvider.autoDispose<Map<String, double>>(
  (ref) => ref.watch(transactionRepositoryProvider).monthExpenseByUser(DateTime.now()),
);

/// Alocação da despesa — decide como dividir UMA transação entre os membros
/// da família. A sugestão inicial vem da proporção histórica real de gastos
/// de cada membro no mês (mesmo dado mostrado em "quem contribuiu no mês"
/// na Home). O responsável pela família pode aceitar, editar manualmente ou
/// assumir a divisão sozinho.
///
/// PENDÊNCIA CONHECIDA: não existe hoje uma tabela para persistir a divisão
/// aceita/editada de uma despesa (só existe transactions.user_id = quem
/// LANÇOU, não quem "deve" cada parte). Esta tela é funcional de ponta a
/// ponta na interface, mas o resultado final (Aceitar/Editar) ainda não é
/// gravado no banco — depende de uma decisão de schema nova, fora do escopo
/// desta rodada.
class AllocateExpenseScreen extends ConsumerStatefulWidget {
  const AllocateExpenseScreen({super.key, required this.transaction});
  final Transaction transaction;

  @override
  ConsumerState<AllocateExpenseScreen> createState() => _AllocateExpenseScreenState();
}

class _AllocateExpenseScreenState extends ConsumerState<AllocateExpenseScreen> {
  Map<String, double>? _editedPct; // userId -> % (só quando em edição manual)
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    final familyId = profile?.familyId;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tx = widget.transaction;

    if (familyId == null) {
      return const KinFinScope(
        child: Scaffold(body: Center(child: Text('Sem família vinculada.'))),
      );
    }

    final membersAsync = ref.watch(_membersProvider(familyId));
    final expenseAsync = ref.watch(_monthExpenseByUserProvider);

    return KinFinScope(
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Alocação da despesa', style: TextStyle(fontSize: 16)),
              Text(tx.description ?? tx.category,
                  style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: membersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('Não foi possível carregar a família.')),
            data: (members) => expenseAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Não foi possível calcular a sugestão.')),
              data: (byUser) {
                final total = byUser.values.fold<double>(0, (s, v) => s + v);
                // Sugestão: proporção real do mês; sem histórico, divide igualmente.
                final suggested = <String, double>{
                  for (final m in members)
                    m.id: total > 0
                        ? ((byUser[m.id] ?? 0) / total * 100)
                        : (100 / members.length),
                };
                final pct = _editedPct ?? suggested;
                final pctSum = pct.values.fold<double>(0, (s, v) => s + v);
                final sumIsValid = (pctSum - 100).abs() < 0.5;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 320),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(18),
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                        child: Text(
                          'Vou propor como dividir esta despesa de ${tx.amount.brl}.',
                          style: TextStyle(color: scheme.onPrimary, fontSize: 14, height: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: KinFinColors.card,
                        border: Border.all(color: KinFinColors.line),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Atribuição sugerida entre os membros:',
                              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            _editedPct == null
                                ? 'Baseada na proporção real de gastos deste mês.'
                                : 'Informe como deseja dividir ou edite manualmente os valores.',
                            style: text.labelSmall?.copyWith(color: KinFinColors.textMuted),
                          ),
                          const SizedBox(height: 14),
                          for (var i = 0; i < members.length; i++) ...[
                            if (i > 0) const Divider(height: 24, color: KinFinColors.line),
                            _MemberAllocationRow(
                              member: members[i],
                              isMe: members[i].id == profile?.id,
                              pct: pct[members[i].id] ?? 0,
                              editable: _editedPct != null,
                              onChanged: (v) => setState(() {
                                _editedPct = {...pct, members[i].id: v};
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_accepted)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: KinFinColors.positive.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded, color: KinFinColors.positive, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Divisão registrada nesta tela. A gravação permanente no banco '
                              'depende de uma decisão de schema ainda pendente.',
                              style: text.labelSmall?.copyWith(color: KinFinColors.positive),
                            ),
                          ),
                        ]),
                      )
                    else ...[
                      if (!sumIsValid)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Total atual: ${pctSum.round()}% — ajuste os percentuais até '
                            'somar 100% para aceitar.',
                            style: text.labelSmall?.copyWith(
                                color: KinFinColors.attention, fontWeight: FontWeight.w600),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Tooltip(
                            message: sumIsValid
                                ? 'Aceitar a divisão sugerida'
                                : 'A soma dos percentuais precisa ser 100% '
                                    '(atual: ${pctSum.round()}%)',
                            child: FilledButton(
                              onPressed: sumIsValid
                                  ? () => setState(() => _accepted = true)
                                  : null,
                              child: const Text('Aceitar sugestão'),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => setState(() => _editedPct = Map.of(pct)),
                            child: const Text('Editar divisão'),
                          ),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _editedPct = {
                                for (final m in members)
                                  m.id: m.id == profile?.id ? 100.0 : 0.0,
                              };
                            }),
                            child: const Text('Fazer eu mesmo'),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberAllocationRow extends StatelessWidget {
  const _MemberAllocationRow({
    required this.member,
    required this.isMe,
    required this.pct,
    required this.editable,
    required this.onChanged,
  });
  final AppUser member;
  final bool isMe;
  final double pct;
  final bool editable;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: scheme.primary,
          child: Text(member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: isMe ? 'Você (${member.name})' : member.name,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                TextSpan(
                    text: '  (${pct.round()}%)',
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
              ])),
              const SizedBox(height: 3),
              Text(
                'Proporcional à participação real deste membro nos gastos do mês.',
                style: text.labelSmall?.copyWith(color: KinFinColors.textMuted),
              ),
              if (editable) ...[
                const SizedBox(height: 6),
                Slider(
                  value: pct.clamp(0, 100),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: scheme.primary,
                  onChanged: onChanged,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
