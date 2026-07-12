import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Resumo visual da carteira. É uma visão da conta, não uma cópia de cartão
/// físico: não exibe número, CVV, logotipo de banco ou qualquer dado sensível.
class WalletAccountCarousel extends StatefulWidget {
  const WalletAccountCarousel({super.key, required this.accounts});

  final List<FinancialAccount> accounts;

  @override
  State<WalletAccountCarousel> createState() => _WalletAccountCarouselState();
}

class _WalletAccountCarouselState extends State<WalletAccountCarousel> {
  late final PageController _controller = PageController(viewportFraction: .88);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.accounts.isEmpty) return const SizedBox.shrink();
    final pageLabel = '${_page + 1} de ${widget.accounts.length}';
    return Semantics(
      label: 'Carteira, cartão $pageLabel',
      child: Column(
        children: [
          SizedBox(
            height: 196,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.accounts.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final current = _controller.hasClients
                      ? (_controller.page ?? _controller.initialPage.toDouble())
                      : 0.0;
                  final distance = (current - index).abs().clamp(0.0, 1.0);
                  return Transform.scale(
                      scale: 1 - (distance * .045), child: child);
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _WalletCard(account: widget.accounts[index]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                widget.accounts.length,
                (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 6,
                      width: index == _page ? 20 : 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: index == _page
                            ? AppColors.neonGreen
                            : Theme.of(context).colorScheme.outline,
                      ),
                    )),
          ),
        ],
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.account});

  final FinancialAccount account;

  ({IconData icon, String label, List<Color> colors}) get _style =>
      switch (account.type) {
        AccountType.creditCard => (
            icon: Icons.credit_card_rounded,
            label: 'Cartão de crédito',
            colors: const [Color(0xFF30313D), Color(0xFF171827)],
          ),
        AccountType.investment => (
            icon: Icons.trending_up_rounded,
            label: 'Investimento',
            colors: const [Color(0xFF164638), Color(0xFF0B2A24)],
          ),
        AccountType.bankAccount => (
            icon: Icons.account_balance_rounded,
            label: 'Conta',
            colors: const [Color(0xFF173F72), Color(0xFF102948)],
          ),
      };

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final detail =
        account.type == AccountType.creditCard && account.creditLimit != null
            ? 'Limite total ${account.creditLimit!.brl}'
            : style.label;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style.colors,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: style.colors.last.withValues(alpha: .35),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(style.icon, color: Colors.white70),
              const Spacer(),
              const Icon(Icons.nfc_rounded, color: Colors.white54),
            ],
          ),
          const Spacer(),
          Text(account.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  )),
          const SizedBox(height: 4),
          Text(detail, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          Text(account.balance.brl,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  )),
        ],
      ),
    );
  }
}
