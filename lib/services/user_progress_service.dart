import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Maturity level model ──────────────────────────────────────────────────────

class MaturityLevel {
  const MaturityLevel({
    required this.title,
    required this.emoji,
    required this.minPoints,
    required this.nextLevelPoints,
  });
  final String title;
  final String emoji;
  final int minPoints;
  final int nextLevelPoints; // -1 = max level

  double progress(int points) {
    if (nextLevelPoints == -1) return 1.0;
    return ((points - minPoints) / (nextLevelPoints - minPoints)).clamp(0.0, 1.0);
  }

  int pointsToNext(int points) =>
      nextLevelPoints == -1 ? 0 : (nextLevelPoints - points).clamp(0, nextLevelPoints);
}

const kMaturityLevels = [
  MaturityLevel(title: 'Media Novice',     emoji: '🌱', minPoints: 0,    nextLevelPoints: 50),
  MaturityLevel(title: 'Fact Finder',      emoji: '🔍', minPoints: 50,   nextLevelPoints: 150),
  MaturityLevel(title: 'Truth Seeker',     emoji: '🎯', minPoints: 150,  nextLevelPoints: 350),
  MaturityLevel(title: 'Critical Thinker', emoji: '🧠', minPoints: 350,  nextLevelPoints: 700),
  MaturityLevel(title: 'Bias Analyst',     emoji: '⚖️', minPoints: 700,  nextLevelPoints: 1200),
  MaturityLevel(title: 'Info Master',      emoji: '🏆', minPoints: 1200, nextLevelPoints: -1),
];

// ── Stats snapshot ────────────────────────────────────────────────────────────

class UserProgressStats {
  const UserProgressStats({
    required this.maturityPoints,
    required this.predictionsTotal,
    required this.predictionsCorrect,
    required this.questsAnswered,
    required this.questsCorrect,
  });

  static const zero = UserProgressStats(
    maturityPoints:     0,
    predictionsTotal:   0,
    predictionsCorrect: 0,
    questsAnswered:     0,
    questsCorrect:      0,
  );

  final int maturityPoints;
  final int predictionsTotal;
  final int predictionsCorrect;
  final int questsAnswered;
  final int questsCorrect;

  double get predictionAccuracy =>
      predictionsTotal == 0 ? 0 : predictionsCorrect / predictionsTotal;

  MaturityLevel get level => UserProgressService.levelFor(maturityPoints);

  UserProgressStats copyWith({
    int? maturityPoints,
    int? predictionsTotal,
    int? predictionsCorrect,
    int? questsAnswered,
    int? questsCorrect,
  }) =>
      UserProgressStats(
        maturityPoints:     maturityPoints     ?? this.maturityPoints,
        predictionsTotal:   predictionsTotal   ?? this.predictionsTotal,
        predictionsCorrect: predictionsCorrect ?? this.predictionsCorrect,
        questsAnswered:     questsAnswered     ?? this.questsAnswered,
        questsCorrect:      questsCorrect      ?? this.questsCorrect,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class UserProgressService {
  UserProgressService._();

  static final stats = ValueNotifier<UserProgressStats>(UserProgressStats.zero);

  static String get _uid =>
      fb.FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
  static String _k(String f) => '${_uid}_up_$f';

  static MaturityLevel levelFor(int points) {
    for (final lvl in kMaturityLevels.reversed) {
      if (points >= lvl.minPoints) return lvl;
    }
    return kMaturityLevels.first;
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    stats.value = UserProgressStats(
      maturityPoints:     p.getInt(_k('mp')) ?? 0,
      predictionsTotal:   p.getInt(_k('pt')) ?? 0,
      predictionsCorrect: p.getInt(_k('pc')) ?? 0,
      questsAnswered:     p.getInt(_k('qa')) ?? 0,
      questsCorrect:      p.getInt(_k('qc')) ?? 0,
    );
  }

  static Future<void> _save(UserProgressStats s) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_k('mp'), s.maturityPoints);
    await p.setInt(_k('pt'), s.predictionsTotal);
    await p.setInt(_k('pc'), s.predictionsCorrect);
    await p.setInt(_k('qa'), s.questsAnswered);
    await p.setInt(_k('qc'), s.questsCorrect);
    stats.value = s;
  }

