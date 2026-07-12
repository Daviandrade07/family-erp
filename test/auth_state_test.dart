import 'package:kinfin/data/repositories/repositories.dart';
import 'package:kinfin/features/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// T6 — Máquina de estados do `AuthController`.
///
/// Cobre as transições de `refreshProfile` conforme sessão + perfil, usando um
/// `FakeAuthRepository` (nenhum login/sessão/storage reais). O stream de auth
/// nunca emite, então não há refresh concorrente; `Env.hasDevLogin` é false nos
/// testes (sem defines), então o bootstrap não tenta auto-login.
void main() {
  late FakeAuthRepository fakeAuth;
  late ProviderContainer container;

  setUp(() {
    fakeAuth = FakeAuthRepository();
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
    ]);
  });

  tearDown(() {
    container.dispose();
    fakeAuth.dispose();
  });

  AuthController controller() =>
      container.read(authControllerProvider.notifier);

  test('signedOut quando não há sessão', () async {
    fakeAuth.sessionValue = null;
    final c = controller();
    await c.refreshProfile();
    expect(c.state.status, AuthStatus.signedOut);
    expect(c.state.profile, isNull);
  });

  test('needsFamily quando há sessão mas o perfil não tem família', () async {
    fakeAuth.sessionValue = FakeSession();
    fakeAuth.profileValue = buildUser(); // sem familyId
    final c = controller();
    await c.refreshProfile();
    expect(c.state.status, AuthStatus.needsFamily);
    expect(c.state.profile?.id, 'user-1');
  });

  test('signedIn quando há sessão e perfil com família', () async {
    fakeAuth.sessionValue = FakeSession();
    fakeAuth.profileValue = buildUser(familyId: 'fam-1');
    final c = controller();
    await c.refreshProfile();
    expect(c.state.status, AuthStatus.signedIn);
    expect(c.state.canWrite, isTrue); // role user
  });

  test('signedOut quando há sessão mas o perfil não é encontrado', () async {
    fakeAuth.sessionValue = FakeSession();
    fakeAuth.profileValue = null;
    final c = controller();
    await c.refreshProfile();
    expect(c.state.status, AuthStatus.signedOut);
  });

  // --- B-1: coalescing de refreshes concorrentes ---
  test('refreshes concorrentes reaproveitam um único carregamento de perfil',
      () async {
    fakeAuth.sessionValue = FakeSession();
    fakeAuth.profileValue = buildUser(familyId: 'fam-1');
    final c = controller();
    await c.refreshProfile(); // deixa o bootstrap assentar
    fakeAuth.fetchProfileCalls = 0; // zera para medir só as concorrentes

    final f1 = c.refreshProfile();
    final f2 = c.refreshProfile();
    final f3 = c.refreshProfile();
    await f1;
    await f2;
    await f3;

    expect(fakeAuth.fetchProfileCalls, 1);
    expect(c.state.status, AuthStatus.signedIn);
  });

  // --- B-2: erro de fetchProfile não desloga às cegas ---
  test('erro de perfil no startup/login (sem perfil prévio) vira signedOut',
      () async {
    fakeAuth.sessionValue = FakeSession();
    fakeAuth.throwOnFetch = true;
    final c = controller();
    await c.refreshProfile();
    expect(c.state.status, AuthStatus.signedOut);
  });

  test('erro de perfil com usuário já autenticado preserva o estado', () async {
    fakeAuth.sessionValue = FakeSession();
    fakeAuth.profileValue = buildUser(familyId: 'fam-1');
    final c = controller();
    await c.refreshProfile();
    expect(c.state.status, AuthStatus.signedIn);

    // Um refresh que falha (rede) NÃO deve derrubar a sessão já estabelecida.
    fakeAuth.throwOnFetch = true;
    await c.refreshProfile();
    expect(c.state.status, AuthStatus.signedIn);
    expect(c.state.profile?.id, 'user-1');
  });
}
