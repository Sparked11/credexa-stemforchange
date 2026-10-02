import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../models/quest_item.dart';

/// Serves the Daily Quest banner: a bundled bank of ~170 hand-written items
/// across 5 difficulty tiers, selected adaptively based on the user's recent
/// accuracy, with an AI-generated fallback if the bundled bank can't be read.
class QuestService {
  static const _kApiKey = kOpenRouterApiKey;
  static const _kUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const _kModel = 'openai/gpt-4o-mini'; // use mini for quests (cost-efficient)
  static const _kAssetPath = 'assets/quests/daily_quests.json';

  static const _kTierKey = 'daily_quest_tier';
  static const _kSeenKeyPrefix = 'daily_quest_seen_tier_';
  static const _kRollingKey = 'daily_quest_rolling';

  static List<QuestItem>? _bank;

  static Future<List<QuestItem>> _loadBank() async {
    final cached = _bank;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString(_kAssetPath);
      final list = jsonDecode(raw) as List<dynamic>;
      final parsed = list
          .map((e) => QuestItem.fromJson(e as Map<String, dynamic>))
          .toList();
      _bank = parsed;
      return parsed;
    } catch (_) {
      _bank = const [];
      return const [];
    }
  }

  /// The user's current adaptive difficulty tier (1 = beginner, 5 = expert).
  /// Starts at 2 so a brand-new user isn't dropped straight into hard content.
  static Future<int> currentTier() async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(_kTierKey) ?? 2).clamp(1, 5);
  }

  /// Feeds a quest result into the rolling-accuracy window (last 5 answers)
  /// and adjusts the tier: 3+ recent answers at >=80% accuracy moves up a
  /// tier; <=34% moves down a tier. Otherwise the tier holds steady, so one
  /// lucky or unlucky guess doesn't swing the difficulty.
  static Future<void> recordAnswer(bool correct) async {
    final p = await SharedPreferences.getInstance();
    final rolling = (p.getStringList(_kRollingKey) ?? <String>[])
      ..add(correct ? '1' : '0');
    while (rolling.length > 5) {
      rolling.removeAt(0);
    }
    await p.setStringList(_kRollingKey, rolling);

    var tier = (p.getInt(_kTierKey) ?? 2).clamp(1, 5);
    if (rolling.length >= 3) {
      final accuracy =
          rolling.map(int.parse).reduce((a, b) => a + b) / rolling.length;
      if (accuracy >= 0.8) {
        tier = (tier + 1).clamp(1, 5);
      } else if (accuracy <= 0.34) {
        tier = (tier - 1).clamp(1, 5);
      }
    }
    await p.setInt(_kTierKey, tier);
  }

  /// Picks today's quest at the user's current tier, cycling through every
  /// item at that tier before any repeat. Never throws — falls back to an
  /// AI-generated quest if the bundled bank is somehow unavailable, and to a
  /// nearby tier if a tier happens to be empty.
  static Future<QuestItem> getAdaptiveDailyQuest() async {
    final bank = await _loadBank();
    if (bank.isEmpty) {
      try {
        return QuestItem.fromLegacyAiMap(await generateQuest());
      } catch (_) {
        return _placeholderQuest();
      }
    }

    final tier = await currentTier();
    var pool = bank.where((q) => q.difficulty == tier).toList();
    if (pool.isEmpty) pool = bank;

    final p = await SharedPreferences.getInstance();
    final seenKey = '$_kSeenKeyPrefix$tier';
    var seen = (p.getStringList(seenKey) ?? <String>[]).toSet();
    var unseen = pool.where((q) => !seen.contains(q.id)).toList();
    if (unseen.isEmpty) {
      seen = {};
      unseen = pool;
    }

    final dayIndex = DateTime.now().difference(DateTime(2024, 1, 1)).inDays;
    final picked = unseen[dayIndex.abs() % unseen.length];
    seen.add(picked.id);
    await p.setStringList(seenKey, seen.toList());
    return picked;
  }

  static QuestItem _placeholderQuest() => const QuestItem(
        id: 'placeholder',
        format: QuestFormat.post,
        difficulty: 2,
        category: 'General',
        technique: 'Loaded Language',
        techniqueDefinition:
            'Using emotionally charged words instead of neutral ones to steer your opinion.',
        question: 'What technique is this post using?',
        options: [
          'It uses emotionally loaded words to push a reaction.',
          'It cites a credible, named source.',
          'It presents balanced evidence on both sides.',
          'It asks a neutral, open-ended question.',
        ],
        correctIndex: 0,
        explanation:
            'Loaded Language swaps neutral words for emotionally charged ones to influence '
            'how you feel about a claim before you\'ve evaluated the facts.',
        postText:
            'Check back tomorrow for a new daily quest — today\'s couldn\'t load.',
        postHandle: '@credexa',
        postPlatform: 'twitter',
      );

  static String _systemPrompt() => '''
You are a media-literacy educator making quick daily quiz cards for teenagers.
Generate ONE punchy social media post that uses exactly ONE manipulation technique.

STRICT RULES:
- post_text: 1-2 sentences MAX. Under 25 words. Sound like a real tweet or caption. Can include 1 hashtag or emoji.
- options: exactly 4 short labels. Each option is 2-4 words ONLY — no long phrases.
- explanation: 1-2 short sentences only.

Return ONLY valid JSON (no markdown):
{
  "post_text": "<1-2 sentence post, max 25 words>",
  "technique": "<exact technique name>",
  "options": ["<2-4 word label>", "<2-4 word label>", "<2-4 word label>", "<2-4 word label>"],
  "correct_index": <0-3>,
  "explanation": "<1-2 short sentences>",
  "difficulty": "<easy|medium|hard>",
  "topic": "<topic category>"
}

Technique must be one of: Fear Appeal, Loaded Language, False Dichotomy, Cherry Picking,
Bandwagon, Appeal to Authority, Emotional Manipulation, Scapegoating, Us-vs-Them Framing,
Sensationalism, Ad Hominem, Straw Man, Slippery Slope, Whataboutism, Appeal to Nature,
Hasty Generalization, False Cause, Manufactured Urgency, Gaslighting, False Equivalence,
Appeal to Tradition.
Options must include the correct technique and 3 plausible-but-wrong alternatives.
correct_index is the 0-based index of the correct answer in options.''';

  /// Generates a single quest (social post + 4 options + answer + explanation)
  /// via the AI, used only as a last-resort fallback if the bundled quest
  /// bank asset can't be read.
  ///
  /// Returns a [Map] with: post_text, options (`List<String>`), correct_index,
  /// explanation, technique, difficulty, topic.
  /// Throws an [Exception] on network failure, non-200 response, or bad JSON.
  static Future<Map<String, dynamic>> generateQuest({
    String difficulty = 'medium',
  }) async {
    final response = await http
        .post(
          Uri.parse(_kUrl),
          headers: {
            'Authorization': 'Bearer $_kApiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://credexa.app',
            'X-Title': 'Credexa',
          },
          body: jsonEncode({
            'model': _kModel,
            'messages': [
              {'role': 'system', 'content': _systemPrompt()},
              {
                'role': 'user',
                'content':
                    'Generate one media-literacy quest at "$difficulty" difficulty. '
                    'Return only the JSON object from your system prompt.',
              },
            ],
            'temperature': 0.9,
            'max_tokens': 600,
          }),
        )
        .timeout(const Duration(seconds: 30));

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final msg = (body['error'] as Map<String, dynamic>?)?['message'] ??
          'OpenRouter error ${response.statusCode}';
      throw Exception(msg);
    }

    final content =
        (body['choices'] as List<dynamic>)[0]['message']['content'] as String?;
    if (content == null || content.isEmpty) {
      throw Exception('Empty response from model');
    }

    final clean = content
        .replaceAll(RegExp(r'^```json?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'```\s*$'), '')
        .trim();

    final quest = jsonDecode(clean) as Map<String, dynamic>;

    final rawOptions = quest['options'];
    final options = rawOptions is List
        ? rawOptions.map((e) => e.toString()).toList()
        : <String>[];

    final rawIndex = quest['correct_index'];
    final correctIndex = rawIndex is int
        ? rawIndex
        : int.tryParse('${rawIndex ?? 0}') ?? 0;

    return {
      'post_text':   (quest['post_text']   as String?)?.trim() ?? '',
      'technique':   (quest['technique']   as String?)?.trim() ?? '',
      'options':     options,
      'correct_index':
          (correctIndex >= 0 && correctIndex < options.length) ? correctIndex : 0,
      'explanation': (quest['explanation'] as String?)?.trim() ?? '',
      'difficulty':  (quest['difficulty']  as String?)?.trim() ?? difficulty,
      'topic':       (quest['topic']       as String?)?.trim() ?? 'general',
    };
  }
}
