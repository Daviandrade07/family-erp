import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/economy_tips.dart';
import '../../core/theme/kinfin_theme.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/kinfin_scope.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/export/csv_export_service.dart';
import '../auth/aal2_guard.dart';
import '../../services/export/csv_saver.dart';
import '../auth/auth_controller.dart';
import 'security_controller.dart';
import 'simple_mode_controller.dart';
import 'usage_mode_controller.dart';
import 'theme_controller.dart';

final familyMembersProvider =
    FutureProvider.autoDispose<List<AppUser>>((ref) async {
  final profile = ref.watch(authControllerProvider).profile;
  if (profile?.familyId == null) return const [];
  return ref.watch(authRepositoryProvider).familyMembers(profile!.familyId!);
});

/// Os 4 temas nomeados do mockup de Perfil. Cada um reaproveita a
/// infraestrutura JÁ existente e persistida (`themeModeProvider` +
/// `accentColorProvider`) — não é um motor de tema novo. Polar Night é o
/// escuro roxo padrão do KinFin; Esmeralda tinge de verde (cor do Modo
/// Compartilhado); Satélite é um escuro mais neutro/azulado; Aurora Boreal é
/// o único claro.
class NamedTheme {
  const NamedTheme(this.name, this.mode, this.accent, this.swatchColor);
  final String name;
  final ThemeMode mode;
  final Color accent;
  final Color swatchColor;
}

