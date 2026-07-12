import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Item da navegação flutuante.
class FloatingNavItem {
  const FloatingNavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Navegação inferior flutuante da identidade "Casa Viva": cápsula arredondada
/// com blur (glass) sobre a aurora, e o item ativo numa **pílula menta**
/// (cor primária) com texto/ícone em contraste. Substitui a NavigationBar
/// padrão no telefone.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<FloatingNavItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor =
        (isDark ? AppColors.darkSurface : AppColors.lightSurface)
            .withValues(alpha: 0.72);
    final muted =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: scheme.outline),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavItem(
                        item: items[i],
                        selected: i == selectedIndex,
                        primary: scheme.primary,
                        onPrimary: scheme.onPrimary,
                        muted: muted,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.primary,
    required this.onPrimary,
    required this.muted,
    required this.onTap,
  });

  final FloatingNavItem item;
  final bool selected;
  final Color primary;
  final Color onPrimary;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? onPrimary : muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? item.selectedIcon : item.icon, size: 22, color: fg),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
