import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../data/models/models.dart';
import '../data/repositories/repositories.dart';
import 'ai/ai_write_tick.dart';

enum AlertSeverity { critico, atencao, info }

class AppAlert {
  const AppAlert({
    required this.severity,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.route,
  });

  final AlertSeverity severity;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? route;

  Color get color => switch (severity) {
        AlertSeverity.critico => AppColors.red,
        AlertSeverity.atencao => AppColors.amber,
        AlertSeverity.info => AppColors.techBlue,
      };
}

/// Agrega lembretes proativos a partir dos dados já existentes: contas
/// vencendo/vencidas, comida perto do vencimento, estoque baixo e risco de
/// estouro de orçamento. (No APK Android, esta mesma lista alimenta as
/// notificações locais.)
final alertsProvider = FutureProvider.autoDispose<List<AppAlert>>((ref) async {
  ref.watch(aiWriteTickProvider); // dados vivos: refaz quando a IA grava
  final bills = await ref.watch(billRepositoryProvider).all();
  final inventory = await ref.watch(inventoryRepositoryProvider).all();

  final alerts = <AppAlert>[];

  // ---- Contas a pagar ----
  for (final b in bills.where((b) => b.status == BillStatus.pending)) {
    final days = b.dueDate.difference(DateTime.now()).inDays;
    if (days < 0) {
      alerts.add(AppAlert(
        severity: AlertSeverity.critico,
        icon: Icons.receipt_long_rounded,
        title: 'Conta vencida: ${b.description}',
        subtitle: 'Venceu há ${-days} dia(s) — ${_brl(b.amount)}',
        route: '/bills',
      ));
    } else if (days <= 3) {
      alerts.add(AppAlert(
        severity: AlertSeverity.atencao,
        icon: Icons.event_rounded,
        title: '${b.description} vence em ${days}d',
        subtitle: '${_brl(b.amount)} — prioridade ${b.priority.labelPt}',
        route: '/bills',
      ));
    }
  }

  // ---- Despensa: validade ----
  for (final i in inventory.where((i) => i.quantity > 0)) {
    final d = i.daysToExpire;
    if (d == null) continue;
    if (d < 0) {
      alerts.add(AppAlert(
        severity: AlertSeverity.critico,
        icon: Icons.no_food_rounded,
        title: '${i.productName} vencido',
        subtitle: 'Passou da validade há ${-d} dia(s)',
        route: '/inventory',
      ));
    } else if (d <= 3) {
      alerts.add(AppAlert(
        severity: AlertSeverity.atencao,
        icon: Icons.schedule_rounded,
        title: '${i.productName} vence em ${d}d',
        subtitle: 'Use logo para não desperdiçar',
        route: '/inventory',
      ));
    }
  }

  // ---- Estoque baixo ----
  for (final i in inventory.where((i) => i.isLowStock && i.quantity > 0)) {
    alerts.add(AppAlert(
      severity: AlertSeverity.info,
      icon: Icons.inventory_2_rounded,
      title: 'Estoque baixo: ${i.productName}',
      subtitle:
          'Restam ${i.quantity.toStringAsFixed(0)} ${i.unit} (mín. ${i.minQuantity.toStringAsFixed(0)})',
      route: '/shopping',
    ));
  }

  // Obs.: o risco de estouro de orçamento fica exclusivamente na seção
  // "Alertas da IA" do dashboard — não é repetido aqui para evitar dado
  // duplicado. Estes lembretes cobrem apenas contas, validade e estoque.

  const order = {
    AlertSeverity.critico: 0,
    AlertSeverity.atencao: 1,
    AlertSeverity.info: 2,
  };
  alerts.sort((a, b) => order[a.severity]!.compareTo(order[b.severity]!));
  return alerts;
});

// ============================================================
// Semáforo "quanto posso gastar"
// ============================================================
enum AllowanceStatus { semDados, verde, amarelo, vermelho }

class SpendingAllowance {
  const SpendingAllowance({
    required this.perDay,
    required this.todaySpent,
    required this.freeThisMonth,
    required this.daysLeft,
    required this.status,
  });

  /// Quanto dá para gastar por dia até o fim do mês, já descontando as contas
  /// a pagar pendentes.
  final double perDay;
  final double todaySpent;
  final double freeThisMonth;
  final int daysLeft;
  final AllowanceStatus status;

  String get message => switch (status) {
        AllowanceStatus.semDados =>
          'Registre o primeiro movimento para eu aprender o ritmo da casa.',
        AllowanceStatus.vermelho => perDay <= 0
            ? 'Sem margem este mês — priorize as contas essenciais.'
            : 'Você já passou do limite de hoje. Segure os gastos.',
        AllowanceStatus.amarelo =>
          'Atenção ao ritmo — está chegando no limite.',
        AllowanceStatus.verde => 'No azul! Dá para gastar com tranquilidade.',
      };
}

final spendingAllowanceProvider =
    FutureProvider.autoDispose<SpendingAllowance>((ref) async {
  ref.watch(aiWriteTickProvider); // dados vivos
  final analytics = ref.watch(analyticsRepositoryProvider);
  final kpis = await analytics.kpis();
  final todaySpent = await analytics.todayExpenses();

  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final daysLeft = daysInMonth - now.day + 1;

  // Dinheiro livre = saldo em contas − contas a pagar pendentes do mês.
  final free = kpis.totalBalance - kpis.billsPending;
  final perDay = free <= 0 ? 0.0 : free / daysLeft;

  // Saldo zero não é automaticamente uma crise: para uma família nova,
  // significa apenas que ainda não há histórico suficiente para orientar.
  final hasActivity = kpis.totalBalance != 0 ||
      kpis.billsPending != 0 ||
      kpis.monthExpenses != 0 ||
      kpis.monthRevenue != 0 ||
      todaySpent != 0;

  final AllowanceStatus status;
  if (!hasActivity) {
    status = AllowanceStatus.semDados;
  } else if (perDay <= 0) {
    status = AllowanceStatus.vermelho;
  } else if (todaySpent <= perDay * 0.7) {
    status = AllowanceStatus.verde;
  } else if (todaySpent <= perDay) {
    status = AllowanceStatus.amarelo;
  } else {
    status = AllowanceStatus.vermelho;
  }

  return SpendingAllowance(
    perDay: perDay,
    todaySpent: todaySpent,
    freeThisMonth: free,
    daysLeft: daysLeft,
    status: status,
  );
});

String _brl(num v) {
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  return 'R\$ $s';
}
