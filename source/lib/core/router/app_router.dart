import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/accounts_screen.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/family_setup_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/two_factor_screen.dart';
import '../../features/bills/bills_screen.dart';
import '../../features/budgets/budgets_screen.dart';
import '../../features/debts/debts_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/goals/goals_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/meals/meals_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shopping/shopping_screen.dart';
import '../../features/transactions/add_transaction_screen.dart';
import '../../features/transactions/analytics_screen.dart';
import '../../features/transactions/transactions_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (authState.status) {
        case AuthStatus.loading:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          return loc == '/auth' ? null : '/auth';
        case AuthStatus.needsFamily:
          return loc == '/family-setup' ? null : '/family-setup';
        case AuthStatus.signedIn:
          return (loc == '/splash' || loc == '/auth' || loc == '/family-setup')
              ? '/'
              : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
      GoRoute(
          path: '/family-setup',
          builder: (_, __) => const FamilySetupScreen()),
      GoRoute(path: '/2fa', builder: (_, __) => const TwoFactorScreen()),
      GoRoute(
          path: '/transactions/new',
          builder: (_, __) => const AddTransactionScreen()),
      GoRoute(
          path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
      GoRoute(path: '/budgets', builder: (_, __) => const BudgetsScreen()),
      GoRoute(path: '/accounts', builder: (_, __) => const AccountsScreen()),
      GoRoute(path: '/shopping', builder: (_, __) => const ShoppingScreen()),
      GoRoute(path: '/meals', builder: (_, __) => const MealsScreen()),
      GoRoute(path: '/goals', builder: (_, __) => const GoalsScreen()),
      GoRoute(path: '/bills', builder: (_, __) => const BillsScreen()),
      GoRoute(path: '/debts', builder: (_, __) => const DebtsScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/transactions',
                builder: (_, __) => const TransactionsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/inventory',
                builder: (_, __) => const InventoryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/more', builder: (_, __) => const _MoreScreen()),
          ]),
        ],
      ),
    ],
  );
});

class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    // Web/tablet: side rail. Phone: bottom bar. Full responsiveness.
    final wide = MediaQuery.sizeOf(context).width >= 800;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: shell.goBranch,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('Início')),
                NavigationRailDestination(
                    icon: Icon(Icons.swap_vert_rounded),
                    label: Text('Finanças')),
                NavigationRailDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome),
                    label: Text('IA')),
                NavigationRailDestination(
                    icon: Icon(Icons.kitchen_outlined),
                    selectedIcon: Icon(Icons.kitchen),
                    label: Text('Despensa')),
                NavigationRailDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: Text('Mais')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Início'),
          NavigationDestination(
              icon: Icon(Icons.swap_vert_rounded), label: 'Finanças'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'IA'),
          NavigationDestination(
              icon: Icon(Icons.kitchen_outlined),
              selectedIcon: Icon(Icons.kitchen),
              label: 'Despensa'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Mais'),
        ],
      ),
    );
  }
}

/// Hub with the remaining modules.
class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Orçamentos', Icons.donut_small_rounded, '/budgets'),
      ('Contas e Cartões', Icons.account_balance_rounded, '/accounts'),
      ('Lista de Compras', Icons.shopping_cart_outlined, '/shopping'),
      ('Cardápio Semanal', Icons.restaurant_menu_rounded, '/meals'),
      ('Metas Financeiras', Icons.flag_outlined, '/goals'),
      ('Contas a Pagar', Icons.receipt_long_outlined, '/bills'),
      ('Fiado e Parcelas', Icons.handshake_outlined, '/debts'),
      ('Análises Avançadas', Icons.insights_rounded, '/analytics'),
      ('Configurações', Icons.settings_outlined, '/settings'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Mais')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final (label, icon, route) = items[i];
          final scheme = Theme.of(context).colorScheme;
          return Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => context.push(route),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: scheme.primary),
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
