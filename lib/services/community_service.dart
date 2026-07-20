import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../models/community_message.dart';
import 'web_search_service.dart';
import 'ocr_service.dart';

const _kApiKey          = kOpenRouterApiKey;
const _kModerationModel = 'openai/gpt-4o-mini';          // image safety — reliably returns bare JSON
const _kUrl             = 'https://openrouter.ai/api/v1/chat/completions';
const _kCollection = 'community_hub';
const _kMaxMessages = 50;
// A message hidden from everyone once this many distinct users report it, so
// objectionable content is removed automatically without waiting for a manual
// review (App Store Review Guideline 1.2).
const _kReportHideThreshold = 2;
const _kBlockedKey = 'community_blocked_users';

// Basic profanity word list — whole-word and substring checks combined
const _kProfanity = <String>[
  'fuck', 'shit', 'ass', 'bitch', 'cunt', 'dick', 'cock', 'pussy',
  'nigger', 'nigga', 'faggot', 'fag', 'retard', 'whore', 'slut',
  'bastard', 'asshole', 'bullshit', 'motherfuck', 'douchebag',
  'dipshit', 'jackass', 'dumbass', 'prick', 'twat',
];

class CommunityService {
  static final _col = FirebaseFirestore.instance.collection(_kCollection);

  // Locally blocked user ids — messages from these users are hidden on this
  // device. Loaded once via [loadModeration]; kept in memory for synchronous
  // filtering in [messagesStream].
  static final Set<String> _blockedUsers = {};

  /// Loads the device's blocked-user list. Call once at app/hub startup.
  static Future<void> loadModeration() async {
    final p = await SharedPreferences.getInstance();
    _blockedUsers
      ..clear()
      ..addAll(p.getStringList(_kBlockedKey) ?? const []);
  }

  static bool isBlocked(String? userId) =>
      userId != null && _blockedUsers.contains(userId);

  static List<String> get blockedUsers => _blockedUsers.toList();

