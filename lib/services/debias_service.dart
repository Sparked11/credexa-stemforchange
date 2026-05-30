import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import '../models/debias_result.dart';

const _kApiKey = kOpenRouterApiKey;
const _kModel  = 'openai/gpt-4o';
const _kFallbackModel = 'anthropic/claude-3-5-haiku';
const _kUrl    = 'https://openrouter.ai/api/v1/chat/completions';

class DebiasService {
  static String _today() {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December',
    ];
    final d = DateTime.now();
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static const _iconMap = {
    'Loaded Language':        '🔥',
    'Fear Appeal':            '😱',
    'Vilification':           '🎭',
    'Us-vs-Them Framing':     '⚔️',
    'Absolute Language':      '🚨',
    'Missing Balance':        '📍',
    'One-Sided Framing':      '📣',
    'Misleading Stats':       '📊',
    'Sensationalism':         '💥',
    'Unverified Claim':       '❓',
    'Emotional Manipulation': '💔',
    'Scapegoating':           '🐐',
  };

  static String _systemPrompt() => '''
You are a professional media-bias analyst and neutral-language editor for Credexa, a teen media-literacy platform aligned with UN SDG Goal 16.
Today's date is ${_today()}. Do NOT treat any date on or before today as a future date.

The user will provide a text snippet (headline, social post, or article excerpt).

Your tasks:
1. Identify every bias technique used: loaded/emotional language, one-sided framing, vilification, fear appeals, absolute language, misleading stats, unverified claims presented as fact, us-vs-them framing, scapegoating, sensationalism.
2. Rewrite the text in factual, balanced, neutral language — keep all true facts, remove all manipulation.
3. List each specific change you made.

Respond with ONLY a valid JSON object. Do NOT use markdown fences. Do NOT add text outside the JSON.

{
  "bias_score": <integer 0-100; 0 = perfectly neutral, 100 = maximum bias>,
  "neutral_text": "<full neutral rewrite>",
  "changes": [
    {
      "type": "<bias pattern, e.g. 'Loaded Language', 'Fear Appeal', 'Us-vs-Them Framing', 'Absolute Language', 'Missing Balance', 'One-Sided Framing', 'Misleading Stats', 'Sensationalism', 'Unverified Claim', 'Vilification', 'Emotional Manipulation', 'Scapegoating'>",
      "original": "<exact problematic phrase from the input>",
      "rewritten": "<the neutral replacement used in your rewrite>",
      "explanation": "<one sentence explaining why this phrase is manipulative>",
      "severity": "<low | medium | high>"
    }
  ],
  "bias_types": ["<top 1-3 bias category names found>"],
  "manipulation_tactics": ["<top 2-3 named tactics>"],
  "readability": { "grade_level": <integer 1-20>, "tone": "<alarming | neutral | persuasive | informational>" },
  "perspectives": {
    "left":   { "label": "Progressive Take",   "text": "<~40-word reframe emphasising systemic causes, equity, or community impact — factual but through that lens>", "note": "<one phrase describing the rhetorical choice made>" },
    "center": { "label": "Neutral / Factual",  "text": "<same as neutral_text — copy it here>",                                                                     "note": "Sticks strictly to verifiable facts with no advocacy" },
    "right":  { "label": "Conservative Take",  "text": "<~40-word reframe emphasising individual responsibility, free markets, or limited government — factual but through that lens>", "note": "<one phrase describing the rhetorical choice made>" }
  }
}

Rules:
- bias_score: 0-20 = mostly neutral, 21-50 = mildly biased, 51-80 = clearly biased, 81-100 = highly manipulative
- If text is already neutral (bias_score < 15): set neutral_text = original text, changes = []
- List 1-6 specific changes; pick the most impactful ones
- neutral_text and perspective texts should be similar length to the original
- Write explanations a 14-year-old can understand
- Perspectives must be fair, factual representations — not caricatures or strawmen of either side

After your JSON, ensure bias_score is calibrated accurately:
- Corporate PR language, euphemisms for layoffs/cuts → score 25-40
- Political attack ads, partisan framing → score 60-80
- Conspiracy theories, dehumanizing language → score 85-100
- Academic/journalistic neutral writing → score 0-15

For each change in the "changes" array, also add a "severity" field: "low" | "medium" | "high"
  - high: dehumanization, incitement, dangerous misinformation
  - medium: clear manipulation, fear appeal, vilification
  - low: loaded language, slight framing bias

Add a "manipulation_tactics" array (top 2-3 named tactics from: "Bandwagon", "Fear Appeal", "False Dichotomy", "Ad Hominem", "Strawman", "Cherry Picking", "Appeal to Authority", "Emotional Appeal", "Loaded Language", "Scapegoating") as a top-level JSON field.

Add a "readability" object: { "grade_level": <Flesch-Kincaid grade estimate 1-20>, "tone": "alarming" | "neutral" | "persuasive" | "informational" }''';

