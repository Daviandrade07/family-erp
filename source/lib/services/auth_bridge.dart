import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/models.dart';
import '../features/auth/auth_controller.dart';

/// Ponte entre a camada de serviços e o estado de autenticação, para que os
/// serviços de IA acessem o perfil logado (user_id/family_id) sem acoplar-se
/// à árvore de widgets.
final currentProfileProvider = Provider<AppUser?>(
  (ref) => ref.watch(authControllerProvider).profile,
);
