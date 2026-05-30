import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models/analysis_result.dart';
import 'models/debias_result.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

class BiasFingerprint {
  const BiasFingerprint({
    required this.emotionalTone,
    required this.sensationalism,
    required this.citationWeakness,
    required this.logicalLeaps,
    required this.exaggeration,
    required this.politicalLean,
  });

  final double emotionalTone;
  final double sensationalism;
  final double citationWeakness;
  final double logicalLeaps;
  final double exaggeration;
  final double politicalLean;

  List<double> get values => [
        emotionalTone,
        sensationalism,
        citationWeakness,
        logicalLeaps,
        exaggeration,
        politicalLean,
      ];

  double get overall => values.fold(0.0, (a, b) => a + b) / values.length;

  static const axisLabels = [
    'Emotional\nTone',
    'Sensational\nLanguage',
    'Citation\nWeakness',
    'Logical\nLeaps',
    'Exaggeration',
    'Political\nLean',
  ];

  static const shortLabels = [
    'Emotional',
    'Sensational',
    'Citations',
    'Logic',
    'Exaggeration',
    'Political',
  ];

  factory BiasFingerprint.fromDebias(DebiasResult r) {
    final types = <String>{
      ...r.biasTypes.map((t) => t.toLowerCase()),
      ...r.changes.map((c) => c.type.toLowerCase()),
    };
    bool has(List<String> kws) =>
        types.any((t) => kws.any((k) => t.contains(k)));
    final b = r.biasScore.toDouble();
    return BiasFingerprint(
      emotionalTone: _derive(
          b, has(['emotional manipulation', 'fear appeal', 'loaded language']), 40),
      sensationalism:
          _derive(b, has(['sensationalism', 'fear appeal']), 34),
      citationWeakness: _derive(
          b,
          has(['unverified claim', 'missing balance', 'one-sided framing']),
          42),
      logicalLeaps: _derive(
          b, has(['misleading stats', 'scapegoating', 'appeal']), 30),
      exaggeration:
          _derive(b, has(['absolute language', 'sensationalism']), 32),
      politicalLean: _derive(
          b,
          has(['us-vs-them', 'scapegoating', 'vilification', 'one-sided']),
          36),
    );
  }

  factory BiasFingerprint.fromAnalysis(AnalysisResult r) {
    final flagTypes =
        r.synthesis.flags.map((f) => f.type.toLowerCase()).toSet();
    final inv = (100 - r.synthesis.finalScore).toDouble();
    bool has(List<String> kws) =>
        flagTypes.any((t) => kws.any((k) => t.contains(k)));
    return BiasFingerprint(
      emotionalTone: _derive(inv, has(['emotional_language']), 38),
      sensationalism: _derive(inv, has(['sensationalism']), 34),
      citationWeakness: _derive(inv, has(['no_source']), 44),
      logicalLeaps:
          _derive(inv, has(['known_pattern', 'misleading_stats']), 30),
      exaggeration:
          _derive(inv, has(['misleading_stats', 'outdated']), 32),
      politicalLean: _derive(inv, has(['scapegoating']), 26),
    );
  }

  static double _derive(double base, bool matched, double boost) =>
      (base * 0.55 + (matched ? boost : -boost * 0.22)).clamp(5.0, 95.0);
}

Color _biasColor(double overall) {
  if (overall < 28) return const Color(0xFF22C55E);
  if (overall < 50) return const Color(0xFFF59E0B);
  if (overall < 68) return const Color(0xFFEF4444);
  return const Color(0xFFB91C1C);
}

Color _dimColor(double v) {
  if (v < 30) return const Color(0xFF22C55E);
  if (v < 55) return const Color(0xFFF59E0B);
  return const Color(0xFFEF4444);
}

// ─────────────────────────────────────────────────────────────────────────────
//  CARD WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class BiasFingerprintCard extends StatefulWidget {
  const BiasFingerprintCard({super.key, required this.fingerprint});
  final BiasFingerprint fingerprint;

  @override
  State<BiasFingerprintCard> createState() => _BiasFingerprintCardState();
}