final kNamedThemes = <NamedTheme>[
  const NamedTheme('Polar Night', ThemeMode.dark, KinFinColors.solo, KinFinColors.card),
  const NamedTheme('Satélite', ThemeMode.dark, KinFinColors.info, Color(0xFF1B1E29)),
  const NamedTheme('Esmeralda', ThemeMode.dark, KinFinColors.shared, KinFinColors.sharedDeep),
  const NamedTheme('Aurora Boreal', ThemeMode.light, KinFinColors.solo, Color(0xFFE9ECF5)),
];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _setAppLock(
      BuildContext context, WidgetRef ref, bool enable) async {
    if (!enable) {
      await ref.read(appLockProvider.notifier).set(false);
      return;
    }

    // O sistema operacional é a única fonte biométrica: o app não cadastra,
    // armazena nem vê rosto/digital. Pedimos uma confirmação antes de ativar
    // para evitar deixar alguém bloqueado por engano.
    final ok = await ref.read(biometricServiceProvider).authenticate(
          reason: 'Confirme para ativar a proteção do Kinfin',
        );
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'A proteção não foi ativada. Você pode tentar novamente quando quiser.'),
      ));
      return;
    }
    await ref.read(appLockProvider.notifier).set(true);
  }

  /// Entrar numa família existente já tendo conta — cola o código de convite.
  Future<void> _joinAnotherFamily(BuildContext context, WidgetRef ref) async {
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entrar em outra família'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Cole o código de convite que a família compartilhou. Você '
                'passa a ver as finanças dela; o que registrou antes fica no '
                'seu espaço anterior.'),
            const SizedBox(height: 12),
            TextField(
              controller: code,
              decoration:
                  const InputDecoration(hintText: 'Código de convite'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entrar')),
        ],
      ),
    );
    if (ok != true || code.text.trim().isEmpty) return;
    if (!context.mounted) return;
    // Trocar de família é sensível (muda quais dados você vê): exige 2FA.
    if (!await requireAal2(context, ref, reason: 'trocar de família')) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .switchToFamily(code.text.trim());
      if (context.mounted) {
        AppFeedback.success(context, 'Pronto! Você entrou na família.');
      }
    } catch (e) {
      final s = e.toString().toLowerCase();
      final msg = s.contains('outras pessoas')
          ? 'Você já faz parte de uma família com outras pessoas. Peça a um '
              'admin para removê-lo antes de entrar em outra.'
          : (s.contains('não encontrado') || s.contains('invalid'))
              ? 'Código de convite inválido.'
              : 'Não foi possível entrar agora. Confira o código e tente de novo.';
      if (context.mounted) AppFeedback.error(context, msg);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final usageMode = ref.watch(usageModeProvider);
    final accent = ref.watch(accentColorProvider);
    // Estado REAL do 2FA (fator TOTP verificado), lido do Supabase — nunca de
    // uma coluna gravável pelo app. Enquanto carrega, tratamos como inativo.
    final has2fa = ref.watch(twoFactorActiveProvider).valueOrNull ?? false;
    final members = ref.watch(familyMembersProvider);
    final profile = auth.profile;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return KinFinScope(
      child: Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---- Cartão de perfil ----
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: KinFinColors.card,
                  border: Border.all(color: KinFinColors.line),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: scheme.primary,
                      backgroundImage: profile?.avatarUrl != null
                          ? NetworkImage(profile!.avatarUrl!)
                          : null,
                      child: profile?.avatarUrl == null
                          ? Text(
                              profile?.name.isNotEmpty == true
                                  ? profile!.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20),
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile?.name ?? '',
                              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          Text(profile?.email ?? '', style: text.labelSmall),
                        ],
                      ),
                    ),
                    _RoleBadge(role: profile?.role),
                  ],
                ),
              ),

              const _SectionTitle('Aparência', subtitle: 'Escolha o tema da sua preferência.'),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: kNamedThemes.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.8,
                ),
                itemBuilder: (context, i) {
                  final t = kNamedThemes[i];
                  final selected = themeMode == t.mode && accent.toARGB32() == t.accent.toARGB32();
                  return _ThemeSwatch(
                    theme: t,
                    selected: selected,
                    onTap: () {
                      ref.read(themeModeProvider.notifier).set(t.mode);
                      ref.read(accentColorProvider.notifier).set(t.accent);
                    },
                  );
                },
              ),

              const _SectionTitle('Modo do app', subtitle: 'Escolha como deseja usar o aplicativo.'),
              _ModeRow(
                icon: Icons.person_outline_rounded,
                title: 'Modo Solo',
                subtitle: 'Gerencie suas finanças individuais.',
                selected: usageMode == UsageMode.solo,
                onTap: () => ref.read(usageModeProvider.notifier).set(UsageMode.solo),
              ),
              const SizedBox(height: 10),
              _ModeRow(
                icon: Icons.groups_2_outlined,
                title: 'Modo Compartilhado',
                subtitle: 'Gerencie finanças em família.',
                selected: usageMode == UsageMode.grupo,
                onTap: () => ref.read(usageModeProvider.notifier).set(UsageMode.grupo),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'É independente do "Modo simples" abaixo — este decide quem usa; '
                  'aquele, só como a tela é mostrada.',
                  style: text.labelSmall?.copyWith(color: KinFinColors.textMuted),
                ),
              ),

              const _SectionTitle('Segurança'),
              _KinCard(
                child: (ref.watch(biometricAvailableProvider).valueOrNull ?? false)
                    ? SwitchListTile(
                        value: ref.watch(appLockProvider).enabled,
                        onChanged: (v) => _setAppLock(context, ref, v),
                        activeThumbColor: scheme.primary,
                        secondary: Icon(Icons.face_retouching_natural_rounded, color: scheme.primary),
                        title: const Text('Proteção do aparelho'),
                        subtitle: const Text(
                            'Usa Face ID, digital ou o código já configurado no seu celular.'),
                      )
                    : const ListTile(
                        enabled: false,
                        leading: Icon(Icons.fingerprint_rounded),
                        title: Text('Proteção do aparelho'),
                        subtitle: Text('Não disponível neste celular. O app continua '
                            'funcionando normalmente.'),
                      ),
              ),
              const SizedBox(height: 10),
              _KinCard(
                child: ListTile(
                  leading: Icon(Icons.security_rounded, color: scheme.primary),
                  title: Row(
                    children: [
                      const Flexible(child: Text('Autenticação em duas etapas')),
                      const SizedBox(width: 8),
                      _Badge(
                        has2fa ? 'Ativa' : 'Avançado',
                        color: has2fa ? KinFinColors.positive : scheme.primary,
                      ),
                    ],
                  ),
                  subtitle: Text(has2fa
                      ? 'Código do app autenticador ativado'
                      : 'Camada extra com Google Authenticator/Authy '
                          '(opcional, para quem quer o máximo de proteção)'),
                  trailing: has2fa
                      ? const Icon(Icons.check_circle, color: KinFinColors.positive)
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: has2fa ? null : () => context.push('/2fa'),
                ),
              ),

              const _SectionTitle('Preferências'),
              _KinCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.label_outline_rounded, color: scheme.primary),
                  title: const Text('Categorias'),
                  subtitle: const Text('Crie e organize as categorias da família'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/categories'),
                ),
              ),
              const SizedBox(height: 10),
              _KinCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  value: ref.watch(simpleModeProvider),
                  onChanged: (v) => ref.read(simpleModeProvider.notifier).set(v),
                  activeThumbColor: scheme.primary,
                  secondary: Icon(Icons.accessibility_new_rounded, color: scheme.primary),
                  title: const Text('Modo simples'),
                  subtitle: const Text('Tela inicial com botões grandes e voz em primeiro lugar '
                      '— mais fácil de usar.'),
                ),
              ),
              const SizedBox(height: 10),
              _KinCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  value: ref.watch(tipsEnabledProvider),
                  onChanged: (v) => ref.read(tipsEnabledProvider.notifier).set(v),
                  activeThumbColor: scheme.primary,
                  secondary: const Icon(Icons.lightbulb_outline_rounded, color: KinFinColors.attention),
                  title: const Text('Dica de economia ao abrir'),
                  subtitle: const Text('Uma dica prática por dia. Desligue se preferir abrir o app '
                      'direto.'),
                ),
              ),

              const _SectionTitle('Família'),
              if (profile?.familyId != null)
                _KinCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Código de convite', style: text.labelMedium),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              profile!.familyId!,
                              style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: profile.familyId!));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Código copiado')));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              _KinCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.group_add_outlined, color: scheme.primary),
                  title: const Text('Entrar em outra família'),
                  subtitle: const Text('Use um código de convite que você recebeu.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _joinAnotherFamily(context, ref),
                ),
              ),
              const SizedBox(height: 10),
              members.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => _KinCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final m in list) ...[
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primary.withValues(alpha: 0.2),
                            child: Text(m.name[0].toUpperCase(),
                                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                          ),
                          title: Text(m.name),
                          subtitle: Text(m.email),
                          trailing: auth.isAdmin && m.id != profile?.id
                              ? DropdownButton<UserRole>(
                                  value: m.role,
                                  underline: const SizedBox.shrink(),
                                  items: const [
                                    DropdownMenuItem(value: UserRole.admin, child: Text('Admin')),
                                    DropdownMenuItem(value: UserRole.user, child: Text('Membro')),
                                    DropdownMenuItem(value: UserRole.guest, child: Text('Convidado')),
                                  ],
                                  onChanged: (role) async {
                                    if (role == null) return;
                                    await ref.read(authRepositoryProvider).updateMemberRole(m.id, role);
                                    ref.invalidate(familyMembersProvider);
                                  },
                                )
                              : _RoleBadge(role: m.role),
                        ),
                        if (m != list.last) const Divider(height: 1, color: KinFinColors.line),
                      ],
                    ],
                  ),
                ),
              ),

              const _SectionTitle('Seus dados'),
              _KinCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.table_view_rounded, color: scheme.primary),
                      title: const Text('Exportar transações (CSV)'),
                      subtitle: const Text('Baixe suas receitas e despesas para Excel/Sheets.'),
                      trailing: const Icon(Icons.download_rounded),
                      onTap: () => _exportCsv(context, ref, _ExportKind.transactions),
                    ),
                    const Divider(height: 1, color: KinFinColors.line),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_rounded, color: KinFinColors.attention),
                      title: const Text('Exportar contas a pagar (CSV)'),
                      subtitle: const Text('Leve suas contas para onde quiser. Seus dados são seus.'),
                      trailing: const Icon(Icons.download_rounded),
                      onTap: () => _exportCsv(context, ref, _ExportKind.bills),
                    ),
                  ],
                ),
              ),

              const _SectionTitle('Mais'),
              // Itens do mockup sem funcionalidade real ainda no projeto —
              // mostrados honestamente como "em breve", em vez de fingir uma
              // tela de planos/notificações/privacidade que não existe.
              _KinCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ComingSoonItem(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Planos e assinatura',
                      subtitle: 'Gerencie seu plano atual.',
                    ),
                    const Divider(height: 1, color: KinFinColors.line),
                    _ComingSoonItem(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notificações',
                      subtitle: 'Personalize suas preferências.',
                    ),
                    const Divider(height: 1, color: KinFinColors.line),
                    _ComingSoonItem(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacidade',
                      subtitle: 'Controle seus dados e segurança.',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout_rounded, color: KinFinColors.danger),
                label: const Text('Sair da conta', style: TextStyle(color: KinFinColors.danger)),
                onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
              ),
              const SizedBox(height: 20),
              // Carimbo de versão: confirma num relance se o app está atualizado
              // (útil quando o navegador segura uma versão antiga em cache).
              Center(
                child: Text('Kinfin · atualizado em 06/07/2026',
                    style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Card padrão KinFin — mesma superfície usada em Início/Finanças.
class _KinCard extends StatelessWidget {
  const _KinCard({required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: KinFinColors.card,
        border: Border.all(color: KinFinColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {
      UserRole.admin => 'Admin',
      UserRole.guest => 'Convidado',
      _ => 'Membro',
    };
    return _Badge(label, color: role == UserRole.admin ? KinFinColors.positive : KinFinColors.info);
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme, required this.selected, required this.onTap});
  final NamedTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.swatchColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? theme.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Icon(Icons.check_circle_rounded, size: 18, color: theme.accent)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(theme.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: KinFinColors.textMuted)),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: _KinCard(
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: text.labelSmall?.copyWith(color: KinFinColors.textMuted)),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? scheme.primary : KinFinColors.line, width: 2),
                color: selected ? scheme.primary : Colors.transparent,
              ),
              child: selected
                  ? Icon(Icons.circle, size: 8, color: scheme.onPrimary)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonItem extends StatelessWidget {
  const _ComingSoonItem({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: KinFinColors.textMuted),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title chega em breve.'),
          backgroundColor: scheme.primary,
        ),
      ),
    );
  }
}

