import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';

enum GlassHaptic { light, medium, selection, none }

/// Frosted-glass button: blurred translucent body, luminous edge, top sheen
/// and a soft coloured glow. [filled] tints the glass with [accent] (primary
/// actions); otherwise it is neutral glass (secondary actions).
class GlassButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final Widget? child;
  final VoidCallback? onTap;
  final Color accent;
  final bool filled;
  final double height;
  final double radius;
  final bool expand;
  final bool loading;
  final Color? foreground;
  final double fontSize;
  final GlassHaptic haptic;
  final EdgeInsetsGeometry padding;

  /// Force dark-glass styling on screens that are always dark (auth, hero).
  final bool? onDark;

  const GlassButton({
    super.key,
    this.label,
    this.icon,
    this.child,
    required this.onTap,
    this.accent = AppColors.green,
    this.filled = true,
    this.height = 54,
    this.radius = 16,
    this.expand = true,
    this.loading = false,
    this.foreground,
    this.fontSize = 14,
    this.haptic = GlassHaptic.medium,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.onDark,
  }) : assert(label != null || child != null || icon != null);

  void _fire() {
    switch (haptic) {
      case GlassHaptic.light:
        HapticFeedback.lightImpact();
      case GlassHaptic.medium:
        HapticFeedback.mediumImpact();
      case GlassHaptic.selection:
        HapticFeedback.selectionClick();
      case GlassHaptic.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = onDark ?? (Theme.of(context).brightness == Brightness.dark);
    final enabled = onTap != null && !loading;
    final fg = foreground ??
        (filled
            ? Colors.white
            : (isDark ? Colors.white : AppColors.slate800));
    final r = BorderRadius.circular(radius);

    final tint = filled
        ? [accent.withValues(alpha: 0.82), accent.withValues(alpha: 0.52)]
        : [
            (isDark ? Colors.white : Colors.white)
                .withValues(alpha: isDark ? 0.16 : 0.72),
            (isDark ? Colors.white : Colors.white)
                .withValues(alpha: isDark ? 0.06 : 0.38),
          ];

    final content = child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
              )
            else if (icon != null)
              Icon(icon, color: filled ? fg : accent, size: 20),
            if ((icon != null || loading) && label != null)
              const SizedBox(width: 9),
            if (label != null)
              // Shrinks instead of truncating so the label is always readable.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label!,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      color: fg,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
          ],
        );

    Widget button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: (filled ? accent : Colors.black)
                .withValues(alpha: filled ? 0.38 : (isDark ? 0.35 : 0.10)),
            blurRadius: filled ? 24 : 16,
            offset: Offset(0, filled ? 9 : 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              height: height,
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: tint,
                ),
                border: Border.all(
                  color: Colors.white.withValues(
                      alpha: filled ? 0.5 : (isDark ? 0.24 : 0.9)),
                  width: 1.2,
                ),
              ),
              child: InkWell(
                borderRadius: r,
                splashColor: Colors.white.withValues(alpha: 0.25),
                highlightColor: Colors.white.withValues(alpha: 0.1),
                onTap: enabled
                    ? () {
                        _fire();
                        onTap!();
                      }
                    : null,
                child: Stack(
                  children: [
                    // Glossy top sheen
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: height * 0.5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white
                                  .withValues(alpha: filled ? 0.30 : 0.35),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: padding,
                      child: Center(child: content),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!expand) button = IntrinsicWidth(child: button);
    return Opacity(opacity: onTap == null ? 0.55 : 1, child: button);
  }
}