  // ── Accuracy prediction ──────────────────────────────────────────────────────
  // [prediction] is 'true' or 'false' (user's guess before seeing the result).
  // [aiVerdict] is the synthesis finalVerdict string from AnalysisResult.
  static Future<bool> recordPrediction(
      String prediction, String aiVerdict) async {
    final correct = _isPredictionCorrect(prediction, aiVerdict);
    final s = stats.value;
    await _save(s.copyWith(
      maturityPoints:     s.maturityPoints + (correct ? 5 : 1),
      predictionsTotal:   s.predictionsTotal + 1,
      predictionsCorrect: s.predictionsCorrect + (correct ? 1 : 0),
    ));
    return correct;
  }

  static bool _isPredictionCorrect(String prediction, String verdict) {
    final v = verdict.toUpperCase();
    if (prediction == 'true') {
      return v == 'CREDIBLE' || v == 'LIKELY_TRUE';
    }
    // 'false' prediction is correct if verdict is misleading or uncertain
    return v == 'MISLEADING' || v == 'LIKELY_FALSE' || v == 'UNCERTAIN';
  }

  // ── Daily quest ──────────────────────────────────────────────────────────────

  static String _todayStr() {
    final t = DateTime.now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  static Future<bool> shouldShowDailyQuest() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_k('last_quest_date')) ?? '') != _todayStr();
  }

  static Future<void> markQuestSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k('last_quest_date'), _todayStr());
  }

  static Future<Map<String, dynamic>?> getCachedQuest() async {
    final p = await SharedPreferences.getInstance();
    if ((p.getString(_k('cached_quest_date')) ?? '') != _todayStr()) return null;
    final json = p.getString(_k('cached_quest_json'));
    if (json == null) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheQuest(Map<String, dynamic> quest) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k('cached_quest_date'), _todayStr());
    await p.setString(_k('cached_quest_json'), jsonEncode(quest));
  }

  static Future<void> recordQuestResult({required bool correct}) async {
    final s = stats.value;
    await _save(s.copyWith(
      maturityPoints: s.maturityPoints + (correct ? 15 : 5),
      questsAnswered: s.questsAnswered + 1,
      questsCorrect:  s.questsCorrect + (correct ? 1 : 0),
    ));
  }

  // ── Micro-survey ─────────────────────────────────────────────────────────────

  static Future<int>          getSurveyCount()    async => (await SharedPreferences.getInstance()).getInt(_k('sv_count'))    ?? 0;
  static Future<int>          getSurveyPositive() async => (await SharedPreferences.getInstance()).getInt(_k('sv_pos'))      ?? 0;
  static Future<List<String>> getSurveyComments() async =>
      (await SharedPreferences.getInstance()).getStringList(_k('sv_comments')) ?? [];

  static Future<void> recordSurveyResponse({
    required bool positive,
    String? comment,
  }) async {
    final p       = await SharedPreferences.getInstance();
    final count   = (p.getInt(_k('sv_count'))  ?? 0) + 1;
    final pos     = (p.getInt(_k('sv_pos'))    ?? 0) + (positive ? 1 : 0);
    await p.setInt(_k('sv_count'), count);
    await p.setInt(_k('sv_pos'),   pos);
    if (comment != null && comment.trim().isNotEmpty) {
      final existing = p.getStringList(_k('sv_comments')) ?? [];
      existing.insert(0, comment.trim());
      // Keep last 20 comments to avoid unbounded growth.
      await p.setStringList(_k('sv_comments'), existing.take(20).toList());
    }
    // Bonus maturity points for engaging with the survey.
    await addMaturityPoints(2);
  }

  static Future<void> addMaturityPoints(int pts) async {
    final s = stats.value;
    await _save(s.copyWith(maturityPoints: s.maturityPoints + pts));
  }
}
