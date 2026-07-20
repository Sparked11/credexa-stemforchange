import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'feedback_service.dart';

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
    this.accuracyHistory = const [],
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
  // Running accuracy (0.0–1.0) snapshotted after every prediction — all-time.
  final List<double> accuracyHistory;

  double get predictionAccuracy =>
      predictionsTotal == 0 ? 0 : predictionsCorrect / predictionsTotal;

  MaturityLevel get level => UserProgressService.levelFor(maturityPoints);

  UserProgressStats copyWith({
    int? maturityPoints,
    int? predictionsTotal,
    int? predictionsCorrect,
    int? questsAnswered,
    int? questsCorrect,
    List<double>? accuracyHistory,
  }) =>
      UserProgressStats(
        maturityPoints:     maturityPoints     ?? this.maturityPoints,
        predictionsTotal:   predictionsTotal   ?? this.predictionsTotal,
        predictionsCorrect: predictionsCorrect ?? this.predictionsCorrect,
        questsAnswered:     questsAnswered     ?? this.questsAnswered,
        questsCorrect:      questsCorrect      ?? this.questsCorrect,
        accuracyHistory:    accuracyHistory    ?? this.accuracyHistory,
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
    List<double> hist = [];
    try {
      final raw = p.getString(_k('acc_hist')) ?? '[]';
      hist = (jsonDecode(raw) as List)
          .map((e) => (e as num).toDouble())
          .toList();
    } catch (_) {}
    stats.value = UserProgressStats(
      maturityPoints:     p.getInt(_k('mp')) ?? 0,
      predictionsTotal:   p.getInt(_k('pt')) ?? 0,
      predictionsCorrect: p.getInt(_k('pc')) ?? 0,
      questsAnswered:     p.getInt(_k('qa')) ?? 0,
      questsCorrect:      p.getInt(_k('qc')) ?? 0,
      accuracyHistory:    hist,
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
    unawaited(pushToCloud(s));
  }

  // ── Cloud sync (users/{uid}.progress) ────────────────────────────────────────

  /// Pushes the current (or given) stats snapshot to Firestore. Fire-and-forget:
  /// never throws into the caller, and a slow/offline network never blocks the UI
  /// — Firestore's own offline-persistence queue flushes the write on reconnect.
  static Future<void> pushToCloud([UserProgressStats? s]) async {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = s ?? stats.value;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'progress': {
          'maturityPoints':     snap.maturityPoints,
          'predictionsTotal':   snap.predictionsTotal,
          'predictionsCorrect': snap.predictionsCorrect,
          'questsAnswered':     snap.questsAnswered,
          'questsCorrect':      snap.questsCorrect,
          'accuracyHistory':    snap.accuracyHistory,
          'updatedAt':          FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort — local SharedPreferences remains the source of truth here.
    }
  }

  /// Overwrites local state (memory + SharedPreferences) with a remote snapshot
  /// pulled from Firestore. Does not re-push — called only by [SyncService].
  static Future<void> applyRemote(Map<String, dynamic> remote) async {
    List<double> hist = [];
    try {
      hist = (remote['accuracyHistory'] as List? ?? [])
          .map((e) => (e as num).toDouble())
          .toList();
    } catch (_) {}
    final s = UserProgressStats(
      maturityPoints:     (remote['maturityPoints']     as num?)?.toInt() ?? 0,
      predictionsTotal:   (remote['predictionsTotal']   as num?)?.toInt() ?? 0,
      predictionsCorrect: (remote['predictionsCorrect'] as num?)?.toInt() ?? 0,
      questsAnswered:     (remote['questsAnswered']     as num?)?.toInt() ?? 0,
      questsCorrect:      (remote['questsCorrect']      as num?)?.toInt() ?? 0,
      accuracyHistory:    hist,
    );
    final p = await SharedPreferences.getInstance();
    await p.setInt(_k('mp'), s.maturityPoints);
    await p.setInt(_k('pt'), s.predictionsTotal);
    await p.setInt(_k('pc'), s.predictionsCorrect);
    await p.setInt(_k('qa'), s.questsAnswered);
    await p.setInt(_k('qc'), s.questsCorrect);
    await p.setString(_k('acc_hist'), jsonEncode(s.accuracyHistory));
    stats.value = s;
  }

  // Append a running-accuracy snapshot to the history (max 50 points).
  static Future<List<double>> _appendHistory(double accuracy) async {
    final p   = await SharedPreferences.getInstance();
    List<double> hist = [];
    try {
      hist = (jsonDecode(p.getString(_k('acc_hist')) ?? '[]') as List)
          .map((e) => (e as num).toDouble())
          .toList();
    } catch (_) {}
    hist.add(accuracy);
    if (hist.length > 50) hist.removeRange(0, hist.length - 50);
    await p.setString(_k('acc_hist'), jsonEncode(hist));
    return hist;
  }

  // ── Accuracy prediction ──────────────────────────────────────────────────────
  // [prediction] is 'true' or 'false' (user's guess before seeing the result).
  // [aiVerdict] is the synthesis finalVerdict string from AnalysisResult.
  static Future<bool> recordPrediction(
      String prediction, String aiVerdict) async {
    final correct = _isPredictionCorrect(prediction, aiVerdict);
    final s = stats.value;
    final newCorrect = s.predictionsCorrect + (correct ? 1 : 0);
    final newTotal   = s.predictionsTotal + 1;
    final hist = await _appendHistory(newCorrect / newTotal);
    await _save(s.copyWith(
      maturityPoints:     s.maturityPoints + (correct ? 5 : 1),
      predictionsTotal:   newTotal,
      predictionsCorrect: newCorrect,
      accuracyHistory:    hist,
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

  // ── De-bias manipulation slider prediction ───────────────────────────────────
  // Correct if the user's guess lands in the same bias category as the AI score.
  static Future<bool> recordDebiasPrediction(int userScore, int aiScore) async {
    final correct = _biasCategory(userScore) == _biasCategory(aiScore);
    final s = stats.value;
    final newCorrect = s.predictionsCorrect + (correct ? 1 : 0);
    final newTotal   = s.predictionsTotal + 1;
    final hist = await _appendHistory(newCorrect / newTotal);
    await _save(s.copyWith(
      maturityPoints:     s.maturityPoints + (correct ? 5 : 1),
      predictionsTotal:   newTotal,
      predictionsCorrect: newCorrect,
      accuracyHistory:    hist,
    ));
    return correct;
  }

  // 0=Neutral, 1=Mildly Biased, 2=Clearly Biased, 3=Highly Biased
  static int _biasCategory(int score) {
    if (score <= 20) return 0;
    if (score <= 50) return 1;
    if (score <= 80) return 2;
    return 3;
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
    final newCorrect = s.predictionsCorrect + (correct ? 1 : 0);
    final newTotal   = s.predictionsTotal + 1;
    final hist = await _appendHistory(newCorrect / newTotal);
    await _save(s.copyWith(
      maturityPoints:     s.maturityPoints + (correct ? 15 : 5),
      questsAnswered:     s.questsAnswered + 1,
      questsCorrect:      s.questsCorrect + (correct ? 1 : 0),
      predictionsTotal:   newTotal,
      predictionsCorrect: newCorrect,
      accuracyHistory:    hist,
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
    // Persist locally so the trigger counter still works.
    final p     = await SharedPreferences.getInstance();
    final count = (p.getInt(_k('sv_count')) ?? 0) + 1;
    await p.setInt(_k('sv_count'), count);

    // Send to Google Sheets — errors are swallowed inside FeedbackService.
    FeedbackService.submit(helpful: positive, comment: comment);

    // Bonus maturity points for engaging with the survey.
    await addMaturityPoints(2);
  }

  static Future<void> addMaturityPoints(int pts) async {
    final s = stats.value;
    await _save(s.copyWith(maturityPoints: s.maturityPoints + pts));
  }
}