class _BiasFingerprintCardState extends State<BiasFingerprintCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fp = widget.fingerprint;
    final overall = fp.overall;
    final accentColor = _biasColor(overall);

    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final t = _progress.value;
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D1B2A), Color(0xFF1B2845)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.28 * t),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──────────────────────────────────────────────
                  Row(
                    children: [
                      const Text('🔏',
                          style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      const Text(
                        'Bias Fingerprint',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      // Animated overall score badge
                      Opacity(
                        opacity: t,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                                color: accentColor.withValues(alpha: 0.6),
                                width: 1.2),
                          ),
                          child: Text(
                            '${overall.round()}% bias',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Visual analysis of 6 bias dimensions',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Radar chart ─────────────────────────────────────────
                  _ChartView(fingerprint: fp, progress: t),
                  const SizedBox(height: 22),

                  // ── Legend chips ────────────────────────────────────────
                  if (t > 0.55)
                    Opacity(
                      opacity: ((t - 0.55) / 0.45).clamp(0.0, 1.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(6, (i) {
                          final v = fp.values[i];
                          final c = _dimColor(v);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                  color: c.withValues(alpha: 0.35), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  BiasFingerprint.shortLabels[i],
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${v.round()}',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: c,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CHART VIEW — places radar painter + axis labels
// ─────────────────────────────────────────────────────────────────────────────

class _ChartView extends StatelessWidget {
  const _ChartView({required this.fingerprint, required this.progress});
  final BiasFingerprint fingerprint;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 278,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cx = constraints.maxWidth / 2;
          const cy = 278 / 2.0;
          final maxR = math.min(cx - 52, cy - 44).clamp(60.0, 130.0);
          final labelR = maxR + 30;
          const n = 6;

          return Stack(
            children: [
              // radar painter fills the whole area
              Positioned.fill(
                child: CustomPaint(
                  painter: _RadarPainter(
                    values: fingerprint.values,
                    progress: progress,
                    cx: cx,
                    cy: cy,
                    maxR: maxR,
                  ),
                ),
              ),

              // axis labels
              ...List.generate(n, (i) {
                final angle = -math.pi / 2 + (2 * math.pi / n) * i;
                final lx = cx + labelR * math.cos(angle);
                final ly = cy + labelR * math.sin(angle);
                final label = BiasFingerprint.axisLabels[i];
                final val = fingerprint.values[i];
                final col = _dimColor(val);

                // anchor alignment: push label away from center
                final ax = math.cos(angle);
                final ay = math.sin(angle);
                final AlignmentGeometry align;
                if (ax.abs() < 0.3) {
                  align = ay < 0
                      ? Alignment.bottomCenter
                      : Alignment.topCenter;
                } else {
                  align = ax < 0
                      ? Alignment.centerRight
                      : Alignment.centerLeft;
                }

                return Positioned(
                  left: lx - 44,
                  top: ly - 22,
                  width: 88,
                  height: 44,
                  child: Opacity(
                    opacity: progress,
                    child: Align(
                      alignment: align,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Color(0xAAFFFFFF),
                              height: 1.25,
                            ),
                          ),
                          Text(
                            '${val.round()}',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: col,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CUSTOM PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.values,
    required this.progress,
    required this.cx,
    required this.cy,
    required this.maxR,
  });

  final List<double> values;
  final double progress;
  final double cx, cy, maxR;

  static const _n = 6;

  Offset _pt(int i, double r) {
    final angle = -math.pi / 2 + (2 * math.pi / _n) * i;
    return Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
  }

  Path _hexPath(double r) {
    final path = Path();
    for (var i = 0; i < _n; i++) {
      final pt = _pt(i, r);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  Path _dataPath() {
    final path = Path();
    for (var i = 0; i < _n; i++) {
      final r = (values[i] / 100.0) * maxR * progress;
      final pt = _pt(i, r);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  // Interpolate between the bias gradient colors
  Color get _dataColor {
    final avg = values.fold(0.0, (a, b) => a + b) / values.length;
    if (avg < 28) return const Color(0xFF22C55E);
    if (avg < 50) return const Color(0xFFF59E0B);
    if (avg < 68) return const Color(0xFFEF4444);
    return const Color(0xFFB91C1C);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ── Grid rings ──────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    for (final frac in [0.33, 0.66, 1.0]) {
      canvas.drawPath(_hexPath(maxR * frac), gridPaint);
    }

    // ── Radial axes ─────────────────────────────────────────────────────────
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    for (var i = 0; i < _n; i++) {
      final outer = _pt(i, maxR);
      canvas.drawLine(Offset(cx, cy), outer, axisPaint);
    }

    if (progress < 0.01) return;

    final dataPath = _dataPath();
    final color = _dataColor;

    // ── Outer glow ──────────────────────────────────────────────────────────
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.45 * progress)
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawPath(dataPath, glowPaint);

    // ── Fill ────────────────────────────────────────────────────────────────
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.18 * progress);
    canvas.drawPath(dataPath, fillPaint);

    // ── Stroke ──────────────────────────────────────────────────────────────
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.92 * progress)
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(dataPath, strokePaint);

    // ── Vertex dots ─────────────────────────────────────────────────────────
    for (var i = 0; i < _n; i++) {
      final r = (values[i] / 100.0) * maxR * progress;
      final pt = _pt(i, r);

      // glow halo
      canvas.drawCircle(
        pt,
        7,
        Paint()
          ..color = color.withValues(alpha: 0.3 * progress)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // white ring
      canvas.drawCircle(
        pt,
        4,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9 * progress)
          ..style = PaintingStyle.fill,
      );
      // brand color core
      canvas.drawCircle(
        pt,
        2.5,
        Paint()
          ..color = color.withValues(alpha: progress)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.progress != progress || old.values != values;
}
