import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/achievement_service.dart';
import '../theme/app_tokens.dart';

/// Shows "badge unlocked" / "level up" toasts above every screen, one at a
/// time, using the root overlay so they appear even over pushed pages.
class AchievementToaster {
  AchievementToaster._();

  static final List<Achievement> _queue = [];
  static bool _showing = false;

  static void enqueue(BuildContext context, Achievement a,
      {required VoidCallback onView}) {
    _queue.add(a);
    if (!_showing) _next(context, onView);
  }

  static void _next(BuildContext context, VoidCallback onView) {
    if (_queue.isEmpty || !context.mounted) {
      _showing = false;
      return;
    }
    _showing = true;
    final a = _queue.removeAt(0);
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AchievementToast(
        achievement: a,
        onView: () {
          entry.remove();
          onView();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (context.mounted) _next(context, onView);
          });
        },
        onDone: () {
          entry.remove();
          Future.delayed(const Duration(milliseconds: 350), () {
            if (context.mounted) _next(context, onView);
          });
        },
      ),
    );
    overlay.insert(entry);
  }
}

class AchievementToast extends StatefulWidget {
  final Achievement achievement;
  final VoidCallback onView;
  final VoidCallback onDone;
  const AchievementToast({
    super.key,
    required this.achievement,
    required this.onView,
    required this.onDone,
  });

  @override
  State<AchievementToast> createState() => AchievementToastState();
}

class AchievementToastState extends State<AchievementToast>
    with TickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);
  Timer? _timer;
  bool _leaving = false;
  double _dragY = 0;

  bool get _isLevel => widget.achievement.kind == AchievementKind.level;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _burst.forward();
    });
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 160),
        HapticFeedback.mediumImpact);
    Future.delayed(const Duration(milliseconds: 320),
        HapticFeedback.lightImpact);
    _timer = Timer(const Duration(seconds: 5), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slide.dispose();
    _burst.dispose();
    _halo.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _slide.animateBack(0,
        duration: const Duration(milliseconds: 280), curve: Curves.easeIn);
    widget.onDone();
  }

  void _open() {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    HapticFeedback.lightImpact();
    widget.onView();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final top = MediaQuery.of(context).padding.top + 8;
    final accent = _isLevel ? AppColors.green : const Color(0xFFFBBF24);

    return Positioned(
      top: top,
      left: 14,
      right: 14,
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, child) {
          final t = Curves.elasticOut.transform(_slide.value.clamp(0.0, 1.0));
          return Opacity(
            opacity: _slide.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - t) * -140 + _dragY),
              child: child,
            ),
          );
        },
        child: GestureDetector(
          onTap: _open,
          onVerticalDragUpdate: (d) =>
              setState(() => _dragY = (_dragY + d.delta.dy).clamp(-120.0, 0.0)),
          onVerticalDragEnd: (d) {
            if (_dragY < -40) {
              _dismiss();
            } else {
              setState(() => _dragY = 0);
            }
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 34,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1E1B4B).withValues(alpha: 0.92),
                          const Color(0xFF0F172A).withValues(alpha: 0.94),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedBuilder(
                                animation: _burst,
                                builder: (_, _) => CustomPaint(
                                  size: const Size(72, 72),
                                  painter: _ConfettiPainter(_burst.value),
                                ),
                              ),
                              AnimatedBuilder(
                                animation: _halo,
                                builder: (_, child) => Container(
                                  width: 62,
                                  height: 62,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: _isLevel
                                          ? const [
                                              Color(0xFF86EFAC),
                                              Color(0xFF16A34A)
                                            ]
                                          : const [
                                              Color(0xFFFDE68A),
                                              Color(0xFFF59E0B)
                                            ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accent.withValues(
                                            alpha: 0.35 + 0.35 * _halo.value),
                                        blurRadius: 14 + 12 * _halo.value,
                                        spreadRadius: 1 + 3 * _halo.value,
                                      ),
                                    ],
                                  ),
                                  child: child,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    alignment: Alignment.center,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0F172A),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(a.emoji,
                                        style: const TextStyle(fontSize: 26)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isLevel ? 'LEVEL UP' : 'BADGE UNLOCKED',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                a.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 12,
                                  height: 1.35,
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 26),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  _ConfettiPainter(this.t);

  static final _rnd = math.Random(11);
  static final _bits = List.generate(
    22,
    (i) => (
      angle: _rnd.nextDouble() * math.pi * 2,
      speed: 34 + _rnd.nextDouble() * 46,
      size: 3 + _rnd.nextDouble() * 4,
      spin: _rnd.nextDouble() * 8,
      color: const [
        Color(0xFFFBBF24),
        Color(0xFF22C55E),
        Color(0xFF38BDF8),
        Color(0xFFF472B6),
        Color(0xFFA78BFA),
      ][i % 5],
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final c = size.center(Offset.zero);
    final paint = Paint();
    for (final b in _bits) {
      final d = Curves.easeOutCubic.transform(t) * b.speed;
      final gravity = 26 * t * t;
      final pos = c + Offset(math.cos(b.angle) * d, math.sin(b.angle) * d + gravity);
      paint.color = b.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(b.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.6),
            const Radius.circular(1)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
