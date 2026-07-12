import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/economy_tips.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_widgets.dart';
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
          reason: 'Confirme para ativar a proteção do Família ERP',
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

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.neonGreen.withValues(alpha: 0.2),
                  backgroundImage: profile?.avatarUrl != null
                      ? NetworkImage(profile!.avatarUrl!)
                      : null,
                  child: profile?.avatarUrl == null
                      ? Text(
                          profile?.name.isNotEmpty == true
                              ? profile!.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: AppColors.neonGreen,
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
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(profile?.email ?? '',
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                StatusBadge(
                  switch (profile?.role) {
                    UserRole.admin => 'Admin',
                    UserRole.guest => 'Convidado',
                    _ => 'Membro',
                  },
                  color: profile?.isAdmin == true
                      ? AppColors.neonGreen
                      : AppColors.techBlue,
                ),
              ],
            ),
          ),
          const SectionHeader('Segurança'),
          // Só oferece o bloqueio biométrico onde ele realmente protege — em
          // plataformas sem biometria (web/desktop sem sensor) o toggle nem
          // aparece, para não vender segurança que não existe.
          // App Lock sempre visível e honesto: interruptor real onde há
          // biometria; onde não há (ex.: web), aparece desabilitado e explicado
          // — nunca some silenciosamente.
          AppCard(
            padding: EdgeInsets.zero,
            child: (ref.watch(biometricAvailableProvider).valueOrNull ?? false)
                ? SwitchListTile(
                    value: ref.watch(appLockProvider).enabled,
                    onChanged: (v) => _setAppLock(context, ref, v),
                    activeThumbColor: AppColors.neonGreen,
                    secondary: const Icon(Icons.face_retouching_natural_rounded,
                        color: AppColors.neonGreen),
                    title: const Text('Proteção do aparelho'),
                    subtitle: const Text(
                        'Usa Face ID, digital ou o código já configurado no seu celular.'),
                  )
                : const ListTile(
                    enabled: false,
                    leading: Icon(Icons.fingerprint_rounded),
                    title: Text('Proteção do aparelho'),
                    subtitle:
                        Text('Não disponível neste celular. O app continua '
                            'funcionando normalmente.'),
                  ),
          ),
          const SizedBox(height: 12),
          // Extra opcional/avançado: 2FA por app autenticador.
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading:
                  const Icon(Icons.security_rounded, color: AppColors.techBlue),
              title: Row(
                children: [
                  const Flexible(child: Text('Autenticação em duas etapas')),
                  const SizedBox(width: 8),
                  StatusBadge(
                    has2fa ? 'Ativa' : 'Avançado',
                    color: has2fa ? AppColors.neonGreen : AppColors.techBlue,
                  ),
                ],
              ),
              subtitle: Text(has2fa
                  ? 'Código do app autenticador ativado'
                  : 'Camada extra com Google Authenticator/Authy '
                      '(opcional, para quem quer o máximo de proteção)'),
              trailing: has2fa
                  ? const Icon(Icons.check_circle, color: AppColors.neonGreen)
                  : const Icon(Icons.chevron_right_rounded),
              onTap: has2fa ? null : () => context.push('/2fa'),
            ),
          ),
          const SectionHeader('Como você usa'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<UsageMode>(
                  segments: const [
                    ButtonSegment(
                        value: UsageMode.solo,
                        label: Text('Sozinho(a)'),
                        icon: Icon(Icons.person_outline_rounded)),
                    ButtonSegment(
                        value: UsageMode.grupo,
                        label: Text('Em família'),
                        icon: Icon(Icons.groups_2_outlined)),
                  ],
                  selected: {usageMode},
                  onSelectionChanged: (s) =>
                      ref.read(usageModeProvider.notifier).set(s.first),
                ),
                const SizedBox(height: 10),
                Text(
                  usageMode == UsageMode.solo
                      ? 'O app fala no singular: seu dinheiro, suas metas.'
                      : 'O app é compartilhado: finanças e metas da família.',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'É independente do "Modo simples" abaixo — este decide quem '
                  'usa; aquele, só como a tela é mostrada.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.label_outline_rounded,
                  color: AppColors.lagoon),
              title: const Text('Categorias'),
              subtitle: const Text('Crie e organize as categorias da família'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/categories'),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined,
                  color: AppColors.violet),
              title: const Text('Nova identidade (prévia)'),
              subtitle: const Text('Conheça o modo Solo/Compartilhado do KinFin'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/kinfin'),
            ),
          ),
          const SectionHeader('Aparência'),
          AppCard(
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Claro'),
                    icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Escuro'),
                    icon: Icon(Icons.dark_mode_outlined)),
                ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Sistema'),
                    icon: Icon(Icons.settings_suggest_outlined)),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cor de acento',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Um toque de cor seu, sem perder a leitura.',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final a in kAppAccents)
                      _AccentSwatch(
                        accent: a,
                        selected: accent.toARGB32() == a.color.toARGB32(),
                        onTap: () =>
                            ref.read(accentColorProvider.notifier).set(a.color),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: ref.watch(simpleModeProvider),
              onChanged: (v) => ref.read(simpleModeProvider.notifier).set(v),
              activeColor: AppColors.neonGreen,
              secondary: const Icon(Icons.accessibility_new_rounded,
                  color: AppColors.techBlue),
              title: const Text('Modo simples'),
              subtitle: const Text(
                  'Tela inicial com botões grandes e voz em primeiro lugar '
                  '— mais fácil de usar.'),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: ref.watch(tipsEnabledProvider),
              onChanged: (v) => ref.read(tipsEnabledProvider.notifier).set(v),
              activeColor: AppColors.neonGreen,
              secondary: const Icon(Icons.lightbulb_outline_rounded,
                  color: AppColors.amber),
              title: const Text('Dica de economia ao abrir'),
              subtitle: const Text(
                  'Uma dica prática por dia. Desligue se preferir abrir o app '
                  'direto.'),
            ),
          ),
          const SectionHeader('Família'),
          if (profile?.familyId != null)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Código de convite',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          profile!.familyId!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: profile.familyId!));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Código copiado')));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.group_add_outlined,
                  color: AppColors.techBlue),
              title: const Text('Entrar em outra família'),
              subtitle:
                  const Text('Use um código de convite que você recebeu.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _joinAnotherFamily(context, ref),
            ),
          ),
          const SizedBox(height: 12),
          members.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final m in list) ...[
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.techBlue.withValues(alpha: 0.2),
                        child: Text(m.name[0].toUpperCase(),
                            style: const TextStyle(
                                color: AppColors.techBlue,
                                fontWeight: FontWeight.w700)),
                      ),
                      title: Text(m.name),
                      subtitle: Text(m.email),
                      trailing: auth.isAdmin && m.id != profile?.id
                          ? DropdownButton<UserRole>(
                              value: m.role,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(
                                    value: UserRole.admin,
                                    child: Text('Admin')),
                                DropdownMenuItem(
                                    value: UserRole.user,
                                    child: Text('Membro')),
                                DropdownMenuItem(
                                    value: UserRole.guest,
                                    child: Text('Convidado')),
                              ],
                              onChanged: (role) async {
                                if (role == null) return;
                                await ref
                                    .read(authRepositoryProvider)
                                    .updateMemberRole(m.id, role);
                                ref.invalidate(familyMembersProvider);
                              },
                            )
                          : StatusBadge(
                              switch (m.role) {
                                UserRole.admin => 'Admin',
                                UserRole.guest => 'Convidado',
                                _ => 'Membro',
                              },
                              color: m.isAdmin
                                  ? AppColors.neonGreen
                                  : AppColors.techBlue,
                            ),
                    ),
                    if (m != list.last) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
          const SectionHeader('Seus dados'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.table_view_rounded,
                      color: AppColors.techBlue),
                  title: const Text('Exportar transações (CSV)'),
                  subtitle: const Text(
                      'Baixe suas receitas e despesas para Excel/Sheets.'),
                  trailing: const Icon(Icons.download_rounded),
                  onTap: () =>
                      _exportCsv(context, ref, _ExportKind.transactions),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.receipt_long_rounded,
                      color: AppColors.amber),
                  title: const Text('Exportar contas a pagar (CSV)'),
                  subtitle: const Text(
                      'Leve suas contas para onde quiser. Seus dados são seus.'),
                  trailing: const Icon(Icons.download_rounded),
                  onTap: () => _exportCsv(context, ref, _ExportKind.bills),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded, color: AppColors.red),
            label: const Text('Sair da conta',
                style: TextStyle(color: AppColors.red)),
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
          const SizedBox(height: 20),
          // Carimbo de versão: confirma num relance se o app está atualizado
          // (útil quando o navegador segura uma versão antiga em cache).
          Center(
            child: Text('Família ERP · atualizado em 06/07/2026',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).disabledColor)),
          ),
          const SizedBox(height: 32),
        ],
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
        backgroundColor: AppColors.red));
  }
}

/// Amostra clicável de cor de acento: um disco preenchido com anel de seleção.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch(
      {required this.accent, required this.selected, required this.onTap});

  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Acento ${accent.name}',
      child: Tooltip(
        message: accent.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                : null,
          ),
        ),
      ),
    );
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
