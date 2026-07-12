import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/settings/security_controller.dart';
import 'theme/app_theme.dart';

/// Envolve o app: quando "Bloquear com biometria" está ligado e o usuário
/// está logado, exige digital/rosto ao voltar do segundo plano. Em plataformas
/// sem biometria (ex.: web), o desbloqueio passa direto.
class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _wentBackground = false;
  bool _checking = false;
  bool _initialLockChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _active =>
      ref.read(appLockProvider).enabled &&
      ref.read(authControllerProvider).status == AuthStatus.signedIn;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_active) _wentBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_wentBackground && _active) {
        _wentBackground = false;
        setState(() => _locked = true);
        _authenticate();
      }
    }
  }

  Future<void> _authenticate() async {
    if (_checking) return;
    _checking = true;
    final ok = await ref.read(biometricServiceProvider).authenticate();
    if (mounted && ok) setState(() => _locked = false);
    _checking = false;
  }

  void _lockAndAuthenticate() {
    if (!mounted || !_active || _locked || _checking) return;
    setState(() => _locked = true);
    _authenticate();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn =
        ref.watch(authControllerProvider).status == AuthStatus.signedIn;
    final appLock = ref.watch(appLockProvider);
    // Fecha a lacuna de segurança da abertura fria: uma sessão restaurada só
    // aparece depois do bloqueio local quando a pessoa escolheu ativá-lo.
    if (signedIn && appLock.loaded && !_initialLockChecked) {
      _initialLockChecked = true;
      if (appLock.enabled) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _lockAndAuthenticate());
      }
    } else if (!signedIn) {
      _initialLockChecked = false;
    }
    final locked = _locked && appLock.enabled && signedIn;

    return Stack(
      children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: Material(
              color: AppColors.darkBg,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded,
                        size: 56, color: AppColors.neonGreen),
                    const SizedBox(height: 16),
                    const Text('App bloqueado',
                        style: TextStyle(
                            color: AppColors.darkTextPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Use Face ID, digital ou o código do aparelho',
                        style: TextStyle(color: AppColors.darkTextSecondary)),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _authenticate,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Desbloquear'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
