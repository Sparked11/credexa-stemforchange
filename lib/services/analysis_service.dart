import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/analysis_result.dart';
import 'web_search_service.dart';

class AnalysisService {
  static const _url =
      'https://credexa-tawny.vercel.app/api/analyzeClam';

  /// Posts to the analysis backend with a single automatic retry on
  /// [TimeoutException] or [SocketException] (a 3-second delay between
  /// attempts). The original error is rethrown if the retry also fails.
  static Future<http.Response> _postWithRetry({
    required Object body,
    required Duration timeout,
  }) async {
    Future<http.Response> attempt() => http
        .post(
          Uri.parse(_url),
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
          },
          body: body,
        )
        .timeout(timeout);

    try {
      return await attempt();
    } on TimeoutException {
      await Future<void>.delayed(const Duration(seconds: 3));
      return await attempt();
    } on SocketException {
      await Future<void>.delayed(const Duration(seconds: 3));
      return await attempt();
    }
  }

  static Future<AnalysisResult> analyze(String claim) async {
    final response = await _postWithRetry(
      body: jsonEncode({'claim': claim}),
      timeout: const Duration(seconds: 90),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Analysis failed (${response.statusCode})');
    }
    return AnalysisResult.fromJson(body);
  }

  /// Builds the evidence block that is injected into both Round 1 and Round 2
  /// prompts. Uses full scraped article text when available; falls back to RSS
  /// headlines so callers always get something useful.
  static String _webEvidenceBlock(
    List<Map<String, String>> scraped,
    String fallbackHeadlines,
  ) {
    if (scraped.isNotEmpty) {
      final buf = StringBuffer(
        'SCRAPED WEB ARTICLES '
        '(actual article content retrieved today — treat as PRIMARY evidence):\n',
      );
      for (int i = 0; i < scraped.length; i++) {
        final a       = scraped[i];
        final title   = a['title']   ?? '';
        final source  = a['source']  ?? 'Unknown source';
        final excerpt = a['excerpt'] ?? '';
        buf.writeln('[${i + 1}] $source — $title');
        if (excerpt.isNotEmpty) buf.writeln('    $excerpt');
      }
      return buf.toString().trimRight();
    }
    if (fallbackHeadlines.isNotEmpty) {
      return 'LIVE NEWS HEADLINES '
          '(from Google News, retrieved today — use as PRIMARY evidence):\n'
          '$fallbackHeadlines';
    }
    return 'No live web results available — reason carefully about what is '
        'plausible given the date above, and express uncertainty rather than '
        'declaring the claim false if you cannot confirm it.';
  }

  /// Scores a claim against scraped article text (keyword matching against full
  /// body content, not just titles). Falls back to [fallbackHeadlines] if no
  /// articles were scraped. Returns a [ModelResult] for the UI panel.
  static ModelResult _buildWebScrapeResult(
    String claim,
    List<Map<String, String>> scraped,
    String fallbackHeadlines,
  ) {
    final claimWords = _keyWords(claim);

    if (scraped.isEmpty && fallbackHeadlines.isEmpty) {
      return ModelResult(
        model:            'Web Search',
        credibilityScore: 45,
        verdict:          'UNCERTAIN',
        confidence:       'LOW',
        reasoning:        'No web content could be retrieved for this claim.',
        flags:            [],
      );
    }

    int matchCount = 0;
    final evidenceLines = <String>[];

    if (scraped.isNotEmpty) {
      for (final a in scraped) {
        final combined = '${a['title'] ?? ''} ${a['excerpt'] ?? ''}'.toLowerCase();
        final hits = claimWords.where((w) => combined.contains(w)).length;
        matchCount += hits;
        final title  = a['title']  ?? '';
        final source = a['source'] ?? '';
        final snip   = (a['excerpt'] ?? '');
        final preview = snip.length > 160 ? '${snip.substring(0, 160)}…' : snip;
        if (title.isNotEmpty) {
          evidenceLines.add('[$source] $title${preview.isNotEmpty ? " — $preview" : ""}');
        }
      }
    } else {
      for (final line in fallbackHeadlines.split('\n').where((l) => l.isNotEmpty)) {
        if (claimWords.any((w) => line.toLowerCase().contains(w))) matchCount++;
        evidenceLines.add(line);
      }
    }

    final int score;
    final String verdict;
    final String confidence;

    if (matchCount >= 6) {
      score = 78; verdict = 'CREDIBLE';    confidence = 'HIGH';
    } else if (matchCount >= 3) {
      score = 65; verdict = 'CREDIBLE';    confidence = 'MEDIUM';
    } else if (matchCount >= 1) {
      score = 50; verdict = 'UNCERTAIN';   confidence = 'LOW';
    } else {
      score = 35; verdict = 'MISLEADING';  confidence = 'LOW';
    }

    return ModelResult(
      model:            'Web Search',
      credibilityScore: score,
      verdict:          verdict,
      confidence:       confidence,
      reasoning:        evidenceLines.join('\n'),
      flags:            [],
    );
  }

  /// Fetches and scrapes real web articles, then runs a two-round deliberation:
  ///
  ///   Step 0  — [searchWithLinks] finds article URLs; [scrapeArticles] fetches
  ///             full body text (800-char excerpts). Falls back to RSS headlines
  ///             if scraping fails.
  ///
  ///   Round 1 — three AI models independently score the claim using today's
  ///             date and the scraped article excerpts as primary evidence.
  ///
  ///   Round 2 — each model receives: (a) peer AI verdicts from Round 1 and
  ///             (b) the objective Web Search keyword-match verdict. Models must
  ///             reconsider before finalising. The Web Search result is appended
  ///             to the returned [AnalysisResult] and its score is blended (25 %)
  ///             into the synthesis final score.
  static Future<AnalysisResult> analyzeWithSearch(String claim) async {
    final today   = DateTime.now();
    final dateStr = '${_monthName(today.month)} ${today.day}, ${today.year}';

    // ── Step 0: scrape real articles ──────────────────────────────────────────
    final articleItems = await WebSearchService.searchWithLinks(claim, max: 5);
    final scraped      = await WebSearchService.scrapeArticles(articleItems, max: 3, claimHint: claim);
    // RSS headline fallback only when scraping yielded nothing.
    final fallbackHeadlines =
        scraped.isEmpty ? await WebSearchService.quickFact(claim) : '';

    final evidenceBlock = _webEvidenceBlock(scraped, fallbackHeadlines);
    final webResult     = _buildWebScrapeResult(claim, scraped, fallbackHeadlines);

    // ── Round 1: independent AI verdicts ─────────────────────────────────────
    final round1Prompt = '''CLAIM TO FACT-CHECK:
$claim

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ANALYSIS CONTEXT (read before scoring)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Today's date: $dateStr

$evidenceBlock

SCORING RULES:
1. If multiple article sources CONFIRM the claim → score 65–90 (credible).
2. If articles CONTRADICT the claim with data → score 10–40 (likely false).
3. If articles are AMBIGUOUS or only partially related → score 40–65 (uncertain).
4. If NO web results were found → score 40–60 and explain the uncertainty.
5. NEVER state a political figure does or does not hold office based solely on training data — the date above is authoritative.
6. NEVER call a claim "false" purely because it falls outside your training cutoff date.''';

    final round1 = await analyze(round1Prompt);

    // ── Round 2: deliberation — AI peers + objective Web Search verdict ────────
    final peerSummary = StringBuffer(
      'PEER VERDICTS FROM ROUND 1 — read ALL carefully before finalising your score:\n',
    );

    for (final r in round1.modelResults) {
      if (r.failed) continue;
      peerSummary.writeln('''
  ┌─ ${r.model} (AI model)
  │  Score:     ${r.credibilityScore}/100
  │  Verdict:   ${r.verdict}  (confidence: ${r.confidence})
  │  Reasoning: ${r.reasoning}
  └─''');
    }

    // Web Search result as an objective, non-LLM peer signal
    final webSnippet = webResult.reasoning.split('\n').take(4).join(' | ');
    peerSummary.writeln('''
  ┌─ Web Search  ★ OBJECTIVE SIGNAL — keyword match against scraped article text
  │  Score:     ${webResult.credibilityScore}/100
  │  Verdict:   ${webResult.verdict}  (confidence: ${webResult.confidence})
  │  Evidence:  $webSnippet
  └─''');

    final round2Prompt = '''CLAIM TO FACT-CHECK:
$claim

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ANALYSIS CONTEXT (read before scoring)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Today's date: $dateStr

$evidenceBlock

$peerSummary
DELIBERATION INSTRUCTIONS:
You have now read peer AI verdicts AND an objective Web Search signal (keyword matches against scraped article bodies — not opinion).
• If the Web Search verdict contradicts your Round 1 score, you MUST explain why before keeping your score unchanged.
• If a peer AI's reasoning reveals evidence or logic you missed, update your score accordingly.
• Do NOT blindly copy a peer verdict — reason independently, then converge on the most accurate conclusion.
• The goal is collective truth. Correct peers if they are wrong; accept correction if you were wrong.

SCORING RULES:
1. If multiple article sources CONFIRM the claim → score 65–90 (credible).
2. If articles CONTRADICT the claim with data → score 10–40 (likely false).
3. If articles are AMBIGUOUS or only partially related → score 40–65 (uncertain).
4. If NO web results were found → score 40–60 and explain the uncertainty.
5. NEVER state a political figure does or does not hold office based solely on training data — the date above is authoritative.
6. NEVER call a claim "false" purely because it falls outside your training cutoff date.''';

    final round2 = await analyze(round2Prompt);

    // Blend Web Search score (25 %) into synthesis.
    final blendedScore =
        ((round2.synthesis.finalScore * 3 + webResult.credibilityScore) / 4).round();

    return AnalysisResult(
      modelResults: [...round2.modelResults, webResult],
      synthesis: Synthesis(
        finalScore:   blendedScore,
        finalVerdict: round2.synthesis.finalVerdict,
        agreements:   round2.synthesis.agreements,
        conflicts:    round2.synthesis.conflicts,
        flags:        round2.synthesis.flags,
        summary:      round2.synthesis.summary,
      ),
      extractedText: round2.extractedText,
      sourceUrl:     round2.sourceUrl,
    );
  }

  /// Derives a verdict from Google News RSS headlines only — no LLM call.
  /// Used by the real-time AR overlay so the Vercel backend is never hit
  /// during live scanning. The manual "Run AI Council Analysis" button still
  /// calls [analyzeWithSearch] for full LLM reasoning.
  static Future<AnalysisResult> analyzeRssOnly(String claim) async {
    final headlines = await WebSearchService.quickFact(claim);
    final lines     = headlines.split('\n').where((l) => l.isNotEmpty).toList();
    final words     = _keyWords(claim);
    int matches     = 0;
    for (final l in lines) {
      if (words.any((w) => l.toLowerCase().contains(w))) matches++;
    }
    final score   = lines.isEmpty ? 45 : matches >= 3 ? 70 : matches >= 1 ? 52 : 42;
    final verdict = score >= 65 ? 'CREDIBLE' : 'UNCERTAIN';
    final summary = lines.isEmpty
        ? 'No recent news headlines found.'
        : '$matches of ${lines.length} headlines matched claim keywords.';
    return AnalysisResult(
      modelResults: [
        ModelResult(
          model:            'Google News RSS',
          credibilityScore: score,
          verdict:          verdict,
          confidence:       matches >= 3 ? 'MEDIUM' : 'LOW',
          reasoning:        lines.isEmpty ? 'No headlines retrieved.' : lines.join('\n'),
          flags:            [],
        ),
      ],
      synthesis: Synthesis(
        finalScore:   score,
        finalVerdict: verdict,
        agreements:   [],
        conflicts:    [],
        flags:        [],
        summary:      summary,
      ),
    );
  }

  static List<String> _keyWords(String text) {
    const stop = {
      'the', 'a', 'an', 'is', 'it', 'in', 'on', 'at', 'to', 'of',
      'and', 'or', 'for', 'with', 'this', 'that', 'are', 'was', 'were',
      'have', 'has', 'had', 'will', 'be', 'been', 'its', 'as', 'by',
    };
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stop.contains(w))
        .toList();
  }

  static String _monthName(int m) => const [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ][m];

  static Future<AnalysisResult> analyzeImage(Uint8List bytes, String mimeType) async {
    final imageBase64 = base64Encode(bytes);
    final response = await _postWithRetry(
      body: jsonEncode({'imageBase64': imageBase64, 'mimeType': mimeType}),
      timeout: const Duration(seconds: 90),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Image analysis failed (${response.statusCode})');
    }
    return AnalysisResult.fromJson(body);
  }
}
