import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.neonGreen.withValues(alpha: 0.25),
                    AppColors.techBlue.withValues(alpha: 0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: const Icon(Icons.home_work_rounded,
                  size: 56, color: AppColors.neonGreen),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.06, 1.06),
                    duration: 900.ms,
                    curve: Curves.easeInOut),
            const SizedBox(height: 24),
            Text(
              'Família ERP',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.darkTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ).animate().fadeIn(duration: 600.ms),
            const SizedBox(height: 8),
            Text(
              'Gestão doméstica inteligente',
              style: TextStyle(color: AppColors.darkTextSecondary),
            ).animate().fadeIn(delay: 200.ms, duration: 600.ms),
            const SizedBox(height: 40),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.neonGreen),
            ),
          ],
        ),
      ),
    );
  }
}
