import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Shared scroll state that lets the top bar, bottom nav and scroll-reveal
/// sections react to whichever page is currently scrolling.
class ChromeController extends ChangeNotifier {
  double offset = 0;
  double heroHeight = 0;
  bool navHidden = false;
  double _accum = 0;

  /// 1 while the dark hero sits behind the top bar, fading to 0 once it has
  /// scrolled away. Always 0 on pages without a hero.
  double get topDark {
    if (heroHeight <= 0) return 0;
    final fadeStart = heroHeight - 64 - 80;
    return (1 - (offset - fadeStart) / 80).clamp(0.0, 1.0);
  }

  void onScroll(double pixels, double delta) {
    final next = pixels < 0 ? 0.0 : pixels;
    var hidden = navHidden;
    if (pixels <= 8) {
      hidden = false;
      _accum = 0;
    } else {
      if ((delta > 0 && _accum < 0) || (delta < 0 && _accum > 0)) _accum = 0;
      _accum += delta;
      if (_accum > 28) {
        hidden = true;
        _accum = 28;
      } else if (_accum < -10) {
        hidden = false;
        _accum = -10;
      }
    }
    if (next == offset && hidden == navHidden) return;
    offset = next;
    navHidden = hidden;
    notifyListeners();
  }

  void setHeroHeight(double h) {
    if ((h - heroHeight).abs() < 0.5) return;
    heroHeight = h;
    notifyListeners();
  }

  void reset() {
    offset = 0;
    heroHeight = 0;
    navHidden = false;
    _accum = 0;
    notifyListeners();
  }
}

class ChromeScope extends InheritedWidget {
  final ChromeController controller;
  const ChromeScope({super.key, required this.controller, required super.child});

  static ChromeController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ChromeScope>()
      ?.controller;

  @override
  bool updateShouldNotify(ChromeScope old) => controller != old.controller;
}

/// Measures its child and reports the height (used for the home hero).
class HeroHeightReporter extends StatefulWidget {
  final Widget child;
  const HeroHeightReporter({super.key, required this.child});

  @override
  State<HeroHeightReporter> createState() => _HeroHeightReporterState();
}

class _HeroHeightReporterState extends State<HeroHeightReporter> {
  ChromeController? _chrome;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome = ChromeScope.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) _chrome?.setHeroHeight(box.size.height);
    });
    return widget.child;
  }
}

/// Top bar that blends into the page: solid at rest, frosted glass once
/// content scrolls beneath it, and transparent while the dark hero is behind.
class GlassTopBar extends StatelessWidget {
  final Widget Function(BuildContext context, double dark) builder;
  final double height;

  const GlassTopBar({super.key, required this.builder, this.height = 64});

  /// Convenience for pages that don't need the dark-hero mode.
  GlassTopBar.simple({super.key, required Widget child, this.height = 64})
      : builder = ((_, _) => child);

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.maybeOf(context);
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (chrome == null) {
      return Container(height: height, color: bg, child: builder(context, 0));
    }

    return ListenableBuilder(
      listenable: chrome,
      builder: (context, _) {
        final scrolled = (chrome.offset / 48).clamp(0.0, 1.0);
        final dark = chrome.topDark;
        final overHero = chrome.heroHeight > 0;
        final alpha = overHero
            ? (1 - dark) * (0.55 + 0.35 * scrolled)
            : 1.0 - 0.18 * scrolled;
        final blur = overHero ? 18 * (1 - dark) : 18 * scrolled;
        final borderAlpha = overHero ? (1 - dark) * scrolled : scrolled;

        Widget bar = Container(
          height: height,
          decoration: BoxDecoration(
            color: bg.withValues(alpha: alpha),
            border: Border(
              bottom: BorderSide(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.08 * borderAlpha),
              ),
            ),
          ),
          child: builder(context, dark),
        );
        if (blur > 0.5) {
          bar = ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: bar,
            ),
          );
        }
        return bar;
      },
    );
  }
}

/// Scroll-linked entrance: content rises, unfolds in 3D and fades in as it
/// travels up into view, and reverses when scrolled back down.
class ScrollReveal extends StatefulWidget {
  final Widget child;
  final double distance;
  final int side; // -1 unfolds from the left, 1 from the right, 0 straight up

  const ScrollReveal({
    super.key,
    required this.child,
    this.distance = 44,
    this.side = 0,
  });

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal> {
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
    return ((vh - 90 - y) / (vh * 0.24)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.maybeOf(context);
    if (chrome == null) return widget.child;
    return ListenableBuilder(
      listenable: chrome,
      builder: (context, child) {
        final p = Curves.easeOutCubic.transform(_progress(context, chrome));
        final inv = 1 - p;
        return Opacity(
          opacity: p,
          child: Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..translateByDouble(0.0, widget.distance * inv, 0.0, 1.0)
              ..rotateX(0.38 * inv)
              ..rotateY(widget.side * 0.32 * inv)
              ..scaleByDouble(0.94 + 0.06 * p, 0.94 + 0.06 * p, 1.0, 1.0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Tracks a widget's on-screen top edge during scrolling. Layout positions are
/// one frame stale while building, so this extrapolates from the last measured
/// position using the live scroll offset.
class ScrollTopTracker {
  double? _y0;
  double _o0 = 0;
  bool _pending = false;

  double? topY(BuildContext context, ChromeController chrome) {
    final est = _y0 == null ? null : _y0! - (chrome.offset - _o0);
    if (!_pending) {
      _pending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        if (!context.mounted) return;
        final box = context.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          _y0 = box.localToGlobal(Offset.zero).dy;
          _o0 = chrome.offset;
        }
      });
    }
    return est;
  }
}
