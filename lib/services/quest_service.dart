import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import '../data/daily_quest_bank.dart';

/// Generates AI-powered media-literacy quest content via OpenRouter.
///
/// Used by the Learning Quests feature. Each quest is a realistic social media
/// post that demonstrates exactly one manipulation technique, paired with
/// multiple-choice options and an explanation.
class QuestService {
  static const _kApiKey = kOpenRouterApiKey;
  static const _kUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const _kModel = 'openai/gpt-4o-mini'; // use mini for quests (cost-efficient)

  static String _systemPrompt() => '''
You are a media-literacy educator making quick daily quiz cards for teenagers.
Generate ONE punchy social media post that uses exactly ONE manipulation technique.

STRICT RULES:
- post_text: 1-2 sentences MAX. Under 25 words. Sound like a real tweet or caption. Can include 1 hashtag or emoji.
- options: exactly 4 short labels. Each option is 2-4 words ONLY — no long phrases.
- topic_emoji: a single emoji that represents the post topic (e.g. 🌍 environment, 🏛️ politics, 💊 health, 📱 tech, ⚽ sports).
- explanation: 1-2 short sentences only.

Return ONLY valid JSON (no markdown):
{
  "post_text": "<1-2 sentence post, max 25 words>",
  "technique": "<exact technique name>",
  "topic_emoji": "<single emoji>",
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

  /// Returns a quest from the local 100-question bank, selected by day of year.
  /// Never fails — no network required.
  static Map<String, dynamic> getLocalQuest() {
    final dayIndex =
        DateTime.now().difference(DateTime(2024, 1, 1)).inDays;
    return DailyQuestBank.getForDay(dayIndex);
  }

  /// Generates a single quest (social post + 4 options + answer + explanation).
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

    // Normalize and guard the returned fields with safe defaults so callers
    // never receive a partially-shaped map.
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
      'topic_emoji': (quest['topic_emoji'] as String?)?.trim() ?? '📱',
      'options':     options,
      'correct_index':
          (correctIndex >= 0 && correctIndex < options.length) ? correctIndex : 0,
      'explanation': (quest['explanation'] as String?)?.trim() ?? '',
      'difficulty':  (quest['difficulty']  as String?)?.trim() ?? difficulty,
      'topic':       (quest['topic']       as String?)?.trim() ?? 'general',
    };
  }
}
