import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import 'auth_controller.dart';

/// Post-signup step: create a new family (becoming admin) or join an
/// existing one with an invite code (the family UUID).
class FamilySetupScreen extends ConsumerStatefulWidget {
  const FamilySetupScreen({super.key});

  @override
  ConsumerState<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends ConsumerState<FamilySetupScreen> {
  final _familyName = TextEditingController();
  final _inviteCode = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _familyName.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String errorMsg) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorMsg), backgroundColor: AppColors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar família'),
        actions: [
          TextButton(
            onPressed: () => auth.signOut(),
            child: const Text('Sair'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusBadge('Nova família',
                          color: AppColors.neonGreen,
                          icon: Icons.add_home_rounded),
                      const SizedBox(height: 12),
                      Text('Crie o espaço da sua família',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _familyName,
                        decoration: const InputDecoration(
                            hintText: 'Ex.: Família Andrade'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () async {
                                    if (_familyName.text.trim().isEmpty) {
                                      throw Exception('nome vazio');
                                    }
                                    await auth
                                        .createFamily(_familyName.text.trim());
                                  },
                                  'Não foi possível criar a família.',
                                ),
                        child: const Text('Criar e ser administrador'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusBadge('Convite',
                          color: AppColors.techBlue,
                          icon: Icons.group_add_rounded),
                      const SizedBox(height: 12),
                      Text('Entrar em uma família existente',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        'Peça ao administrador o código da família '
                        '(em Configurações).',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _inviteCode,
                        decoration: const InputDecoration(
                            hintText: 'Código de convite'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => auth
                                      .joinFamily(_inviteCode.text.trim()),
                                  'Código inválido.',
                                ),
                        child: const Text('Entrar na família'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
