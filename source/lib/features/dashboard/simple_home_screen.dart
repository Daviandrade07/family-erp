import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../services/alerts_service.dart';
import '../auth/auth_controller.dart';
import '../settings/simple_mode_controller.dart';

/// Tela inicial do MODO SIMPLES (opcional): poucos botões grandes, voz em
/// primeiro lugar e linguagem do dia a dia — para quem quer resolver rápido,
/// enxerga menos ou tem pouca intimidade com o celular.
class SimpleHomeScreen extends ConsumerWidget {
  const SimpleHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).profile;
    final allowance = ref.watch(spendingAllowanceProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Saudação
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.neonGreen.withOpacity(0.2),
                  child: Text(
                    profile?.name.isNotEmpty == true
                        ? profile!.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: AppColors.neonGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Text('Olá, ${profile?.name.split(' ').first ?? ''}',
                    style:
                        text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),

            // Semáforo "posso gastar" — grande e simples
            allowance.when(
              loading: () => const SizedBox(
                  height: 96,
                  child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
              data: (a) {
                final color = switch (a.status) {
                  AllowanceStatus.verde => AppColors.neonGreen,
                  AllowanceStatus.amarelo => AppColors.amber,
                  AllowanceStatus.vermelho => AppColors.red,
                };
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hoje você pode gastar',
                          style: text.titleMedium?.copyWith(color: color)),
                      const SizedBox(height: 4),
                      Text(a.perDay <= 0 ? 'R\$ 0' : a.perDay.brlCompact,
                          style: text.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800, color: color)),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // Botão grande: falar com a IA (voz em primeiro lugar)
            _BigButton(
              label: 'Falar com a ajudante',
              icon: Icons.mic_rounded,
              filled: true,
              onTap: () => context.push('/chat'),
            ),
            const SizedBox(height: 16),

            // 4 ações principais em botões grandes
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.05,
              children: [
                _BigTile(
                  label: 'Comprar',
                  icon: Icons.shopping_cart_rounded,
                  color: AppColors.techBlue,
                  onTap: () => context.push('/shopping'),
                ),
                _BigTile(
                  label: 'Contas',
                  icon: Icons.receipt_long_rounded,
                  color: AppColors.amber,
                  onTap: () => context.push('/bills'),
                ),
                _BigTile(
                  label: 'Comida',
                  icon: Icons.restaurant_rounded,
                  color: AppColors.neonGreen,
                  onTap: () => context.push('/meals'),
                ),
                _BigTile(
                  label: 'Foto da nota',
                  icon: Icons.photo_camera_rounded,
                  color: AppColors.violet,
                  onTap: () => context.push('/transactions/new'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Voltar ao modo completo
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Voltar ao modo completo'),
                onPressed: () =>
                    ref.read(simpleModeProvider.notifier).set(false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.neonGreen : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).colorScheme.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 32,
                  color: filled
                      ? const Color(0xFF06280F)
                      : Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: filled
                        ? const Color(0xFF06280F)
                        : Theme.of(context).colorScheme.onSurface,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  const _BigTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 10),
              Text(label,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
