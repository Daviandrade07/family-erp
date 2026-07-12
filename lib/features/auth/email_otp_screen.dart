import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_feedback.dart';
import 'auth_controller.dart';

/// Tela própria para confirmar a POSSE do e-mail com um código de 6 dígitos
/// (fluxo oficial signUp → verifyOTP). Só aparece quando a confirmação de
/// e-mail está ligada no backend; enquanto não estiver, o cadastro segue como
/// hoje. Confirma o endereço — **não** substitui o 2FA real (TOTP/AAL2).
class EmailOtpScreen extends ConsumerStatefulWidget {
  const EmailOtpScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends ConsumerState<EmailOtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      AppFeedback.error(context, 'Digite os 6 números do código.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyEmailOtp(widget.email, code);
      // Sessão criada: o redirect do router leva ao próximo passo sozinho.
      // Mensagem neutra, sem expor detalhes da conta.
    } catch (_) {
      if (mounted) {
        AppFeedback.error(
            context, 'Código inválido ou expirado. Confira e tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .resendSignupCode(widget.email);
    } catch (_) {
      // Mensagem cofre: nunca revelamos se o e-mail existe ou não.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _startCountdown();
        // Sempre a mesma resposta, exista ou não a conta (anti-enumeração).
        AppFeedback.info(
            context, 'Se este cadastro precisar de código, enviamos um novo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final masked = _maskEmail(widget.email);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/auth'),
        ),
        title: const Text('Confirme seu e-mail'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandLagoon.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.mark_email_read_outlined,
                size: 34, color: AppColors.brandLagoon),
          ),
          const SizedBox(height: 18),
          Text('Enviamos um código de 6 números',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            widget.email.isEmpty
                ? 'Confira seu e-mail e digite o código para confirmar o cadastro.'
                : 'Confira $masked e digite o código para confirmar o cadastro.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            enabled: !_busy,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800, letterSpacing: 8),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••••',
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Confirmar'),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: (_secondsLeft == 0 && !_busy) ? _resend : null,
              child: Text(
                _secondsLeft == 0
                    ? 'Reenviar código'
                    : 'Reenviar em ${_secondsLeft}s',
                style: TextStyle(
                  color: _secondsLeft == 0
                      ? AppColors.brandLagoon
                      : text.bodySmall?.color?.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'O código confirma que o e-mail é seu. Ele não é uma senha nem um '
            'segundo fator — o 2FA de verdade fica em Perfil, quando você quiser.',
            style: text.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Mascara o e-mail para não expor o endereço inteiro na tela.
String _maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 1) return email;
  final name = email.substring(0, at);
  final domain = email.substring(at);
  final visible = name.length <= 2 ? name.substring(0, 1) : name.substring(0, 2);
  return '$visible${'•' * (name.length - visible.length)}$domain';
}
