import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/profile_service.dart';
import '../theme/app_tokens.dart';
import 'adaptive_chrome.dart';

class _Category {
  final String name;
  final IconData icon;
  final Color color;
  final List<String> titles;
  const _Category(this.name, this.icon, this.color, this.titles);
}

const _categories = [
  _Category('Milestones', Icons.emoji_events_rounded, Color(0xFFF59E0B),
      ['Welcome!', 'Credexa Champion']),
  _Category('Fact-checking', Icons.fact_check_rounded, Color(0xFF6366F1),
      ['Fact Finder', 'Truth Seeker', 'Myth Buster']),
  _Category('De-bias', Icons.tune_rounded, Color(0xFF14B8A6),
      ['Bias Aware', 'Critical Thinker']),
  _Category('Community', Icons.forum_rounded, Color(0xFF22C55E),
      ['Community Voice', 'Hub Regular']),
  _Category('Quests', Icons.explore_rounded, Color(0xFFF97316),
      ['Quest Starter', 'Quest Master']),
];

class _Counts {
  final int checks, debiases, posts, quests;
  const _Counts(this.checks, this.debiases, this.posts, this.quests);
}

class _Part {
  final String label;
  final int have, need;
  const _Part(this.label, this.have, this.need);
}

List<_Part> _partsFor(BadgeInfo b, _Counts c) => [
      if (b.checks > 0) _Part('Fact-checks', c.checks, b.checks),
      if (b.debiases > 0) _Part('De-biases', c.debiases, b.debiases),
      if (b.posts > 0) _Part('Community posts', c.posts, b.posts),
      if (b.quests > 0) _Part('Quests', c.quests, b.quests),
    ];

double _progressFor(BadgeInfo b, _Counts c) {
  final parts = _partsFor(b, c);
  if (parts.isEmpty) return 1;
  final sum = parts.fold<double>(
      0, (s, p) => s + (p.have / p.need).clamp(0.0, 1.0));
  return sum / parts.length;
}

const _grey = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// Grouped, shelf-style badge display with progress rings on locked badges.
class BadgeCollection extends StatelessWidget {
  final int checks, debiases, posts, quests;
  const BadgeCollection({
    super.key,
    required this.checks,
    required this.debiases,
    required this.posts,
    required this.quests,
  });

