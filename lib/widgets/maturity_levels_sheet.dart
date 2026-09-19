import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/user_progress_service.dart';
import '../theme/app_tokens.dart';

const _levelBlurbs = <String, String>{
  'Media Novice':
      'You are just starting out. You are learning to notice that headlines, posts and videos are shaped by someone.',
  'Fact Finder':
      'You pause before believing or sharing, and you know how to look a claim up.',
  'Truth Seeker':
      'You look for evidence, compare sources and ask who is behind a claim.',
  'Critical Thinker':
      'You spot emotional wording, missing context and weak logic without help.',
  'Bias Analyst':
      'You can name the kind of bias in a story and explain how it changes the message.',
  'Info Master':
      'You evaluate information with confidence and help others do the same.',
};

const _levelColors = <Color>[
  Color(0xFF94A3B8),
  Color(0xFF0EA5E9),
  Color(0xFF22C55E),
  Color(0xFF6366F1),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
];

Future<void> showMaturityLevels(BuildContext context) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const MaturityLevelsSheet(),
  );
}

class MaturityLevelsSheet extends StatelessWidget {
  const MaturityLevelsSheet({super.key});

  static const _earn = [
    (Icons.psychology_alt_rounded, 'Correct prediction', '+5 pts', AppColors.green),
    (Icons.lightbulb_outline_rounded, 'Wrong prediction (you still learn)', '+1 pt', AppColors.sky),
    (Icons.menu_book_rounded, 'Daily quest answered correctly', '+15 pts', AppColors.indigo),
    (Icons.menu_book_rounded, 'Daily quest attempted', '+5 pts', AppColors.amber),
    (Icons.rate_review_rounded, 'Quick feedback survey', '+2 pts', Color(0xFFEC4899)),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.slate900 : AppColors.slate100,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ValueListenableBuilder<UserProgressStats>(
          valueListenable: UserProgressService.stats,
          builder: (context, stats, _) {
            final current = stats.level;
            final currentIdx = kMaturityLevels.indexOf(current);
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Media Maturity',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Six levels that track how well you evaluate information. Your level rises as you earn points.',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 13,
                    height: 1.5,
                    color: cs.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 18),
                _CurrentCard(stats: stats),
                const SizedBox(height: 22),
                _sectionTitle(context, 'HOW TO EARN POINTS'),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _earn.length; i++) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: _earn[i].$4.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_earn[i].$1,
                                    size: 18, color: _earn[i].$4),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _earn[i].$2,
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              Text(
                                _earn[i].$3,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: _earn[i].$4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (i < _earn.length - 1)
                          Divider(
                              height: 1,
                              indent: 60,
                              color: cs.onSurface.withValues(alpha: 0.08)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle(context, 'ALL LEVELS'),
                const SizedBox(height: 12),
                for (var i = 0; i < kMaturityLevels.length; i++)
                  _LevelRow(
                    index: i,
                    level: kMaturityLevels[i],
                    state: i < currentIdx
                        ? _LevelState.achieved
                        : (i == currentIdx
                            ? _LevelState.current
                            : _LevelState.locked),
                    pointsToGo: kMaturityLevels[i].minPoints - stats.maturityPoints,
                    isLast: i == kMaturityLevels.length - 1,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      );
}

class _CurrentCard extends StatelessWidget {
  final UserProgressStats stats;
  const _CurrentCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final lvl = stats.level;
    final idx = kMaturityLevels.indexOf(lvl);
    final color = _levelColors[idx];
    final next = idx + 1 < kMaturityLevels.length ? kMaturityLevels[idx + 1] : null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.35)!],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(lvl.emoji, style: const TextStyle(fontSize: 38)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR LEVEL',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    Text(
                      lvl.title,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${stats.maturityPoints} pts',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: lvl.progress(stats.maturityPoints),
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            next == null
                ? 'You have reached the top level. Keep sharpening your skills.'
                : '${lvl.pointsToNext(stats.maturityPoints)} pts to reach ${next.title}',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LevelState { achieved, current, locked }

class _LevelRow extends StatelessWidget {
  final int index;
  final MaturityLevel level;
  final _LevelState state;
  final int pointsToGo;
  final bool isLast;
  const _LevelRow({
    required this.index,
    required this.level,
    required this.state,
    required this.pointsToGo,
    required this.isLast,
  });

  String get _range => level.nextLevelPoints == -1
      ? '${level.minPoints}+ pts'
      : '${level.minPoints} – ${level.nextLevelPoints - 1} pts';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _levelColors[index];
    final locked = state == _LevelState.locked;
    final current = state == _LevelState.current;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: locked
                    ? null
                    : LinearGradient(colors: [
                        color,
                        Color.lerp(color, Colors.black, 0.3)!,
                      ]),
                color: locked ? cs.onSurface.withValues(alpha: 0.08) : null,
                boxShadow: current
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: locked
                  ? Icon(Icons.lock_rounded,
                      size: 18, color: cs.onSurface.withValues(alpha: 0.4))
                  : Text(level.emoji, style: const TextStyle(fontSize: 22)),
            ),
            if (!isLast)
              Container(
                width: 3,
                height: 74,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: state == _LevelState.achieved
                      ? color.withValues(alpha: 0.7)
                      : cs.onSurface.withValues(alpha: 0.1),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: current
                      ? color.withValues(alpha: 0.7)
                      : cs.onSurface.withValues(alpha: 0.06),
                  width: current ? 1.6 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          level.title,
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: locked
                                ? cs.onSurface.withValues(alpha: 0.7)
                                : cs.onSurface,
                          ),
                        ),
                      ),
                      _StatusChip(
                        text: current
                            ? 'You are here'
                            : (locked ? '$pointsToGo pts to go' : 'Achieved'),
                        color: current
                            ? color
                            : (locked ? cs.onSurface : AppColors.green),
                        strong: !locked,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _range,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _levelBlurbs[level.title] ?? '',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      height: 1.5,
                      color: cs.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  final bool strong;
  const _StatusChip(
      {required this.text, required this.color, required this.strong});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: strong ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: strong ? color : color.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