enum _ExportKind { transactions, bills }

/// Gera o CSV pedido e dispara o download (web) ou compartilhamento (mobile).
Future<void> _exportCsv(
    BuildContext context, WidgetRef ref, _ExportKind kind) async {
  // Ação sensível: os dados saem do app. Exige 2FA quando a pessoa tem
  // (para quem não configurou 2FA, segue sem fricção).
  if (!await requireAal2(context, ref, reason: 'exportar seus dados')) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Gerando arquivo...')));
  try {
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    late final String content;
    late final String filename;

    if (kind == _ExportKind.transactions) {
      final txs = await _allTransactions(ref);
      if (txs.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Nenhuma transação para exportar.')));
        return;
      }
      content = csvExportService.transactions(txs);
      filename = 'transacoes_$stamp.csv';
    } else {
      final bills = await ref.read(billRepositoryProvider).all();
      if (bills.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Nenhuma conta para exportar.')));
        return;
      }
      content = csvExportService.bills(bills);
      filename = 'contas_$stamp.csv';
    }

    await saveCsv(filename, content);
    messenger
        .showSnackBar(SnackBar(content: Text('Arquivo pronto: $filename')));
  } catch (_) {
    messenger.showSnackBar(SnackBar(
        content:
            const Text('Não foi possível exportar agora. Tente novamente.'),
        backgroundColor: KinFinColors.danger));
  }
}

/// Busca todas as transações paginando o repositório.
Future<List<Transaction>> _allTransactions(WidgetRef ref) async {
  final repo = ref.read(transactionRepositoryProvider);
  final all = <Transaction>[];
  for (var page = 0; page < 200; page++) {
    final rows = await repo.fetchPage(page: page);
    all.addAll(rows);
    if (rows.length < TransactionRepository.pageSize) break;
  }
  return all;
}