  @override
  Widget build(BuildContext context) {
    final counts = _Counts(checks, debiases, posts, quests);
    final earned = kBadges
        .where((b) => b.isEarned(checks, debiases, posts, quests))
        .length;

    BadgeInfo? next;
    var bestFrac = -1.0;
    for (final b in kBadges) {
      if (b.isEarned(checks, debiases, posts, quests)) continue;
      final f = _progressFor(b, counts);
      if (f > bestFrac) {
        bestFrac = f;
        next = b;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScrollReveal(
            child: _Header(
              earned: earned,
              total: kBadges.length,
              next: next,
              nextFrac: bestFrac,
            ),
          ),
          const SizedBox(height: 16),
          for (final cat in _categories)
            ScrollReveal(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CategorySection(cat: cat, counts: counts),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int earned, total;
  final BadgeInfo? next;
  final double nextFrac;
  const _Header({
    required this.earned,
    required this.total,
    required this.next,
    required this.nextFrac,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : earned / total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111827), Color(0xFF1E1B4B)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(92, 92),
                    painter: _RingPainter(
                      progress: v,
                      color: const Color(0xFFFBBF24),
                      track: Colors.white.withValues(alpha: 0.12),
                      stroke: 9,
                      glow: true,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$earned',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                      Text(
                        'of $total',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Badge Collection',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  earned == total
                      ? 'Every badge unlocked. Legend!'
                      : '${total - earned} more to unlock. Tap any badge for details.',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(next!.emoji,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Next: ${next!.title} · ${(nextFrac * 100).round()}%',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category shelf ────────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final _Category cat;
  final _Counts counts;
  const _CategorySection({required this.cat, required this.counts});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badges = [
      for (final t in cat.titles) kBadges.firstWhere((b) => b.title == t),
    ];
    final got = badges
        .where((b) => b.isEarned(
            counts.checks, counts.debiases, counts.posts, counts.quests))
        .length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF243247), cs.surface]
              : [Colors.white, const Color(0xFFF1F5F9)],
        ),
        border:
            Border.all(color: Colors.white.withValues(alpha: isDark ? 0.07 : 0.9)),
        boxShadow: [
          BoxShadow(
            color: cat.color.withValues(alpha: isDark ? 0.16 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(cat.icon, size: 17, color: cat.color),
              ),
              const SizedBox(width: 10),
              Text(
                cat.name,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$got / ${badges.length}',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: cat.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in badges)
                Expanded(child: _MedalTile(badge: b, cat: cat, counts: counts)),
              for (var i = badges.length; i < 3; i++)
                const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 10),
          // Shelf edge
          Container(
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(colors: [
                cat.color.withValues(alpha: 0.05),
                cat.color.withValues(alpha: 0.35),
                cat.color.withValues(alpha: 0.05),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedalTile extends StatelessWidget {
  final BadgeInfo badge;
  final _Category cat;
  final _Counts counts;
  const _MedalTile(
      {required this.badge, required this.cat, required this.counts});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final earned =
        badge.isEarned(counts.checks, counts.debiases, counts.posts, counts.quests);
    final frac = _progressFor(badge, counts);
    final parts = _partsFor(badge, counts);
    final caption = earned
        ? 'Unlocked'
        : (parts.length == 1
            ? '${parts.first.have} / ${parts.first.need}'
            : '${(frac * 100).round()}%');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showBadgeDetail(
          context, badge, cat.color, counts.checks, counts.debiases,
          counts.posts, counts.quests),
      child: Column(
        children: [
          _Medal(
              emoji: badge.emoji,
              color: cat.color,
              earned: earned,
              progress: frac,
              size: 78),
          const SizedBox(height: 8),
          Text(
            badge.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: earned ? cs.onSurface : cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            caption,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: earned
                  ? AppColors.greenDark
                  : cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Medal ─────────────────────────────────────────────────────────────────────

class _Medal extends StatelessWidget {
  final String emoji;
  final Color color;
  final bool earned;
  final double progress;
  final double size;
  const _Medal({
    required this.emoji,
    required this.color,
    required this.earned,
    required this.progress,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inner = size - 16;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (earned)
            Container(
              width: inner,
              height: inner,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: earned ? 1 : progress,
              color: color,
              track: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.10),
              stroke: 5,
              glow: earned,
            ),
          ),
          Container(
            width: inner,
            height: inner,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: earned
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(color, Colors.white, 0.35)!,
                        Color.lerp(color, Colors.black, 0.25)!,
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? const [Color(0xFF334155), Color(0xFF1E293B)]
                          : const [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
                    ),
            ),
            child: earned
                ? Text(emoji, style: TextStyle(fontSize: size * 0.4))
                : ColorFiltered(
                    colorFilter: _grey,
                    child: Opacity(
                      opacity: 0.5,
                      child: Text(emoji,
                          style: TextStyle(fontSize: size * 0.4)),
                    ),
                  ),
          ),
          if (earned)
            Positioned(
              top: 10,
              left: 14,
              child: Container(
                width: inner * 0.42,
                height: inner * 0.22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: LinearGradient(colors: [
                    Colors.white.withValues(alpha: 0.5),
                    Colors.white.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            ),
          if (!earned)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: Icon(Icons.lock_rounded,
                    size: 12,
                    color: isDark ? Colors.white70 : const Color(0xFF64748B)),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double stroke;
  final bool glow;
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = Rect.fromCircle(
        center: rect.center, radius: (size.width - stroke) / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [
          Color.lerp(color, Colors.white, 0.35)!,
          color,
          Color.lerp(color, Colors.black, 0.2)!,
        ],
      ).createShader(rect);
    if (glow) {
      canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * progress, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ── Detail sheet ──────────────────────────────────────────────────────────────

void showBadgeDetail(BuildContext context, BadgeInfo badge, Color color,
    int checks, int debiases, int posts, int quests) {
  HapticFeedback.lightImpact();
  final counts = _Counts(checks, debiases, posts, quests);
  final earned = badge.isEarned(checks, debiases, posts, quests);
  final parts = _partsFor(badge, counts);
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, 28 + MediaQuery.of(ctx).padding.bottom),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate900 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),
          _Medal(
            emoji: badge.emoji,
            color: color,
            earned: earned,
            progress: _progressFor(badge, counts),
            size: 120,
          ),
          const SizedBox(height: 16),
          Text(
            badge.title,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            badge.desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              height: 1.5,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (earned ? AppColors.green : cs.onSurface)
                  .withValues(alpha: earned ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(earned ? Icons.check_circle_rounded : Icons.lock_rounded,
                    size: 15,
                    color: earned
                        ? AppColors.greenDark
                        : cs.onSurface.withValues(alpha: 0.65)),
                const SizedBox(width: 6),
                Text(
                  earned ? 'Unlocked' : 'Locked',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: earned
                        ? AppColors.greenDark
                        : cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 20),
            for (final p in parts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.label,
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '${p.have.clamp(0, p.need)} / ${p.need}',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: LinearProgressIndicator(
                        value: (p.have / p.need).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
