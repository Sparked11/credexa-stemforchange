import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'adaptive_chrome.dart';
import 'hero_3d_stage.dart';

class JourneyStep {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;

  const JourneyStep({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
  });
}

/// A vertical timeline whose rail lights up and whose cards unfold in 3D as
/// the user scrolls down the page.
class ScrollJourney extends StatelessWidget {
  final List<JourneyStep> steps;
  const ScrollJourney({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScrollReveal(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HOW CREDEXA WORKS',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: AppColors.greenDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'From scrolling to sharp thinking',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Follow the path: spot it, check it, reframe it, and build the habit.',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 13,
                    height: 1.5,
                    color: cs.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
          for (var i = 0; i < steps.length; i++)
            _JourneyRow(
              index: i,
              step: steps[i],
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _JourneyRow extends StatefulWidget {
  final int index;
  final JourneyStep step;
  final bool isLast;
  const _JourneyRow(
      {required this.index, required this.step, required this.isLast});

  @override
  State<_JourneyRow> createState() => _JourneyRowState();
}

class _JourneyRowState extends State<_JourneyRow> {
  final ScrollTopTracker _tracker = ScrollTopTracker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  double _progress(BuildContext context, ChromeController chrome) {
    final y = _tracker.topY(context, chrome);
    if (y == null) return 0;
    final vh = MediaQuery.sizeOf(context).height;
    return ((vh - 110 - y) / (vh * 0.3)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.maybeOf(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final step = widget.step;

    Widget buildRow(double p) {
      final lit = p > 0.55;
      return Stack(
        children: [
          if (!widget.isLast)
            Positioned(
              left: 14.5,
              top: 38,
              bottom: 0,
              child: Container(
                        width: 3,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: FractionallySizedBox(
                            heightFactor: Curves.easeOut.transform(p),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    step.color,
                                    step.color.withValues(alpha: 0.25),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: step.color.withValues(alpha: 0.45),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Align(
                  alignment: Alignment.topLeft,
                  child:
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: lit
                          ? LinearGradient(colors: [
                              step.color,
                              step.color.withValues(alpha: 0.7),
                            ])
                          : null,
                      color: lit ? null : cs.onSurface.withValues(alpha: 0.1),
                      boxShadow: lit
                          ? [
                              BoxShadow(
                                color: step.color.withValues(alpha: 0.55),
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '${widget.index + 1}',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: lit
                              ? Colors.white
                              : cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 18),
                child: Opacity(
                  opacity: Curves.easeOut.transform(p),
                  child: Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..translateByDouble(28 * (1 - p), 0.0, 0.0, 1.0)
                      ..rotateY(-0.5 * (1 - p)),
                    child: TiltCard(
                      onTap: step.onTap,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [const Color(0xFF273449), AppColors.slate800]
                                : [Colors.white, const Color(0xFFF1F5F9)],
                          ),
                          border: Border.all(
                            color: Colors.white
                                .withValues(alpha: isDark ? 0.08 : 0.9),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: step.color
                                  .withValues(alpha: isDark ? 0.2 : 0.16),
                              blurRadius: 26,
                              offset: const Offset(0, 12),
                            ),
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.35 : 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    step.color.withValues(alpha: 0.95),
                                    step.color.withValues(alpha: 0.6),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: step.color.withValues(alpha: 0.45),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child:
                                  Icon(step.icon, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.title,
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    step.body,
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 12,
                                      height: 1.5,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.75),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        step.cta,
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? step.color
                                              : Color.lerp(step.color,
                                                  Colors.black, 0.2),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.arrow_forward_rounded,
                                          size: 14, color: step.color),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
        ],
      );
    }

    if (chrome == null) return buildRow(1);
    return ListenableBuilder(
      listenable: chrome,
      builder: (context, _) => buildRow(_progress(context, chrome)),
    );
  }
}
