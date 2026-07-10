import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/repositories.dart';
import 'auth_controller.dart';

/// TOTP 2FA enrollment flow (Supabase MFA): shows the secret/URI for the
/// authenticator app and verifies the 6-digit code.
class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _code = TextEditingController();
  String? _factorId;
  String? _secret;
  String? _uri;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _enroll();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(authRepositoryProvider).enrollTotp();
      setState(() {
        _factorId = res.factorId;
        _secret = res.secret;
        _uri = res.uri;
        _error = null;
      });
    } catch (e) {
      setState(() => _error =
          'Não foi possível iniciar o 2FA. Habilite MFA no projeto Supabase.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_factorId == null || _code.text.length != 6) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .verifyTotp(_factorId!, _code.text);
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('2FA ativado com sucesso! 🔒')));
        context.pop();
      }
    } catch (_) {
      setState(() => _error = 'Código inválido. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ativar 2FA')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security_rounded,
                    size: 48, color: AppColors.techBlue),
                const SizedBox(height: 16),
                Text(
                  'Autenticação em duas etapas',
                  textAlign: TextAlign.center,
                  style:
                      text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Adicione a chave abaixo no seu app autenticador '
                  '(Google Authenticator, Authy...) e informe o código gerado.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_busy && _secret == null)
                  const Center(child: CircularProgressIndicator())
                else if (_secret != null) ...[
                  if (_uri != null && _uri!.isNotEmpty) ...[
                    AppCard(
                      child: Column(
                        children: [
                          Text('Escaneie este QR no app autenticador',
                              style: text.labelMedium,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: _uri!,
                              size: 180,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Ou, se preferir, digite a chave manualmente:',
                        style: text.labelSmall, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                  ],
                  AppCard(
                    child: Column(
                      children: [
                        Text('Chave secreta', style: text.labelMedium),
                        const SizedBox(height: 8),
                        SelectableText(
                          _secret!,
                          textAlign: TextAlign.center,
                          style: text.titleMedium?.copyWith(
                              fontFamily: 'monospace', letterSpacing: 2),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copiar chave'),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _uri ?? _secret!));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Chave copiada')));
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall
                        ?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration:
                        const InputDecoration(hintText: '000000', counterText: ''),
                    onSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: const Text('Verificar e ativar'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  StatusBadge(_error!,
                      color: AppColors.red, icon: Icons.error_outline),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
