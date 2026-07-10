import 'dart:async';

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

  Future<void> refreshProfile() async {
    if (_repo.session == null) {
      state = const AuthSessionState(status: AuthStatus.signedOut);
      return;
    }
    try {
      final profile = await _repo.fetchProfile();
      if (profile == null) {
        state = const AuthSessionState(status: AuthStatus.signedOut);
      } else if (profile.familyId == null) {
        state = AuthSessionState(
            status: AuthStatus.needsFamily, profile: profile);
      } else {
        state =
            AuthSessionState(status: AuthStatus.signedIn, profile: profile);
      }
    } catch (_) {
      state = const AuthSessionState(status: AuthStatus.signedOut);
    }
  }

  Future<void> signIn(String email, String password) async {
    await _repo.signIn(email, password);
    await refreshProfile();
  }

  Future<void> signUp(String name, String email, String password) async {
    await _repo.signUp(name, email, password);
    await refreshProfile();
  }

  Future<void> createFamily(String name) async {
    await _repo.createFamily(name);
    await refreshProfile();
  }

  Future<void> joinFamily(String familyId) async {
    await _repo.joinFamily(familyId);
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

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Desbloqueie para acessar as finanças da família',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on Exception {
      // Web / unsupported platforms: skip the gate rather than lock out.
      return true;
    }
  }
}

final biometricServiceProvider = Provider((ref) => BiometricService());
