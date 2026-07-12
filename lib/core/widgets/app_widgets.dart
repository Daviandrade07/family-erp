import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// Rounded, bordered surface used across every screen.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;

  /// Tint sólido opcional — o tratamento de "herói" do Design System
  /// (gradientes decorativos são banidos; um card especial por tela).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color:
            gradient == null ? (color ?? scheme.surfaceContainerHighest) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        // Profundidade suave em vez de borda dura de 1px (o que dava o ar de
        // "dashboard gerado"). No claro, uma sombra leve dá sensação premium;
        // no escuro, uma borda hairline sutil (sombras não aparecem no escuro).
        border: isDark
            ? Border.all(color: scheme.outline.withValues(alpha: 0.6))
            : null,
        boxShadow: isDark
            ? [
                // No escuro a sombra clara não aparece — uma sombra escura
                // sutil dá o mesmo relevo/profundidade.
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF17171C).withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: const Color(0xFF17171C).withValues(alpha: 0.03),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: child,
    );
    // ListTile/SwitchListTile precisam de um ancestral Material para renderizar
    // corretamente fundo, estados de toque e acessibilidade. Mantemos a
    // superfície transparente para não alterar a aparência dos cartões.
    if (onTap == null) {
      return Material(color: Colors.transparent, child: body);
    }
    // Toque com feedback tátil: o card "afunda" levemente ao pressionar
    // (microinteração premium). O InkWell mantém o ripple e a acessibilidade;
    // o Listener só dirige a escala (não consome o gesto). Respeita a redução
    // de movimento do sistema.
    return _PressableCard(onTap: onTap!, child: body);
  }
}

class _PressableCard extends StatefulWidget {
  const _PressableCard({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  double _scale = 1;

  void _set(double v) {
    if (_scale != v) setState(() => _scale = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Listener(
      onPointerDown: reduce ? null : (_) => _set(0.97),
      onPointerUp: reduce ? null : (_) => _set(1),
      onPointerCancel: reduce ? null : (_) => _set(1),
      child: AnimatedScale(
        scale: reduce ? 1 : _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Executive KPI card for the dashboard.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = AppColors.neonGreen,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color accent;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: text.bodySmall?.color?.withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: text.labelSmall?.copyWith(color: accent)),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .moveY(begin: 12, curve: Curves.easeOutCubic);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!,
                  style: const TextStyle(color: AppColors.techBlue)),
            ),
        ],
      ),
    );
  }
}

/// Budget / goal progress with color escalation and optional AI prediction.
class DynamicProgressBar extends StatelessWidget {
  const DynamicProgressBar({
    super.key,
    required this.ratio,
    this.predictedRatio,
    this.height = 10,
  });

  /// 0..1+ actual usage. Values above 1 render fully red.
  final double ratio;

  /// Optional AI-predicted end-of-period ratio, drawn as a ghost bar.
  final double? predictedRatio;
  final double height;

  Color get _color => ratio >= 1
      ? AppColors.red
      : ratio >= 0.8
          ? AppColors.amber
          : AppColors.neonGreen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: scheme.outline.withValues(alpha: 0.5)),
            if (predictedRatio != null)
              FractionallySizedBox(
                widthFactor: predictedRatio!.clamp(0, 1),
                child: Container(color: _color.withValues(alpha: 0.25)),
              ),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              widthFactor: ratio.clamp(0, 1),
              child: Container(color: _color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small colored status pill (expiration badges, bill status, roles...).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Neutro (não verde): estados vazios/erro são calmos, não "sucesso".
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  style: text.bodySmall, textAlign: TextAlign.center),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        )
            // Respiro: o estado vazio surge com calma.
            .animate()
            .fadeIn(duration: 300.ms)
            .moveY(begin: 8, curve: Curves.easeOutCubic),
      ),
    );
  }
}

/// Shimmer skeleton while data loads.
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key, this.itemCount = 4, this.itemHeight = 84});

  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? AppColors.darkCard : Colors.grey.shade300,
      highlightColor: isDark ? AppColors.darkBorder : Colors.grey.shade100,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          height: itemHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

/// Error panel with retry.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_off_rounded,
      title: 'Algo deu errado',
      subtitle: message,
      actionLabel: 'Tentar novamente',
      onAction: onRetry,
    );
  }
}
