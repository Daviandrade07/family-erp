import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/accounts_screen.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/casa/casa_screen.dart';
import '../../features/finance/finance_hub_screen.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/email_otp_screen.dart';
import '../../features/auth/family_setup_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/two_factor_screen.dart';
import '../../features/bills/bills_screen.dart';
import '../widgets/floating_nav_bar.dart';
import '../../features/budgets/budgets_screen.dart';
import '../../features/cards/cards_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/debts/debts_screen.dart';
import '../../features/mode/kinfin_home_screen.dart';
import '../../features/recurring/recurring_screen.dart';
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

/// Transição padrão para telas empurradas: fade + leve deslize para cima.
/// Suave e curta; respeita a redução de movimento do sistema.
Page<void> _slidePage(Widget child) => CustomTransitionPage<void>(
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.of(context).disableAnimations) return child;
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
                    .animate(curved),
            child: child,
          ),
        );
      },
    );

/// Faz o GoRouter reavaliar o redirect quando o login muda de estado — SEM
/// recriar o roteador. Recriar a cada transição de auth (o que acontecia com
/// `ref.watch` aqui) reiniciava a navegação em cascata durante o cadastro e
/// podia prender a pessoa na tela de login mesmo já autenticada.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Construído UMA vez: usa `ref.listen` (não `ref.watch`), então o provider
  // não reconstrói o router; só notifica o redirect via refreshListenable.
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      final loc = state.matchedLocation;
      switch (status) {
        case AuthStatus.loading:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          // A confirmação de e-mail (código de 6 dígitos) acontece ANTES de
          // existir sessão — por isso essa tela é permitida enquanto signedOut.
          return (loc == '/auth' || loc == '/confirm-email') ? null : '/auth';
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
          path: '/confirm-email',
          builder: (_, state) =>
              EmailOtpScreen(email: (state.extra as String?) ?? '')),
      GoRoute(
          path: '/family-setup',
          builder: (_, __) => const FamilySetupScreen()),
      // Telas empurradas: transição suave (fade + deslize). O `_slidePage`
      // preserva o comportamento de navegação; muda só a animação de entrada.
      GoRoute(
          path: '/2fa',
          pageBuilder: (_, __) => _slidePage(const TwoFactorScreen())),
      GoRoute(
          path: '/transactions/new',
          pageBuilder: (_, __) => _slidePage(const AddTransactionScreen())),
      GoRoute(
          path: '/analytics',
          pageBuilder: (_, __) => _slidePage(const AnalyticsScreen())),
      GoRoute(
          path: '/budgets',
          pageBuilder: (_, __) => _slidePage(const BudgetsScreen())),
      GoRoute(
          path: '/accounts',
          pageBuilder: (_, __) => _slidePage(const AccountsScreen())),
      GoRoute(
          path: '/cards',
          pageBuilder: (_, __) => _slidePage(const CardsScreen())),
      GoRoute(
          path: '/recurring',
          pageBuilder: (_, __) => _slidePage(const RecurringScreen())),
      GoRoute(
          path: '/categories',
          pageBuilder: (_, __) => _slidePage(const CategoriesScreen())),
      GoRoute(
          path: '/kinfin',
          pageBuilder: (_, __) => _slidePage(const KinFinHomeScreen())),
      GoRoute(
          path: '/shopping',
          pageBuilder: (_, __) => _slidePage(const ShoppingScreen())),
      GoRoute(
          path: '/meals',
          pageBuilder: (_, __) => _slidePage(const MealsScreen())),
      GoRoute(
          path: '/goals',
          pageBuilder: (_, __) => _slidePage(const GoalsScreen())),
      GoRoute(
          path: '/bills',
          pageBuilder: (_, __) => _slidePage(const BillsScreen())),
      GoRoute(
          path: '/debts',
          pageBuilder: (_, __) => _slidePage(const DebtsScreen())),
      GoRoute(
          path: '/settings',
          pageBuilder: (_, __) => _slidePage(const SettingsScreen())),
      GoRoute(
          path: '/chat',
          pageBuilder: (_, __) => _slidePage(const ChatScreen())),
      GoRoute(
          path: '/transactions',
          pageBuilder: (_, __) => _slidePage(const TransactionsScreen())),
      GoRoute(
          path: '/inventory',
          pageBuilder: (_, __) => _slidePage(const InventoryScreen())),
      // Navegação principal: 4 abas (Início · Finanças · Casa · Perfil).
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/finance',
                builder: (_, __) => const FinanceHubScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/casa', builder: (_, __) => const CasaScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/perfil', builder: (_, __) => const SettingsScreen()),
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
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: Text('Início')),
                NavigationRailDestination(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                    label: Text('Finanças')),
                NavigationRailDestination(
                    icon: Icon(Icons.home_work_outlined),
                    selectedIcon: Icon(Icons.home_work_rounded),
                    label: Text('Casa')),
                NavigationRailDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: Text('Perfil')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: shell.currentIndex,
        onSelect: shell.goBranch,
        items: const [
          FloatingNavItem(
              Icons.home_outlined, Icons.home_rounded, 'Início'),
          FloatingNavItem(Icons.account_balance_wallet_outlined,
              Icons.account_balance_wallet_rounded, 'Finanças'),
          FloatingNavItem(
              Icons.home_work_outlined, Icons.home_work_rounded, 'Casa'),
          FloatingNavItem(
              Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
        ],
      ),
    );
  }
}

// "Mais" dissolvido: seus itens agora vivem em Finanças, Casa e Perfil.
