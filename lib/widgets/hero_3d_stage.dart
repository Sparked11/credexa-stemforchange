import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import 'adaptive_chrome.dart';
import 'glass_button.dart';

/// Cinematic 3D landing hero: a swipe-to-spin ring of misleading posts,
/// lit by spotlights and standing on a glowing stage.
class Hero3DStage extends StatefulWidget {
  final VoidCallback onCheckClaim;
  final VoidCallback onOpenTrustLens;

  /// Extra space at the top so content clears a bar that floats over the hero.
  final double topInset;

  const Hero3DStage({
    super.key,
    required this.onCheckClaim,
    required this.onOpenTrustLens,
    this.topInset = 0,
  });

  @override
  State<Hero3DStage> createState() => _Hero3DStageState();
}

class _Hero3DStageState extends State<Hero3DStage>
    with TickerProviderStateMixin {
  // ── Ring geometry ──────────────────────────────────────────────────────────
  static const int _count = 8;
  static const double _cardW = 172;
  static const double _cardH = _cardW * 9 / 16;
  static const double _radius = 250;
  static const double _perspective = 0.0014;
  static const double _tilt = 0.2;
  static const double _ringAreaH = 268;
  static const double _step = 2 * math.pi / _count;

  // Display order and platform badges (kept from the original slideshow).
  static const _postOrder = [0, 3, 1, 4, 2, 5, 7, 6];
  static const _platforms = [
    'assets/YouTubeicon.png',
    'assets/Instagramicon.png',
    'assets/Xicon.png',
    'assets/Facebookicon.png',
    'assets/TikTokicon.png',
    'assets/YouTubeicon.png',
    'assets/Xicon.png',
    'assets/TikTokicon.png',
  ];

  // ── Motion state ───────────────────────────────────────────────────────────
  static const double _cruise = 0.42; // rad/s idle spin
  double _angle = 0;
  double _speed = _cruise;
  double _dir = 1;
  bool _touching = false;
  bool _interacted = false;
  int _lastHapticSlot = 0;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final AnimationController _beam;
  late final AnimationController _hint;

  final List<ui.Image?> _images = List<ui.Image?>.filled(_count, null);
  late final List<_Mote> _motes;

  ChromeController? _chrome;
  double _lastScroll = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ChromeScope.maybeOf(context);
    if (next != _chrome) {
      _chrome?.removeListener(_onScrollChrome);
      _chrome = next;
      _lastScroll = next?.offset ?? 0;
      next?.addListener(_onScrollChrome);
    }
  }

  // Scrolling the page also spins the ring.
  void _onScrollChrome() {
    final off = _chrome?.offset ?? 0;
    final delta = off - _lastScroll;
    _lastScroll = off;
    if (delta != 0 && !_touching) _angle += delta * 0.006;
  }

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    _motes = List.generate(
      30,
      (_) => _Mote(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        r: 0.8 + rnd.nextDouble() * 1.8,
        speed: 0.01 + rnd.nextDouble() * 0.03,
        phase: rnd.nextDouble() * math.pi * 2,
      ),
    );
    _beam = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
    _hint = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _ticker = createTicker(_onTick)..start();
    _loadImages();
  }

  @override
  void dispose() {
    _chrome?.removeListener(_onScrollChrome);
    _ticker.dispose();
    _beam.dispose();
    _hint.dispose();
    _frame.dispose();
    for (final img in _images) {
      img?.dispose();
    }
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (!_touching) {
      final target = _dir * _cruise;
      _speed += (target - _speed) * (1 - math.exp(-dt / 1.8));
      _angle += _speed * dt;
    } else {
      _speed *= math.exp(-dt * 8);
    }
    _frame.value++;
  }

  /// Decodes each post small and bakes a soft blur in once, so the ring is
  /// cheap to animate and the post text stays unreadable.
  Future<void> _loadImages() async {
    for (var i = 0; i < _count; i++) {
      try {
        final data = await rootBundle.load('assets/post${_postOrder[i] + 1}.png');
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: 560,
        );
        final frame = await codec.getNextFrame();
        final src = frame.image;
        final rec = ui.PictureRecorder();
        Canvas(rec).drawImage(
          src,
          Offset.zero,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: 1.6, sigmaY: 1.6, tileMode: TileMode.clamp),
        );
        final blurred =
            await rec.endRecording().toImage(src.width, src.height);
        src.dispose();
        if (!mounted) {
          blurred.dispose();
          return;
        }
        setState(() => _images[i] = blurred);
      } catch (_) {
        // Leave the placeholder card if an asset fails to decode.
      }
    }
  }

  // ── Gestures ───────────────────────────────────────────────────────────────
  void _onDown() => _touching = true;

  void _onUpdate(DragUpdateDetails d) {
    _touching = true;
    if (!_interacted) setState(() => _interacted = true);
    _angle += d.delta.dx / _radius;
    final slot = (_angle / _step).floor();
    if (slot != _lastHapticSlot) {
      _lastHapticSlot = slot;
      HapticFeedback.selectionClick();
    }
  }

  void _onEnd(DragEndDetails d) {
    final v = (d.velocity.pixelsPerSecond.dx / _radius).clamp(-14.0, 14.0);
    _touching = false;
    if (v.abs() > 0.2) {
      _speed = v;
      _dir = v.sign;
      HapticFeedback.lightImpact();
    }
  }

  void _onRelease() => _touching = false;

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF03050B), Color(0xFF0A1120), Color(0xFF0B2230)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: FadeTransition(
                  opacity: Tween<double>(begin: 0.75, end: 1.0).animate(
                      CurvedAnimation(parent: _beam, curve: Curves.easeInOut)),
                  child: const CustomPaint(painter: _SpotlightPainter()),
                ),
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (_, _, _) => CustomPaint(
                  painter: _MotePainter(_motes, _last.inMilliseconds / 1000),
                ),
              ),
            ),
            _parallax(
              Column(
                children: [
                  SizedBox(height: 26 + widget.topInset),
                  _buildTitle(),
                  const SizedBox(height: 10),
                  _buildRing(),
                  _buildDots(),
                  const SizedBox(height: 14),
                  _buildHint(),
                  const SizedBox(height: 14),
                  _buildCtas(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Content drifts down and fades slightly as the hero scrolls away.
  Widget _parallax(Widget child) {
    final chrome = _chrome;
    if (chrome == null) return child;
    return ListenableBuilder(
      listenable: chrome,
      builder: (context, c) {
        final off = chrome.offset.clamp(0.0, 900.0);
        return Opacity(
          opacity: (1 - off / 760).clamp(0.35, 1.0),
          child: Transform.translate(offset: Offset(0, off * 0.22), child: c),
        );
      },
      child: child,
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border:
                  Border.all(color: AppColors.green.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'CREDEXA · MEDIA LITERACY',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Color(0xFF4ADE80),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Fight Misinformation.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 29,
              fontWeight: FontWeight.w900,
              height: 1.15,
              color: Colors.white,
              shadows: [
                Shadow(
                    color: Color(0x99000000),
                    blurRadius: 18,
                    offset: Offset(0, 6)),
              ],
            ),
          ),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              colors: [Color(0xFF4ADE80), Color(0xFF38BDF8)],
            ).createShader(r),
            child: const Text(
              'Think Critically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 29,
                fontWeight: FontWeight.w900,
                height: 1.15,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Every post on this ring is misleading. Spin it and see if you can spot why.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRing() {
    return SizedBox(
      height: _ringAreaH,
      width: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (_) => _onDown(),
        onPanCancel: _onRelease,
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        onTapUp: (_) => _onRelease(),
        onTapCancel: _onRelease,
        child: ValueListenableBuilder<int>(
          valueListenable: _frame,
          builder: (context, _, _) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _StagePainter(
                      angle: _angle,
                      radius: _radius,
                      cardCenterY: _cardCenterY,
                      count: _count,
                    ),
                  ),
                ),
                ..._buildCards(),
              ],
            );
          },
        ),
      ),
    );
  }

  static const double _cardCenterY = 128;

  List<Widget> _buildCards() {
    final poses = List.generate(_count, (i) {
      final theta = _angle + i * _step;
      return (i: i, theta: theta, depth: math.cos(theta));
    })
      ..sort((a, b) => a.depth.compareTo(b.depth));

    return [
      for (final p in poses)
        Positioned(
          left: 0,
          right: 0,
          top: _cardCenterY - _cardH / 2,
          child: Center(
            child: Transform(
              alignment: Alignment.center,
              transform: _cardMatrix(p.theta, p.depth < 0),
              child: _PostCard(
                image: _images[p.i],
                platform: _platforms[p.i],
                width: _cardW,
                height: _cardH,
                depth: p.depth,
              ),
            ),
          ),
        ),
    ];
  }

  Matrix4 _cardMatrix(double theta, bool backFacing) {
    final m = Matrix4.identity()
      ..setEntry(3, 2, _perspective)
      ..translateByDouble(0.0, 0.0, _radius, 1.0)
      ..rotateX(_tilt)
      ..rotateY(theta)
      ..translateByDouble(0.0, 0.0, -_radius, 1.0);
    if (backFacing) m.scaleByDouble(-1.0, 1.0, 1.0, 1.0);
    return m;
  }

  Widget _buildDots() {
    return ValueListenableBuilder<int>(
      valueListenable: _frame,
      builder: (_, _, _) {
        var front = (-_angle / _step).round() % _count;
        if (front < 0) front += _count;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_count, (i) {
            final active = i == front;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.green
                    : Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(3),
                boxShadow: active
                    ? [
                        BoxShadow(
                            color: AppColors.green.withValues(alpha: 0.7),
                            blurRadius: 8)
                      ]
                    : null,
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildHint() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: _interacted ? 0.0 : 1.0,
      child: AnimatedBuilder(
        animation: _hint,
        builder: (_, _) {
          final t = _hint.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.translate(
                offset: Offset(-6 * t, 0),
                child: Icon(Icons.chevron_left_rounded,
                    color: Colors.white.withValues(alpha: 0.5 + 0.4 * t),
                    size: 22),
              ),
              const SizedBox(width: 6),
              Icon(Icons.swipe_rounded,
                  color: Colors.white.withValues(alpha: 0.85), size: 20),
              const SizedBox(width: 8),
              Text(
                'Swipe to spin',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 6),
              Transform.translate(
                offset: Offset(6 * t, 0),
                child: Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.5 + 0.4 * t),
                    size: 22),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCtas() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: GlassButton(
              label: 'Check a claim',
              icon: Icons.fact_check_rounded,
              onTap: widget.onCheckClaim,
              onDark: true,
              haptic: GlassHaptic.medium,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GlassButton(
              label: 'Trust Lens',
              icon: Icons.videocam_rounded,
              onTap: widget.onOpenTrustLens,
              filled: false,
              accent: const Color(0xFF38BDF8),
              onDark: true,
              haptic: GlassHaptic.light,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CARD
// ─────────────────────────────────────────────────────────────────────────────
class _PostCard extends StatelessWidget {
  final ui.Image? image;
  final String platform;
  final double width;
  final double height;
  final double depth; // cos(theta): 1 = front, -1 = back

  const _PostCard({
    required this.image,
    required this.platform,
    required this.width,
    required this.height,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    final front = ((depth + 1) / 2).clamp(0.0, 1.0);
    final dim = (1 - front) * 0.42;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35 + 0.25 * front),
            blurRadius: 14 + 22 * front,
            offset: Offset(0, 8 + 10 * front),
          ),
          if (front > 0.85)
            BoxShadow(
              color: AppColors.green.withValues(alpha: 0.28 * (front - 0.85) / 0.15),
              blurRadius: 26,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              RawImage(image: image, fit: BoxFit.cover)
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF334155)],
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.5, 1.0],
                  colors: [Color(0x00000000), Color(0xB3000000)],
                ),
              ),
            ),
            // Glossy sheen
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.0, 0.45],
                  colors: [
                    Colors.white.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.asset(platform, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xE6EF4444),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 12),
                    SizedBox(width: 3),
                    Text(
                      'FLAGGED',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10 + 0.22 * front),
                    width: 1.2),
              ),
            ),
            if (dim > 0.01)
              ColoredBox(color: Colors.black.withValues(alpha: dim)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PAINTERS
// ─────────────────────────────────────────────────────────────────────────────

/// Static volumetric spotlight beams falling from the top of the stage.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final floorY = size.height * 0.72;

    void beam(double topX, double topHalf, double botX, double botHalf,
        Color color, double blur) {
      final path = Path()
        ..moveTo(topX - topHalf, 0)
        ..lineTo(topX + topHalf, 0)
        ..lineTo(botX + botHalf, floorY)
        ..lineTo(botX - botHalf, floorY)
        ..close();
      final rect = Rect.fromLTWH(0, 0, size.width, floorY);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0.0)],
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawPath(path, paint);
    }

    // Centre key light
    beam(cx, 16, cx, size.width * 0.42, Colors.white.withValues(alpha: 0.20), 26);
    // Side accent lights
    beam(size.width * 0.06, 10, cx - size.width * 0.18, size.width * 0.26,
        const Color(0xFF22C55E).withValues(alpha: 0.22), 28);
    beam(size.width * 0.94, 10, cx + size.width * 0.18, size.width * 0.26,
        const Color(0xFF38BDF8).withValues(alpha: 0.20), 28);

    // Warm pool of light behind the ring
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF22C55E).withValues(alpha: 0.22),
          const Color(0xFF22C55E).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(cx, size.height * 0.5), radius: size.width * 0.7));
    canvas.drawCircle(Offset(cx, size.height * 0.5), size.width * 0.7, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Mote {
  final double x, y, r, speed, phase;
  const _Mote({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.phase,
  });
}

/// Slow drifting dust motes caught in the light.
class _MotePainter extends CustomPainter {
  final List<_Mote> motes;
  final double t;
  _MotePainter(this.motes, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final m in motes) {
      final y = ((m.y - t * m.speed) % 1.0);
      final x = m.x + math.sin(t * 0.6 + m.phase) * 0.02;
      final twinkle = 0.35 + 0.45 * (0.5 + 0.5 * math.sin(t * 1.4 + m.phase));
      paint.color = Colors.white.withValues(alpha: 0.35 * twinkle);
      canvas.drawCircle(Offset(x * size.width, y * size.height), m.r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MotePainter old) => old.t != t;
}

/// Glowing stage floor with a rotating rim and per-card contact shadows.
class _StagePainter extends CustomPainter {
  final double angle;
  final double radius;
  final double cardCenterY;
  final int count;

  _StagePainter({
    required this.angle,
    required this.radius,
    required this.cardCenterY,
    required this.count,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final floorY = cardCenterY + 92;
    final rx = radius * 0.98;
    final ry = rx * 0.15;
    final center = Offset(cx, floorY);
    final oval = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);

    // Glow disc
    canvas.drawOval(
      oval.inflate(26),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF22C55E).withValues(alpha: 0.38),
            const Color(0xFF0EA5E9).withValues(alpha: 0.14),
            const Color(0xFF0EA5E9).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(oval.inflate(26)),
    );

    // Rim rings
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.16);
    canvas.drawOval(oval, rim);
    canvas.drawOval(
        Rect.fromCenter(center: center, width: rx * 1.45, height: ry * 1.45),
        rim..color = Colors.white.withValues(alpha: 0.08));

    // Rotating rim beads
    final bead = Paint();
    const beads = 56;
    for (var k = 0; k < beads; k++) {
      final a = -angle * 0.6 + k * 2 * math.pi / beads;
      final near = 0.5 + 0.5 * math.sin(a);
      bead.color = const Color(0xFF4ADE80).withValues(alpha: 0.15 + 0.6 * near);
      canvas.drawCircle(
        Offset(cx + rx * math.cos(a), floorY + ry * math.sin(a)),
        0.9 + 1.3 * near,
        bead,
      );
    }

    // Contact shadows under each card
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    for (var i = 0; i < count; i++) {
      final theta = angle + i * 2 * math.pi / count;
      final c = math.cos(theta);
      final s = math.sin(theta);
      final scale = 1 / (1 + 0.0014 * radius * (1 - c));
      final p = Offset(cx + radius * s * scale, floorY + ry * 0.95 * c);
      canvas.drawOval(
        Rect.fromCenter(
            center: p, width: 120 * scale * (0.5 + 0.5 * c.abs()), height: 16 * scale),
        shadow,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => old.angle != angle;
}

/// Card that tilts in 3D toward the finger and sinks slightly when pressed.
class TiltCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const TiltCard({super.key, required this.child, required this.onTap});

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> {
  Offset _tilt = Offset.zero; // x: rotateY factor, y: rotateX factor (-1..1)
  bool _down = false;

  void _update(Offset local, Size size) {
    if (size.isEmpty) return;
    final nx = ((local.dx / size.width) - 0.5) * 2;
    final ny = ((local.dy / size.height) - 0.5) * 2;
    setState(() {
      _down = true;
      _tilt = Offset(nx.clamp(-1.0, 1.0), ny.clamp(-1.0, 1.0));
    });
  }

  void _reset() => setState(() {
        _down = false;
        _tilt = Offset.zero;
      });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return Listener(
        onPointerDown: (e) => _update(e.localPosition, size),
        onPointerMove: (e) => _update(e.localPosition, size),
        onPointerUp: (_) => _reset(),
        onPointerCancel: (_) => _reset(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          child: TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(end: _tilt),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            builder: (context, t, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(-t.dy * 0.2)
                ..rotateY(t.dx * 0.2)
                ..scaleByDouble(
                    _down ? 0.965 : 1.0, _down ? 0.965 : 1.0, 1.0, 1.0),
              child: child,
            ),
            child: widget.child,
          ),
        ),
      );
    });
  }
}
