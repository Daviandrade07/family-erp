import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../services/export/csv_export_service.dart';
import '../../services/export/csv_saver.dart';
import '../auth/auth_controller.dart';
import 'security_controller.dart';
import 'simple_mode_controller.dart';
import 'theme_controller.dart';

final familyMembersProvider =
    FutureProvider.autoDispose<List<AppUser>>((ref) async {
  final profile = ref.watch(authControllerProvider).profile;
  if (profile?.familyId == null) return const [];
  return ref
      .watch(authRepositoryProvider)
      .familyMembers(profile!.familyId!);
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
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
                  backgroundColor: AppColors.neonGreen.withOpacity(0.2),
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
          // Proteção principal recomendada: biometria (simples).
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  value: ref.watch(appLockProvider),
                  onChanged: (v) async {
                    if (v && !await ref.read(biometricServiceProvider).isAvailable) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Este aparelho não oferece biometria. O app continuará disponível com senha.'),
                        ));
                      }
                      return;
                    }
                    await ref.read(appLockProvider.notifier).set(v);
                  },
                  activeColor: AppColors.brandPrimary,
                  secondary: const Icon(Icons.fingerprint_rounded,
                      color: AppColors.brandPrimary),
                  title: Row(
                    children: [
                      const Text('Bloquear com biometria'),
                      const SizedBox(width: 8),
                      const StatusBadge('Recomendado',
                          color: AppColors.neonGreen),
                    ],
                  ),
                  subtitle: const Text(
                      'Pede sua digital ou rosto ao abrir o app. '
                      'Proteção simples para o dia a dia.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Extra opcional/avançado: 2FA por app autenticador.
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.security_rounded,
                  color: AppColors.techBlue),
              title: Row(
                children: [
                  const Flexible(
                      child: Text('Autenticação em duas etapas')),
                  const SizedBox(width: 8),
                  StatusBadge(
                    profile?.active2fa == true ? 'Ativa' : 'Avançado',
                    color: profile?.active2fa == true
                        ? AppColors.neonGreen
                        : AppColors.techBlue,
                  ),
                ],
              ),
              subtitle: Text(profile?.active2fa == true
                  ? 'Código do app autenticador ativado'
                  : 'Camada extra com Google Authenticator/Authy '
                      '(opcional, para quem quer o máximo de proteção)'),
              trailing: profile?.active2fa == true
                  ? const Icon(Icons.check_circle,
                      color: AppColors.neonGreen)
                  : const Icon(Icons.chevron_right_rounded),
              onTap: profile?.active2fa == true
                  ? null
                  : () => context.push('/2fa'),
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
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: ref.watch(simpleModeProvider),
              onChanged: (v) =>
                  ref.read(simpleModeProvider.notifier).set(v),
              activeColor: AppColors.neonGreen,
              secondary: const Icon(Icons.accessibility_new_rounded,
                  color: AppColors.techBlue),
              title: const Text('Modo simples'),
              subtitle: const Text(
                  'Tela inicial com botões grandes e voz em primeiro lugar '
                  '— mais fácil de usar.'),
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
                              const SnackBar(
                                  content: Text('Código copiado')));
                        },
                      ),
                    ],
                  ),
                ],
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
                        backgroundColor:
                            AppColors.techBlue.withOpacity(0.2),
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
                  onTap: () => _exportCsv(context, ref, _ExportKind.transactions),
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
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
      const SnackBar(content: Text('Gerando arquivo...')));
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
    messenger.showSnackBar(
        SnackBar(content: Text('Arquivo pronto: $filename')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text('Falha ao exportar: $e'),
        backgroundColor: AppColors.red));
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
