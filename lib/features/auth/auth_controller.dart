import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/config/env.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

/// Auth phase used by the router redirect.
enum AuthStatus { loading, signedOut, needsFamily, signedIn }

class AuthSessionState {
  const AuthSessionState({required this.status, this.profile});

  final AuthStatus status;
  final AppUser? profile;

  bool get canWrite => profile?.canWrite ?? false;
  bool get isAdmin => profile?.isAdmin ?? false;
}

class AuthController extends StateNotifier<AuthSessionState> {
  AuthController(this._repo)
      : super(const AuthSessionState(status: AuthStatus.loading)) {
    _sub = _repo.onAuthStateChange.listen((_) => refreshProfile());
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await refreshProfile();
    // Dev builds can auto-authenticate to speed up manual testing.
    if (Env.hasDevLogin && state.status == AuthStatus.signedOut) {
      try {
        await signIn(Env.devEmail, Env.devPassword);
      } catch (_) {
        // fall through to the normal login screen
      }
    }
  }

  final AuthRepository _repo;
  late final StreamSubscription _sub;

  /// Refresh de perfil em andamento — coalesce chamadas concorrentes, já que
  /// bootstrap, stream de sessão e login podem disparar quase juntos (B-1).
  Future<void>? _refreshInFlight;

  /// Recarrega o perfil do usuário. Chamadas concorrentes reaproveitam o
  /// refresh em andamento em vez de rodar execuções redundantes.
  Future<void> refreshProfile() => _refreshInFlight ??=
      _refreshProfile().whenComplete(() => _refreshInFlight = null);

  Future<void> _refreshProfile() async {
    if (_repo.session == null) {
      state = const AuthSessionState(status: AuthStatus.signedOut);
      return;
    }
    try {
      final profile = await _repo.fetchProfile();
      if (profile == null) {
        state = const AuthSessionState(status: AuthStatus.signedOut);
      } else if (profile.familyId == null) {
        state =
            AuthSessionState(status: AuthStatus.needsFamily, profile: profile);
      } else {
        state = AuthSessionState(status: AuthStatus.signedIn, profile: profile);
      }
    } catch (_) {
      // B-2: erro (ex.: rede) ao carregar o perfil NÃO deve deslogar às cegas.
      // - Já autenticado (state.profile != null): preserva o estado atual —
      //   um blip de rede não derruba a sessão.
      // - Sem perfil ainda (startup ou login recém-feito): cai para signedOut,
      //   para não prender a UI em "loading" e permitir nova tentativa.
      // Nenhum novo AuthStatus é introduzido; o router não muda.
      if (state.profile == null) {
        state = const AuthSessionState(status: AuthStatus.signedOut);
      }
    }
  }

  Future<void> signIn(String email, String password) async {
    await _repo.signIn(email, password);
    await refreshProfile();
  }

  /// Returns true when the person must confirm their e-mail before signing in.
  Future<bool> signUp(String name, String email, String password) async {
    final requiresEmailConfirmation = await _repo.signUp(name, email, password);
    if (!requiresEmailConfirmation) {
      await refreshProfile();
    }
    return requiresEmailConfirmation;
  }

  /// Confirma o e-mail com o código de 6 dígitos. Ao conferir, o Supabase cria
  /// a sessão; o perfil é recarregado para o app seguir para o próximo passo.
  Future<void> verifyEmailOtp(String email, String token) async {
    await _repo.verifyEmailOtp(email, token);
    await refreshProfile();
  }

  Future<void> resendSignupCode(String email) =>
      _repo.resendSignupCode(email);

  /// Fonte da verdade do 2FA da sessão (nível AAL real).
  bool get hasAal2 => _repo.hasAal2;
  Future<bool> hasVerifiedTotp() => _repo.hasVerifiedTotp();
  Future<void> elevateToAal2(String code) => _repo.elevateToAal2(code);

  Future<void> createFamily(String name) async {
    await _repo.createFamily(name);
    await refreshProfile();
  }

  Future<void> joinFamily(String familyId) async {
    await _repo.joinFamily(familyId);
    await refreshProfile();
  }

  /// Entrar numa família existente já tendo conta (via código de convite).
  Future<void> switchToFamily(String familyId) async {
    await _repo.switchToFamily(familyId.trim());
    await refreshProfile();
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AuthSessionState(status: AuthStatus.signedOut);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthSessionState>(
        (ref) => AuthController(ref.watch(authRepositoryProvider)));

/// Estado REAL do segundo fator (TOTP verificado na conta) — lido do Supabase,
/// nunca de uma coluna gravável pelo app. Fonte da verdade para o selo de 2FA.
final twoFactorActiveProvider = FutureProvider.autoDispose<bool>(
    (ref) => ref.watch(authRepositoryProvider).hasVerifiedTotp());

/// Local biometric gate (Face ID / fingerprint) shown before sensitive data.
class BiometricService {
  final _localAuth = LocalAuthentication();

  Future<bool> get isAvailable async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({
    String reason = 'Desbloqueie para acessar as finanças da família',
  }) async {
    // Plataforma sem biometria (web/desktop sem sensor): não há o que trancar —
    // libera, para não bloquear o usuário para fora. O toggle nem é oferecido
    // nessas plataformas (ver biometricAvailableProvider), então isto só ocorre
    // em situações de borda.
    if (!await isAvailable) return true;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // Em iPhone usa o Face ID já configurado pela própria pessoa; em
          // Android, a digital/rosto disponível. O código do aparelho é um
          // fallback seguro e inclusivo, nunca um cadastro biométrico nosso.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      return ok;
    } on Exception catch (e, st) {
      // Disponível mas falhou (cancelou/erro): fail-CLOSED — permanece
      // bloqueado. Nada de segurança cosmética. Detalhe técnico só no log.
      developer.log('biometric authenticate failed',
          name: 'auth', error: e, stackTrace: st);
      return false;
    }
  }
}

final biometricServiceProvider = Provider((ref) => BiometricService());

/// Há biometria/lock de dispositivo utilizável nesta plataforma? Usado para só
/// oferecer o "Bloquear com biometria" onde ele realmente protege (esconde no
/// web/sem sensor — nada de segurança cosmética).
final biometricAvailableProvider = FutureProvider<bool>(
    (ref) => ref.read(biometricServiceProvider).isAvailable);
