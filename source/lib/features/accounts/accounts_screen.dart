import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/auth_controller.dart';

final accountsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(accountRepositoryProvider).all(orderBy: 'name', asc: true));

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    final name = TextEditingController();
    final balance = TextEditingController(text: '0');
    final limit = TextEditingController();
    AccountType type = AccountType.bankAccount;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nova conta / cartão',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              SegmentedButton<AccountType>(
                segments: const [
                  ButtonSegment(
                      value: AccountType.bankAccount, label: Text('Conta')),
                  ButtonSegment(
                      value: AccountType.creditCard, label: Text('Cartão')),
                  ButtonSegment(
                      value: AccountType.investment, label: Text('Invest.')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setSheet(() => type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      hintText: 'Nome (ex.: Nubank, Itaú...)')),
              const SizedBox(height: 12),
              TextField(
                controller: balance,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    hintText: 'Saldo inicial', prefixText: 'R\$ '),
              ),
              if (type == AccountType.creditCard) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: limit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      hintText: 'Limite de crédito', prefixText: 'R\$ '),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Salvar')),
            ],
          ),
        ),
      ),
    );

    if (saved != true || name.text.trim().isEmpty) return;
    await ref.read(accountRepositoryProvider).insertRow(FinancialAccount(
          id: '',
          familyId: profile!.familyId!,
          name: name.text.trim(),
          type: type,
          balance:
              double.tryParse(balance.text.replaceAll(',', '.')) ?? 0,
          creditLimit: double.tryParse(limit.text.replaceAll(',', '.')),
        ).toInsert());
    ref.invalidate(accountsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Contas e Cartões')),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _add(context, ref),
              backgroundColor: AppColors.neonGreen,
              foregroundColor: const Color(0xFF06280F),
              child: const Icon(Icons.add),
            )
          : null,
      body: accounts.when(
        loading: () => const LoadingSkeleton(itemCount: 4, itemHeight: 96),
        error: (e, _) => ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(accountsProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.account_balance_rounded,
                title: 'Nenhuma conta cadastrada',
                subtitle:
                    'Cadastre contas, cartões e investimentos para acompanhar '
                    'o patrimônio da família.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final a = list[i];
                  final (icon, color, label) = switch (a.type) {
                    AccountType.bankAccount => (
                        Icons.account_balance_rounded,
                        AppColors.techBlue,
                        'Conta bancária'
                      ),
                    AccountType.creditCard => (
                        Icons.credit_card_rounded,
                        AppColors.violet,
                        'Cartão de crédito'
                      ),
                    AccountType.investment => (
                        Icons.trending_up_rounded,
                        AppColors.neonGreen,
                        'Investimento'
                      ),
                  };
                  final usedLimit = a.type == AccountType.creditCard &&
                          a.creditLimit != null &&
                          a.creditLimit! > 0
                      ? (-a.balance / a.creditLimit!).clamp(0.0, 1.0)
                      : null;

                  return AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: color),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(a.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700)),
                                  Text(label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall),
                                ],
                              ),
                            ),
                            Text(
                              a.balance.brl,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: a.balance >= 0
                                        ? AppColors.neonGreen
                                        : AppColors.red,
                                  ),
                            ),
                          ],
                        ),
                        if (usedLimit != null) ...[
                          const SizedBox(height: 12),
                          DynamicProgressBar(ratio: usedLimit),
                          const SizedBox(height: 6),
                          Text(
                            'Limite usado: ${(usedLimit * 100).toStringAsFixed(0)}% '
                            'de ${a.creditLimit!.brl}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
