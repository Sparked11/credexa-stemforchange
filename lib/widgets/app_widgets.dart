import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme/app_tokens.dart';
import 'glass_button.dart';

/// Shown whenever the device has no internet connection.
const String kOfflineMessage =
    'No internet connection. Check your network and try again.';

/// Turns any thrown error into a short message that is safe to show users.
String friendlyError(Object? error) {
  final raw = (error ?? '').toString().toLowerCase();
  if (isOfflineError(error) ||
      raw.contains('socket') ||
      raw.contains('network') ||
      raw.contains('connection') ||
      raw.contains('failed host lookup')) {
    return kOfflineMessage;
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

/// Friendly error state with an optional retry button. Offline errors get a
/// dedicated "You're offline" look automatically.
class AppErrorCard extends StatelessWidget {
  final String? title;
  final String message;
  final VoidCallback? onRetry;
  final IconData? icon;
  const AppErrorCard({
    super.key,
    this.title,
    required this.message,
    this.onRetry,
    this.icon,
  });

  bool get _offline => message.toLowerCase().contains('no internet');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final offline = _offline;
    final color = offline ? AppColors.amber : AppColors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          IconBadge(
            icon: icon ??
                (offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded),
            color: color,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(title ?? (offline ? "You're offline" : 'Something went wrong'),
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

/// Friendly "nothing here yet" state: icon, title, message and optional action.
class EmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color color;
  final bool compact;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.color = AppColors.indigo,
    this.compact = false,
  });

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = widget.compact ? 64.0 : 84.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 32, vertical: widget.compact ? 20 : 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _float,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -6 * Curves.easeInOut.transform(_float.value)),
                child: child,
              ),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color.withValues(alpha: 0.22),
                      widget.color.withValues(alpha: 0.08),
                    ],
                  ),
                  border: Border.all(
                      color: widget.color.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(widget.icon,
                    size: size * 0.46, color: widget.color),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 13,
                height: 1.5,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (widget.actionLabel != null && widget.onAction != null) ...[
              const SizedBox(height: 18),
              GlassButton(
                label: widget.actionLabel,
                onTap: widget.onAction,
                accent: widget.color,
                expand: false,
                height: 46,
                radius: AppRadius.sm,
                haptic: GlassHaptic.light,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
