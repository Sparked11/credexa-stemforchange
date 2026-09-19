import 'dart:async';

enum AchievementKind { badge, level }

class Achievement {
  final AchievementKind kind;
  final String emoji;
  final String title;
  final String subtitle;
  const Achievement({
    required this.kind,
    required this.emoji,
    required this.title,
    required this.subtitle,
  });
}

/// Event bus for "you just unlocked something" moments. Producers call
/// [announce] at the instant a counter changes; the UI shows a toast.
class AchievementService {
  AchievementService._();

  static final _controller = StreamController<Achievement>.broadcast();
  static Stream<Achievement> get stream => _controller.stream;

  static void announce(Achievement a) => _controller.add(a);
}
