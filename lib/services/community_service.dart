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

  // Blocked user ids for the signed-in account — messages from these users are
  // hidden. Loaded via [loadModeration]; kept in memory for synchronous
  // filtering in [messagesStream].
  static final Set<String> _blockedUsers = {};

  /// Local cache key, scoped per account so signing in as someone else on a
  /// shared device doesn't inherit the previous account's blocks. Never falls
  /// back to the unscoped key: that key is shared by definition, so reading it
  /// for any account leaks blocks between accounts.
  static String _blockedKey(String uid) => '$_kBlockedKey.$uid';

  /// Loads the signed-in account's blocked-user list. Call at hub startup, and
  /// again after an account switch.
  ///
  /// Reads the on-device cache first so filtering works instantly and offline,
  /// then merges the copy stored on the user's Firestore document so blocks
  /// follow the account to a new device or a reinstall. The merge is a union —
  /// a block is never silently dropped because one side hadn't synced yet.
  static Future<void> loadModeration() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final p = await SharedPreferences.getInstance();

    // Signed out: no account owns any blocks, so filter nothing. Clearing here
    // also stops one account's list surviving in memory into the next sign-in.
    if (uid == null) {
      _blockedUsers.clear();
      // Retire the pre-scoping key; leaving it would let it be read again.
      await p.remove(_kBlockedKey);
      return;
    }

    _blockedUsers
      ..clear()
      ..addAll(p.getStringList(_blockedKey(uid)) ?? const <String>[]);

    // Drop the old shared key so no account can pick up another's blocks.
    await p.remove(_kBlockedKey);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      final remote = <String>{
        for (final e in (snap.data()?['blockedUsers'] as List<dynamic>? ?? []))
          e.toString(),
      };
      if (!remote.every(_blockedUsers.contains)) {
        _blockedUsers.addAll(remote);
        await p.setStringList(_blockedKey(uid), _blockedUsers.toList());
      }
    } catch (_) {
      // Offline or unreachable — the cached list still applies.
    }
  }

  static bool isBlocked(String? userId) =>
      userId != null && _blockedUsers.contains(userId);

  static List<String> get blockedUsers => _blockedUsers.toList();

  /// Blocks a user so their messages are hidden on this device, and notifies
  /// the developer (App Store Guideline 1.2 requires blocking to both remove
  /// the content from the feed instantly and report it to us). [messageId] and
  /// [messageText] identify the content that prompted the block, so it can be
  /// reviewed and removed within 24 hours.
  static Future<void> blockUser(String userId,
      {String? messageId, String? messageText}) async {
    _blockedUsers.add(userId);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_blockedKey(uid), _blockedUsers.toList());
    }
    await _syncBlockedUser(uid, userId, blocked: true);
    await _fileModerationReport(
      kind: 'block',
      offendingUserId: userId,
      messageId: messageId,
      messageText: messageText,
    );
  }

  /// Mirrors a block onto the user's Firestore document so it survives a
  /// reinstall and follows them to other devices. Best-effort by design: the
  /// local block has already taken effect, and failing to sync must never
  /// leave the blocked user visible.
  static Future<void> _syncBlockedUser(String? uid, String userId,
      {required bool blocked}) async {
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'blockedUsers':
              blocked ? FieldValue.arrayUnion([userId])
                      : FieldValue.arrayRemove([userId]),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Swallowed deliberately — see doc comment.
    }
  }

  /// Writes a moderation record the developer can act on. Best-effort: a
  /// failure here must never stop the block or report from taking effect
  /// locally, which is what the user sees.
  static Future<void> _fileModerationReport({
    required String kind,
    String? offendingUserId,
    String? messageId,
    String? messageText,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('moderation_reports').add({
        'kind':            kind, // 'report' | 'block'
        'offendingUserId': offendingUserId,
        'messageId':       messageId,
        'messageText':     messageText,
        'reportedBy':      FirebaseAuth.instance.currentUser?.uid,
        'createdAt':       FieldValue.serverTimestamp(),
        'status':          'open',
      });
    } catch (_) {
      // Swallowed deliberately — see doc comment.
    }
  }

  static Future<void> unblockUser(String userId) async {
    _blockedUsers.remove(userId);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_blockedKey(uid), _blockedUsers.toList());
    }
    await _syncBlockedUser(uid, userId, blocked: false);
  }

  /// Flags a message as objectionable. Records the reporter (so double-reports
  /// don't inflate the count) and bumps the report counter; once
  /// [_kReportHideThreshold] distinct users report it, [messagesStream] hides it
  /// from everyone automatically.
  static Future<void> reportMessage(String messageId,
      {String? offendingUserId, String? messageText}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _fileModerationReport(
      kind: 'report',
      offendingUserId: offendingUserId,
      messageId: messageId,
      messageText: messageText,
    );
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
        .map((s) =>
            applyModeration(s.docs.map(CommunityMessage.fromFirestore).toList()));
  }

  /// Filters a timestamp-ordered list down to what this viewer may see.
  ///
  /// An AI analysis is stored as its own document, one second after the question
  /// it answers. Hiding only the question would strand the answer — sources and
  /// all — under no question at all, so a hidden question takes the AI reply
  /// that directly follows it with it.
  static List<CommunityMessage> applyModeration(
      List<CommunityMessage> ordered) {
    final out = <CommunityMessage>[];
    var i = 0;
    while (i < ordered.length) {
      final m = ordered[i];
      if (isHidden(m)) {
        // Skip the message, plus its AI answer when this was a question.
        if (m.type != MessageType.ai &&
            i + 1 < ordered.length &&
            ordered[i + 1].type == MessageType.ai) {
          i += 2;
          continue;
        }
        i += 1;
        continue;
      }
      out.add(m);
      i += 1;
    }
    return out;
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
    // Model ids must match OpenRouter's catalog exactly; a retired id 404s and
    // silently falls through to the next candidate.
    // Claude leads on images: GPT-4o intermittently refuses to analyse photos of
    // real political figures, which is exactly the misinformation this feature
    // exists to check. Refusals fall through to the next candidate below.
    final candidates = hasImage
        ? const [
            'anthropic/claude-sonnet-5',
            'openai/gpt-4o',
            'openai/gpt-4o-mini',
          ]
        : const [
            'anthropic/claude-sonnet-5',
            'openai/gpt-4o',
          ];
    final timeoutSecs = hasImage ? 45 : 55;

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

        final out = text.trim();
        // A refusal is a 200 OK with useless prose ("I'm sorry, I can't help
        // with that."). Treat it like a failure so the next candidate gets a
        // turn instead of the refusal being shown to the user as the verdict.
        if (out.isNotEmpty && !_looksLikeRefusal(out)) return out;
      } catch (_) {
        continue; // network/parse error — try next model
      }
    }

    throw Exception('all models failed');
  }

  /// True when a model declined instead of answering. Deliberately narrow: only
  /// short replies count, so a real fact-check that happens to quote "I'm sorry"
  /// is never discarded.
  static bool _looksLikeRefusal(String text) {
    if (text.length > 240) return false;
    final t = text.toLowerCase();
    const markers = [
      "i'm sorry, i can't",
      "i'm sorry, but i can't",
      "i cannot help with that",
      "i can't help with that",
      "i'm unable to help",
      "i can't assist with that",
      "i cannot assist with that",
      "unable to assist with that",
    ];
    return markers.any((m) => t.contains(m));
  }
}
