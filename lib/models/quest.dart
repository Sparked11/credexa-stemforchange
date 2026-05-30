// ── Quest data model ──────────────────────────────────────────────────────────
// Models for the gamified "Learning Quests" feature: each quest presents a
// social-media post and asks the user to identify the manipulation technique.

class QuestOption {
  const QuestOption({
    required this.label,
    required this.isCorrect,
    required this.explanation,
  });

  final String label;
  final bool isCorrect;
  final String explanation;
}

enum QuestDifficulty { easy, medium, hard }

class Quest {
  const Quest({
    required this.id,
    required this.postText,
    required this.technique,
    required this.options,
    required this.explanation,
    required this.topic,
    this.difficulty = QuestDifficulty.medium,
  });

  final String id;
  final String postText; // The social media post to evaluate
  final String technique; // The correct manipulation technique
  final List<QuestOption> options; // 4 options, one isCorrect
  final String explanation; // Why this is manipulative
  final String topic; // e.g. "Health", "Politics"
  final QuestDifficulty difficulty;

  int get xpReward => switch (difficulty) {
        QuestDifficulty.easy => 10,
        QuestDifficulty.medium => 25,
        QuestDifficulty.hard => 50,
      };
}
