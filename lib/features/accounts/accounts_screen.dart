import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/wallet_account_carousel.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth/auth_controller.dart';

final accountsProvider = FutureProvider.autoDispose((ref) =>
    ref.watch(accountRepositoryProvider).all(orderBy: 'name', asc: true));

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  void _showOpenFinanceInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 38,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outline,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Icon(Icons.account_balance_outlined,
                size: 32, color: AppColors.techBlue),
            const SizedBox(height: 14),
            Text('Open Finance, do jeito certo',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text(
              'Quando esta conexão estiver disponível, você escolherá o banco e será levado ao aplicativo dele para confirmar o consentimento. O Kinfin não pede nem guarda sua senha bancária.',
            ),
            const SizedBox(height: 14),
            const Text(
              'A conexão será somente para leitura de saldos e gastos, poderá ser revogada a qualquer momento e só será ativada com parceiro regulado.',
              style: TextStyle(color: AppColors.darkTextSecondary),
            ),
          ],
        ),
      ),
    );
  }

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
            left: 20,
            right: 20,
            top: 20,
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
          balance: double.tryParse(balance.text.replaceAll(',', '.')) ?? 0,
          creditLimit: double.tryParse(limit.text.replaceAll(',', '.')),
        ).toInsert());
    ref.invalidate(accountsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas e Cartões'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Faturas dos cartões',
            onPressed: () => context.push('/cards'),
          ),
        ],
      ),
      floatingActionButton: auth.canWrite
          ? FloatingActionButton(
              onPressed: () => _add(context, ref),
              backgroundColor: AppColors.brandCoral,
              foregroundColor: const Color(0xFF3A1611),
              child: const Icon(Icons.add),
            )
          : null,
      body: accounts.when(
        loading: () => const LoadingSkeleton(itemCount: 4, itemHeight: 96),
        error: (e, _) => ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(accountsProvider)),
        data: (list) => list.isEmpty
            ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  EmptyState(
                    icon: Icons.account_balance_rounded,
                    title: 'Nenhuma conta cadastrada',
                    subtitle:
                        'Cadastre contas, cartões e investimentos para acompanhar '
                        'o patrimônio da família.',
                    actionLabel: auth.canWrite ? 'Adicionar conta' : null,
                    onAction: auth.canWrite ? () => _add(context, ref) : null,
                  ),
                  const SectionHeader('Conexões'),
                  _OpenFinanceCard(onTap: () => _showOpenFinanceInfo(context)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  WalletAccountCarousel(accounts: list),
                  const SectionHeader('Suas contas'),
                  ...list.map((account) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AccountListCard(account: account),
                      )),
                  const SectionHeader('Conexões'),
                  _OpenFinanceCard(onTap: () => _showOpenFinanceInfo(context)),
                ],
              ),
      ),
    );
  }
}

class _OpenFinanceCard extends StatelessWidget {
  const _OpenFinanceCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        child: const ListTile(
          leading:
              Icon(Icons.account_balance_outlined, color: AppColors.techBlue),
          title: Text('Open Finance'),
          subtitle: Text('Conexão bancária segura em preparação'),
          trailing: StatusBadge('Em preparação', color: AppColors.techBlue),
        ),
      );
}

class _AccountListCard extends StatelessWidget {
  const _AccountListCard({required this.account});

  final FinancialAccount account;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (account.type) {
      AccountType.bankAccount => (
          Icons.account_balance_rounded,
          AppColors.techBlue,
          'Conta bancária'
        ),
      AccountType.creditCard => (
          Icons.credit_card_rounded,
          AppColors.catSlate,
          'Cartão de crédito'
        ),
      AccountType.investment => (
          Icons.trending_up_rounded,
          AppColors.neonGreen,
          'Investimento'
        ),
    };
    final usedLimit = account.type == AccountType.creditCard &&
            account.creditLimit != null &&
            account.creditLimit! > 0
        ? (-account.balance / account.creditLimit!).clamp(0.0, 1.0)
        : null;
    final isCard = account.type == AccountType.creditCard;
    return AppCard(
      onTap: isCard ? () => context.push('/cards') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(label, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              Text(account.balance.brl,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: account.balance >= 0
                            ? AppColors.neonGreen
                            : AppColors.red,
                      )),
            ],
          ),
          if (usedLimit != null) ...[
            const SizedBox(height: 12),
            DynamicProgressBar(ratio: usedLimit),
            const SizedBox(height: 6),
            Text(
              'Limite usado: ${(usedLimit * 100).toStringAsFixed(0)}% de ${account.creditLimit!.brl}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}