  /// Blocks a user so their messages are hidden on this device.
  static Future<void> blockUser(String userId) async {
    _blockedUsers.add(userId);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kBlockedKey, _blockedUsers.toList());
  }

  static Future<void> unblockUser(String userId) async {
    _blockedUsers.remove(userId);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kBlockedKey, _blockedUsers.toList());
  }

  /// Flags a message as objectionable. Records the reporter (so double-reports
  /// don't inflate the count) and bumps the report counter; once
  /// [_kReportHideThreshold] distinct users report it, [messagesStream] hides it
  /// from everyone automatically.
  static Future<void> reportMessage(String messageId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = _col.doc(messageId);
    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(doc);
      if (!snap.exists) return;
      final d = snap.data() as Map<String, dynamic>;
      final reportedBy = <String>{
        for (final e in (d['reportedBy'] as List<dynamic>? ?? [])) e.toString(),
      };
      if (reportedBy.contains(uid)) return; // already reported by this user
      reportedBy.add(uid);
      txn.update(doc, {
        'reportedBy':  reportedBy.toList(),
        'reportCount': reportedBy.length,
      });
    });
  }

  /// True if a message should be hidden from the current viewer — because they
  /// blocked its author, it crossed the community report threshold, or they
  /// personally reported it.
  static bool isHidden(CommunityMessage m) {
    if (isBlocked(m.userId)) return true;
    if (m.reportCount >= _kReportHideThreshold) return true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && m.reportedBy.contains(uid)) return true;
    return false;
  }

  static Stream<List<CommunityMessage>> messagesStream() {
    return _col
        .orderBy('timestamp')
        .limitToLast(_kMaxMessages)
        .snapshots()
        .map((s) => s.docs
            .map(CommunityMessage.fromFirestore)
            .where((m) => !isHidden(m))
            .toList());
  }

  /// Returns an error string if the text contains profanity/bad content,
  /// or null if the text is acceptable.
  static String? checkText(String text) {
    if (text.trim().isEmpty) return 'Please write something before posting.';
    // Strip punctuation and lowercase for matching
    final lower = text.toLowerCase().replaceAll(RegExp(r"[^a-z\s']"), ' ');
    final words  = lower.split(RegExp(r'\s+'));
    for (final word in words) {
      final stripped = word.replaceAll("'", '');
      if (_kProfanity.any((p) => stripped == p || stripped.contains(p))) {
        return "Your message contains language that isn't allowed. Please keep it respectful.";
      }
    }
    return null;
  }

  /// Checks an image for explicit/inappropriate content using AI vision.
  /// Returns a record with `safe` (bool) and optional `reason` (String?).
  static Future<({bool safe, String? reason})> moderateImage(
      Uint8List bytes, String mimeType) async {
    final b64 = base64Encode(bytes);
    final res = await http.post(
      Uri.parse(_kUrl),
      headers: {
        'Authorization': 'Bearer $_kApiKey',
        'Content-Type':  'application/json',
        'HTTP-Referer':  'https://credexa.app',
        'X-Title':       'Credexa',
      },
      body: jsonEncode({
        'model':    _kModerationModel,
        'messages': [
          {
            'role':    'user',
            'content': [
              {
                'type': 'text',
                'text': '''You are a content moderator for a teen fact-checking app (ages 13-17).
Analyze this image and respond with ONLY valid JSON — no markdown, no extra text.
{"safe":true,"reason":null}  or  {"safe":false,"reason":"<brief reason>"}

Flag as NOT safe if the image contains: explicit sexual content, nudity, graphic violence or gore, hate symbols, harassment targeting an individual.
Screenshots of news articles, social media posts, memes, claims, or any informational content are ALWAYS safe.
If safe, reason must be null.''',
              },
              {
                'type':      'image_url',
                'image_url': {'url': 'data:$mimeType;base64,$b64'},
              },
            ],
          }
        ],
        'temperature': 0,
        'max_tokens':  80,
      }),
    ).timeout(const Duration(seconds: 30));

    final body    = jsonDecode(res.body) as Map<String, dynamic>;
    final content = (body['choices'] as List)[0]['message']['content'] as String;
    final clean   = content
        .replaceAll(RegExp(r'^```json?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'```\s*$'), '')
        .trim();
    final json = jsonDecode(clean) as Map<String, dynamic>;
    return (
      safe:   json['safe']   as bool?   ?? true,
      reason: json['reason'] as String?,
    );
  }

  /// Posts a new question (with optional image) and triggers a combined AI response.
  static Future<void> ask(
    String question, {
    Uint8List? imageBytes,
    String?    mimeType,
  }) async {
    final base      = DateTime.now();
    final uid       = FirebaseAuth.instance.currentUser?.uid;
    final hasImage  = imageBytes != null && mimeType != null;
    final labelText = question.trim().isEmpty
        ? (hasImage ? '📷 Image shared for analysis' : '')
        : question.trim();

    final questionDoc = <String, dynamic>{
      'text':      labelText,
      'type':      'question',
      'timestamp': Timestamp.fromDate(base),
      'userId':    uid,
    };
    if (hasImage) {
      questionDoc['imageBase64']   = base64Encode(imageBytes);
      questionDoc['imageMimeType'] = mimeType;
    }
    await _col.add(questionDoc);

    final q = question.trim();

    // For images: OCR first so we know what claim/text is in the image.
    // That extracted text becomes the RSS search query regardless of how
    // short the user's typed question is.
    String ocrText = '';
    if (hasImage) {
      try {
        ocrText = await OcrService.extractText(imageBytes, mimeType);
      } catch (_) {}
    }

    // Search query: OCR text drives image lookups; user question drives text lookups.
    final searchQuery = ocrText.isNotEmpty ? ocrText : q;
    final searchable  = searchQuery.length >= 10;

    // rssArticles  → shown to user as tappable links (always from RSS).
    // promptArticles → fed to the AI with context where available.
    List<Map<String, String>> rssArticles    = [];
    List<Map<String, String>> promptArticles = [];
    if (searchable) {
      rssArticles = await WebSearchService.searchWithLinks(searchQuery);
      if (rssArticles.isNotEmpty) {
        if (hasImage) {
          // Images: skip body scraping to keep the request fast and small.
          // The image itself + OCR text already provide the main content.
          promptArticles = rssArticles.take(3)
              .map((a) => {...a, 'excerpt': ''}).toList();
        } else {
          final scraped = await WebSearchService.scrapeArticles(rssArticles);
          promptArticles = scraped.isNotEmpty
              ? scraped
              : rssArticles.take(3).map((a) => {...a, 'excerpt': ''}).toList();
        }
      }
    }

    // Links stored in Firestore always come from rssArticles so they appear
    // regardless of whether scraping succeeded.
    final linksToStore = rssArticles
        .take(3)
        .where((a) => (a['url'] ?? '').isNotEmpty)
        .map((a) => {
              'title':  a['title']  ?? '',
              'source': a['source'] ?? '',
              'url':    a['url']    ?? '',
            })
        .toList();

    String aiText;
    try {
      aiText = await _callAI(
        q,
        imageBytes: imageBytes,
        mimeType:   mimeType,
        articles:   promptArticles,
        ocrText:    ocrText,
      );
    } catch (_) {
      aiText = "I couldn't analyze this right now — please try again in a moment.";
    }

    if (aiText.isNotEmpty) {
      await _col.add({
        'text':      aiText,
        'type':      'ai',
        'timestamp': Timestamp.fromDate(base.add(const Duration(seconds: 1))),
        'links':     linksToStore,
      });
    }

    await _trim();
  }

  /// Posts a community member reply with optional image.
  static Future<void> postReply(
    String text, {
    Uint8List? imageBytes,
    String? mimeType,
  }) async {
    final uid  = FirebaseAuth.instance.currentUser?.uid;
    final data = <String, dynamic>{
      'text':      text.trim(),
      'type':      'reply',
      'timestamp': Timestamp.now(),
      'userId':    uid,
    };
    if (imageBytes != null && mimeType != null) {
      data['imageBase64']   = base64Encode(imageBytes);
      data['imageMimeType'] = mimeType;
    }
    await _col.add(data);
    await _trim();
  }

  /// Toggles an emoji reaction for a user on a message.
  /// Removing an existing reaction if the same emoji is tapped again.
  /// Switching to a new emoji if a different one is tapped.
  static Future<void> toggleReaction(
    String messageId,
    String emoji,
    String userId,
  ) async {
    final doc = _col.doc(messageId);
    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(doc);
      if (!snap.exists) return;
      final d = snap.data() as Map<String, dynamic>;

      final reactions = <String, int>{
        for (final e in (d['reactions'] as Map<String, dynamic>? ?? {}).entries)
          e.key: (e.value as num).toInt(),
      };
      final userReactions = <String, String>{
        for (final e in (d['userReactions'] as Map<String, dynamic>? ?? {}).entries)
          e.key: e.value as String,
      };

      final existing = userReactions[userId];
      if (existing == emoji) {
        // Toggle off
        reactions[emoji] = (reactions[emoji] ?? 1) - 1;
        if ((reactions[emoji] ?? 0) <= 0) reactions.remove(emoji);
        userReactions.remove(userId);
      } else {
        if (existing != null) {
          // Remove old reaction
          reactions[existing] = (reactions[existing] ?? 1) - 1;
          if ((reactions[existing] ?? 0) <= 0) reactions.remove(existing);
        }
        reactions[emoji] = (reactions[emoji] ?? 0) + 1;
        userReactions[userId] = emoji;
      }

      txn.update(doc, {
        'reactions':     reactions,
        'userReactions': userReactions,
      });
    });
  }

  static Future<void> _trim() async {
    final all    = await _col.orderBy('timestamp').get();
    final excess = all.docs.length - _kMaxMessages;
    if (excess <= 0) return;
    final batch  = FirebaseFirestore.instance.batch();
    for (int i = 0; i < excess; i++) {
      batch.delete(all.docs[i].reference);
    }
    await batch.commit();
  }

  static String _today() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final d = DateTime.now();
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Calls the AI and returns a single combined fact-check + verification tip.
  /// Pass [imageBytes] + [mimeType] to include an image in the analysis.
  static Future<String> _callAI(
    String question, {
    Uint8List?                imageBytes,
    String?                   mimeType,
    List<Map<String, String>> articles = const [],
    String                    ocrText  = '',
  }) async {
    final hasImage   = imageBytes != null && mimeType != null;
    final effectiveQ = question.isEmpty
        ? 'Is this image real, authentic, or misleading? Is it AI-generated or photoshopped?'
        : question;

    // Build rich article context from scraped content + titles.
    final String articleBlock;
    if (articles.isEmpty) {
      articleBlock = '';
    } else {
      final buf = StringBuffer('\n\n━━ WEB EVIDENCE (scraped today) ━━\n');
      for (var i = 0; i < articles.length; i++) {
        final a       = articles[i];
        final source  = a['source']  ?? '';
        final title   = a['title']   ?? '';
        final excerpt = a['excerpt'] ?? '';
        buf.write('[${i + 1}] ');
        if (source.isNotEmpty) buf.write('$source — ');
        buf.writeln(title);
        if (excerpt.isNotEmpty) buf.writeln(excerpt);
        buf.writeln();
      }
      buf.write('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      articleBlock = buf.toString();
    }

    final String prompt;
    if (hasImage) {
      final ocrBlock = ocrText.isNotEmpty
          ? '\n\nText extracted from the image:\n"""\n$ocrText\n"""'
          : '';
      prompt = '''
You are an expert fact-checker in the Credexa Community Explanation Hub — a safe, anonymous space where teens ask "Is this real?" about images and media.
Today's date is ${_today()}.$ocrBlock$articleBlock

A community member shared an image and asked: "$effectiveQ"

Your task: fact-check the CLAIM OR INFORMATION shown in this image.
1. Look at the image and the extracted text above.
2. Use the web evidence (if provided) to verify whether what the image shows or says is true, false, or misleading.
3. Write a clear response of 3–5 sentences:
   • Sentence 1: State directly whether the claim or content in the image is TRUE, FALSE, MISLEADING, or UNVERIFIABLE — and why, citing web sources by name if available (e.g., "According to Reuters…").
   • Sentence 2: Add any important factual context or nuance.
   • Sentence 3: Name any manipulation technique present in the image itself (AI-generated, photoshopped, fake headline overlay, etc.) — or confirm the image appears authentic.
   • Sentence 4–5 (optional): Explain the misinformation technique used, if any.
   • Final sentence: Give one concrete action the reader can take to verify this themselves.

Rules:
- Prioritize fact-checking the TEXT/CLAIM in the image over judging visual authenticity.
- If web evidence above contradicts or confirms the claim, say so and name the source.
- Write for a 13–17 year old audience. Clear, friendly, no jargon.
- Do NOT use bullet points, headers, or labels. Write as natural flowing prose.
- Return ONLY the response text — no JSON, no markdown, no preamble.''';
    } else {
      prompt = '''
You are an expert fact-checker in the Credexa Community Explanation Hub — a safe, anonymous space where teens ask "Is this real?" about news and social media.
Today's date is ${_today()}. Do NOT treat any date on or before today as a future date.$articleBlock

A community member asked: "$effectiveQ"

Write a clear, well-grounded response of 3–5 sentences:
• Sentences 1–2: Give a direct, factual verdict backed by the web evidence above where relevant. Say clearly what is true, false, or uncertain. Cite the source name (e.g., "According to Reuters…") if you draw on the evidence.
• Sentence 3: Name the specific misinformation technique if one is used (e.g., "This uses cherry-picking" / "This is a false headline designed to cause outrage") — or confirm why the claim is credible based on the evidence.
• Sentence 4–5 (optional, only if the evidence warrants): Add any important nuance or context that helps a teen understand the full picture.
• Final sentence: Give one concrete action the reader can take to verify this themselves.

Rules:
- Write for a 13–17 year old audience. Clear, friendly, no jargon.
- Be fair and non-partisan. If a claim is true, say so clearly with evidence.
- If the web evidence above contradicts or confirms the claim, prioritize that over your training data.
- If uncertain, say so honestly rather than guessing.
- Do NOT use bullet points, headers, or labels. Write as natural flowing prose.
- Return ONLY the response text — no JSON, no markdown, no preamble.''';
    }

    // Build message content — multimodal when image is present.
    final List<dynamic> messageContent;
    if (hasImage) {
      final b64 = base64Encode(imageBytes);
      messageContent = [
        {'type': 'text',      'text': prompt},
        {'type': 'image_url', 'image_url': {'url': 'data:$mimeType;base64,$b64'}},
      ];
    } else {
      messageContent = [{'type': 'text', 'text': prompt}];
    }

    // Images: use fast GPT-4o models — smaller payload, no scraping, reliable multimodal.
    // Text:   try Claude Sonnet first for richer reasoning, fall back to GPT-4o.
    final candidates = hasImage
        ? const ['openai/gpt-4o', 'openai/gpt-4o-mini']
        : const [
            'anthropic/claude-3.5-sonnet',
            'anthropic/claude-3-5-sonnet',
            'openai/gpt-4o',
          ];
    final timeoutSecs = hasImage ? 30 : 55;

    for (final model in candidates) {
      try {
        final res = await http.post(
          Uri.parse(_kUrl),
          headers: {
            'Authorization': 'Bearer $_kApiKey',
            'Content-Type':  'application/json',
            'HTTP-Referer':  'https://credexa.app',
            'X-Title':       'Credexa',
          },
          body: jsonEncode({
            'model':       model,
            'messages':    [{'role': 'user', 'content': messageContent}],
            'temperature': 0.1,
            'max_tokens':  500,
          }),
        ).timeout(Duration(seconds: timeoutSecs));

        if (res.statusCode != 200) continue; // try next model

        final body    = jsonDecode(res.body) as Map<String, dynamic>;
        final choices = body['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;

        // OpenRouter normalises Claude's array content to a string, but handle
        // both formats defensively.
        final raw = choices[0]['message']['content'];
        final text = raw is String
            ? raw
            : (raw as List)
                .map((c) => (c as Map)['text'] as String? ?? '')
                .join('');

        if (text.trim().isNotEmpty) return text.trim();
      } catch (_) {
        continue; // network/parse error — try next model
      }
    }

    throw Exception('all models failed');
  }
}
