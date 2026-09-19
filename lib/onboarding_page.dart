import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/glass_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ONBOARDING PAGE
// ─────────────────────────────────────────────────────────────────────────────
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;

  // Per-slide entrance animation controllers.
  late final List<AnimationController> _entranceCtrl;

  static const _slides = [
    _Slide(
      eyebrow: 'THE PROBLEM',
      title: 'Misinformation\nIs Everywhere',
      body: 'Many people have shared false content without realising it. '
          'On social media there is little editorial filter — and misinformation spreads fast.',
      accent: Color(0xFF22C55E),
      bgTop: Color(0xFF0A1628),
      bgBottom: Color(0xFF0D2137),
      statValue: 'Many',
      statLabel: 'people share false content without realising it',
    ),
    _Slide(
      eyebrow: 'THE SOLUTION',
      title: 'Think Sharper.\nGrow Wiser.',
      body: 'Every fact-check you run builds real media literacy. '
          'Credexa tracks your critical thinking growth and helps you spot manipulation before it spreads.',
      accent: Color(0xFF6366F1),
      bgTop: Color(0xFF0D0D2B),
      bgBottom: Color(0xFF12122E),
      statValue: 'Skill',
      statLabel: 'Media literacy can be learned and sharpened with practice',
    ),
    _Slide(
      eyebrow: 'THE MISSION',
      title: 'Be the\nChange.',
      body: 'Credexa is built for UN SDG Goal 16. Every fact-check you run '
          'builds a more informed, just democracy.',
      accent: Color(0xFFF59E0B),
      bgTop: Color(0xFF1A0F00),
      bgBottom: Color(0xFF1C1100),
      statValue: 'SDG 16',
      statLabel: 'Peace, justice and strong institutions',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entranceCtrl = List.generate(
      _slides.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _entranceCtrl[0].forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in _entranceCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  void _next() {
    HapticFeedback.mediumImpact();
    if (_page < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _complete();
    }
  }

  Future<void> _complete() async {
    HapticFeedback.heavyImpact();
    final p = await SharedPreferences.getInstance();
    await p.setBool('hasSeenOnboarding', true);
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_page];

    return Scaffold(
      backgroundColor: slide.bgTop,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [slide.bgTop, slide.bgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: DefaultTextStyle(
            // Reset all inherited decoration — this fixes the yellow underlines.
            style: const TextStyle(decoration: TextDecoration.none),
            child: Column(
              children: [
                // ── Top bar ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
                  child: Row(
                    children: [
                      Image.asset('assets/logomain.png', height: 52),
                      const Spacer(),
                      TextButton(
                        onPressed: _complete,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          overlayColor: Colors.white.withValues(alpha: 0.2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100)),
                        ),
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Slides ─────────────────────────────────────────────────
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _page = i);
                      _entranceCtrl[i].forward(from: 0.0);
                    },
                    itemCount: _slides.length,
                    itemBuilder: (_, i) {
                      final s = _slides[i];
                      return AnimatedBuilder(
                        animation: _entranceCtrl[i],
                        builder: (_, child) {
                          final t = CurvedAnimation(
                            parent: _entranceCtrl[i],
                            curve: Curves.easeOutCubic,
                          ).value;
                          return Opacity(
                            opacity: t.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, 24 * (1 - t)),
                              child: child,
                            ),
                          );
                        },
                        child: _SlideView(slide: s, pageIndex: i),
                      );
                    },
                  ),
                ),

                // ── Dots ───────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? slide.accent
                            : Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),

                // ── CTA ────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GlassButton(
                    onTap: _next,
                    accent: slide.accent,
                    onDark: true,
                    height: 58,
                    radius: 18,
                    haptic: GlassHaptic.none,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _page < _slides.length - 1 ? 'Next' : 'Get Started',
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (_page < _slides.length - 1) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 20, color: Colors.white),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SINGLE SLIDE — phone mockup top, content bottom
// ─────────────────────────────────────────────────────────────────────────────
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.pageIndex});
  final _Slide slide;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Phone mockup — fills available vertical space ─────────────
        Expanded(
          child: Center(
            child: _PhoneMockup(slide: slide, pageIndex: pageIndex),
          ),
        ),

        // ── Text content pinned at bottom ─────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Eyebrow ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: slide.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: slide.accent.withValues(alpha: 0.30)),
                ),
                child: Text(
                  slide.eyebrow,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: slide.accent,
                    letterSpacing: 1.3,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Title ───────────────────────────────────────────────
              Text(
                slide.title,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.12,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 10),

              // ── Body ────────────────────────────────────────────────
              Text(
                slide.body,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.85),
                  height: 1.6,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 16),

              // ── Stat chip ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: slide.accent.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      slide.statValue,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: slide.accent,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        slide.statLabel,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.80),
                          height: 1.45,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PHONE MOCKUP  —  real screenshot images per slide
// ─────────────────────────────────────────────────────────────────────────────
class _PhoneMockup extends StatelessWidget {
  const _PhoneMockup({required this.slide, required this.pageIndex});
  final _Slide slide;
  final int pageIndex;

  static const _images = [
    'assets/onboarding1.png',
    'assets/onboarding2.png',
    'assets/onboarding3.png',
  ];

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.36;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: slide.accent.withValues(alpha: 0.15),
              blurRadius: 36,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            _images[pageIndex],
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────
class _Slide {
  const _Slide({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.accent,
    required this.bgTop,
    required this.bgBottom,
    required this.statValue,
    required this.statLabel,
  });
  final String eyebrow, title, body, statValue, statLabel;
  final Color accent, bgTop, bgBottom;
}