  static String _imageSystemPrompt() => '''
You are a professional media-bias analyst and neutral-language editor for Credexa, a teen media-literacy platform aligned with UN SDG Goal 16.
Today's date is ${_today()}. Do NOT treat any date on or before today as a future date.

The user will share an image (e.g. a screenshot of a social media post). Your tasks:
1. Perform OCR: extract ALL visible text from the image.
2. Analyze it for bias patterns and rewrite in neutral language.
3. List each specific change made.

Respond with ONLY a valid JSON object. Do NOT use markdown fences. Do NOT add text outside the JSON.

{
  "extracted_text": "<all text you extracted from the image>",
  "bias_score": <integer 0-100>,
  "neutral_text": "<full neutral rewrite of the extracted text>",
  "changes": [
    {
      "type": "<bias pattern name>",
      "original": "<exact problematic phrase>",
      "rewritten": "<neutral replacement>",
      "explanation": "<one sentence for a 14-year-old>",
      "severity": "<low | medium | high>"
    }
  ],
  "bias_types": ["<top bias categories found>"],
  "manipulation_tactics": ["<top 2-3 named tactics>"],
  "readability": { "grade_level": <integer 1-20>, "tone": "<alarming | neutral | persuasive | informational>" },
  "perspectives": {
    "left":   { "label": "Progressive Take",  "text": "<~40-word reframe through a progressive lens>", "note": "<one phrase on the rhetorical choice>" },
    "center": { "label": "Neutral / Factual", "text": "<same as neutral_text>",                        "note": "Sticks strictly to verifiable facts" },
    "right":  { "label": "Conservative Take", "text": "<~40-word reframe through a conservative lens>","note": "<one phrase on the rhetorical choice>" }
  }
}

Rules:
- Perspectives must be fair, factual representations — not caricatures of either side
- Write for a 14-year-old audience
- Pay special attention to visual context clues like ALL CAPS text, exclamation marks, and emotional imagery descriptions that amplify bias
- If the image contains a chart or graph, check for truncated Y-axes, cherry-picked date ranges, or misleading visual scaling

After your JSON, ensure bias_score is calibrated accurately:
- Corporate PR language, euphemisms for layoffs/cuts → score 25-40
- Political attack ads, partisan framing → score 60-80
- Conspiracy theories, dehumanizing language → score 85-100
- Academic/journalistic neutral writing → score 0-15

For each change in the "changes" array, also add a "severity" field: "low" | "medium" | "high"
  - high: dehumanization, incitement, dangerous misinformation
  - medium: clear manipulation, fear appeal, vilification
  - low: loaded language, slight framing bias

Add a "manipulation_tactics" array (top 2-3 named tactics from: "Bandwagon", "Fear Appeal", "False Dichotomy", "Ad Hominem", "Strawman", "Cherry Picking", "Appeal to Authority", "Emotional Appeal", "Loaded Language", "Scapegoating") as a top-level JSON field.

Add a "readability" object: { "grade_level": <Flesch-Kincaid grade estimate 1-20>, "tone": "alarming" | "neutral" | "persuasive" | "informational" }''';

  /// Performs a single OpenRouter request against [model] and parses the
  /// JSON object returned by the model. Throws on non-200 or empty response.
  static Future<Map<String, dynamic>> _request(
    String model,
    List<Map<String, dynamic>> messages,
    int maxTokens,
  ) async {
    final response = await http.post(
      Uri.parse(_kUrl),
      headers: {
        'Authorization': 'Bearer $_kApiKey',
        'Content-Type':  'application/json',
        'HTTP-Referer':  'https://credexa.app',
        'X-Title':       'Credexa',
      },
      body: jsonEncode({
        'model':       model,
        'messages':    messages,
        'temperature': 0.15,
        'max_tokens':  maxTokens,
      }),
    ).timeout(const Duration(seconds: 60));

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final msg = (body['error'] as Map<String, dynamic>?)?['message']
          ?? 'OpenRouter error ${response.statusCode}';
      throw Exception(msg);
    }
    final content = (body['choices'] as List<dynamic>)[0]['message']['content'] as String?;
    if (content == null || content.isEmpty) throw Exception('Empty response from model');
    final clean = content
        .replaceAll(RegExp(r'^```json?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'```\s*$'), '')
        .trim();
    return jsonDecode(clean) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _call(
    List<Map<String, dynamic>> messages, {
    int maxTokens = 1800,
  }) async {
    try {
      return await _request(_kModel, messages, maxTokens);
    } catch (primaryError) {
      // Primary model failed (exception or non-200). Retry once with the
      // fallback model before surfacing the original error to the UI.
      try {
        return await _request(_kFallbackModel, messages, maxTokens);
      } catch (_) {
        throw primaryError;
      }
    }
  }

  static Map<String, dynamic> _addIcons(Map<String, dynamic> result) {
    final changes = result['changes'];
    if (changes is List) {
      result['changes'] = changes.map((c) {
        final m = Map<String, dynamic>.from(c as Map<String, dynamic>);
        m['icon'] = _iconMap[m['type']] ?? '🔍';
        return m;
      }).toList();
    }
    return result;
  }

  static Future<DebiasResult> debiasText(String text) async {
    final result = await _call([
      {'role': 'system', 'content': _systemPrompt()},
      {'role': 'user',   'content': 'Text to de-bias:\n\n"${text.trim()}"'},
    ]);
    return DebiasResult.fromJson(_addIcons(result), text);
  }

  static Future<DebiasResult> debiasImage(Uint8List bytes, String mimeType) async {
    final b64 = base64Encode(bytes);
    final result = await _call(
      [
        {'role': 'system', 'content': _imageSystemPrompt()},
        {
          'role': 'user',
          'content': [
            {'type': 'image_url', 'image_url': {'url': 'data:$mimeType;base64,$b64'}},
            {'type': 'text',      'text': 'Extract all text from this image, then de-bias it. Return the JSON from your system prompt.'},
          ],
        },
      ],
      maxTokens: 2000,
    );
    final extracted = result['extracted_text'] as String? ?? '';
    return DebiasResult.fromJson(_addIcons(result), extracted);
  }
}
