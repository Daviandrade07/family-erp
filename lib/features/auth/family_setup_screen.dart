import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_feedback.dart';
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
      if (mounted) AppFeedback.error(context, errorMsg);
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
                      const StatusBadge('Só para mim',
                          color: AppColors.neonGreen,
                          icon: Icons.person_rounded),
                      const SizedBox(height: 12),
                      Text('Comece cuidando da sua vida',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Text(
                        'Suas finanças e seus sonhos ficam só com você. Quando quiser, poderá convidar sua família.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => auth.createFamily('Meu espaço'),
                                  'Não foi possível criar seu espaço.',
                                ),
                        child: const Text('Usar só para mim'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusBadge('Com a família',
                          color: AppColors.techBlue,
                          icon: Icons.home_work_rounded),
                      const SizedBox(height: 12),
                      Text('Criar o espaço da família',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _familyName,
                        decoration: const InputDecoration(
                            hintText: 'Ex.: Família Andrade'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
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
                        child: const Text('Criar espaço da família'),
                      ),
                      const SizedBox(height: 20),
                      Text('Já recebeu um convite?',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _inviteCode,
                        decoration: const InputDecoration(
                            hintText: 'Código de convite'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () =>
                                      auth.joinFamily(_inviteCode.text.trim()),
                                  'Código inválido.',
                                ),
                        child: const Text('Entrar em família existente'),
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
