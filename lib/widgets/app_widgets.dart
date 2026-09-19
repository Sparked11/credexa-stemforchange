import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'glass_button.dart';

/// Turns any thrown error into a short message that is safe to show users.
String friendlyError(Object? error) {
  final raw = (error ?? '').toString().toLowerCase();
  if (raw.contains('socket') ||
      raw.contains('network') ||
      raw.contains('connection') ||
      raw.contains('failed host lookup')) {
    return 'No internet connection. Check your network and try again.';
  }
  if (raw.contains('timeout') || raw.contains('timed out')) {
    return 'The request took too long. Please try again.';
  }
  if (raw.contains('permission') || raw.contains('denied')) {
    return 'Permission was denied. You can enable it in Settings.';
  }
  return 'The AI service is unavailable right now. Please try again in a moment.';
}

/// Circular tinted icon container used in place of emoji.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(
      {super.key, required this.icon, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: size * 0.52),
      );
}

/// Friendly error state with an optional retry button.
class AppErrorCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  const AppErrorCard({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          IconBadge(icon: icon, color: AppColors.red, size: 52),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: cs.onSurface.withValues(alpha: 0.7))),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            GlassButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onTap: onRetry,
              expand: false,
              height: 46,
              radius: AppRadius.sm,
              haptic: GlassHaptic.light,
            ),
          ],
        ],
      ),
    );
  }
}
