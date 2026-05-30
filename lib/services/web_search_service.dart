import 'package:http/http.dart' as http;

/// Searches Google News RSS for recent articles related to a claim.
/// Returns formatted headlines the AI can use as grounded, dated context.
/// Falls back to empty string on any network failure so callers proceed cleanly.
class WebSearchService {
  static Future<String> quickFact(String claim) async {
    // Run both searches in parallel; combine whatever succeeds.
    final results = await Future.wait([
      _googleNewsRss(claim),
      _googleNewsRss(_extractKeyPhrase(claim)), // second pass with shorter query
    ]);

    final unique = <String>{};
    final headlines = <String>[];
    for (final block in results) {
      for (final line in block.split('\n')) {
        if (line.isNotEmpty && unique.add(line)) headlines.add(line);
      }
    }
    return headlines.take(6).join('\n');
  }

  // Strips stopwords to get a tighter search query (e.g. job statistics by topic).
  static String _extractKeyPhrase(String claim) {
    const stopwords = {
      'the', 'a', 'an', 'is', 'it', 'in', 'on', 'at', 'to', 'of',
      'and', 'or', 'for', 'with', 'this', 'that', 'are', 'was', 'were',
      'have', 'has', 'had', 'will', 'be', 'been', 'its', 'as', 'by',
    };
    final words = claim
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopwords.contains(w))
        .take(6)
        .toList();
    return words.join(' ');
  }

  static Future<String> _googleNewsRss(String query) async {
    if (query.trim().isEmpty) return '';
    try {
      final encoded = Uri.encodeComponent(query.trim());
      final uri = Uri.parse(
        'https://news.google.com/rss/search?q=$encoded&hl=en-US&gl=US&ceid=US:en',
      );
      final resp = await http.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (compatible; CredeXa/1.0; +https://credexa.app)',
        'Accept': 'application/rss+xml, application/xml, text/xml',
      }).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return '';
      final items = _parseRss(resp.body);
      if (items.isEmpty) return '';

      return items.take(5).map((item) {
        final title  = item['title']   ?? '';
        final source = item['source']  ?? '';
        final date   = item['pubDate'] ?? '';
        if (title.isEmpty) return '';
        final parts = <String>[];
        if (source.isNotEmpty) parts.add(source);
        if (date.isNotEmpty)   parts.add(date);
        return '• $title${parts.isNotEmpty ? " [${parts.join(', ')}]" : ""}';
      }).where((s) => s.isNotEmpty).join('\n');
    } catch (_) {
      return '';
    }
  }

  /// Returns up to [max] structured article items with real, scrapeable URLs.
  ///
  /// Uses Bing News RSS as the primary source because its `<link>` tags contain
  /// the actual article URL (no redirect), so [scrapeArticles] can fetch real
  /// content. Google News RSS is kept as a fallback; its redirect URLs are only
  /// usable for headline text, not reliable scraping.
  static Future<List<Map<String, String>>> searchWithLinks(
    String claim, {
    int max = 3,
  }) async {
    // Trim to ≤200 chars so the search engine gets the most specific part of
    // the claim rather than a truncated sentence that loses its meaning.
    final q = claim.trim().length > 200
        ? claim.trim().substring(0, 200)
        : claim.trim();

    // Bing News RSS returns actual article URLs — preferred for scraping.
    final bingItems = await _bingNewsRssItems(q);
    if (bingItems.isNotEmpty) return bingItems.take(max).toList();

    // Fallback: Google News RSS (links are Google redirects; scraping limited).
    final results = await Future.wait([
      _googleNewsRssItems(q),
      _googleNewsRssItems(_extractKeyPhrase(q)),
    ]);
    final seen  = <String>{};
    final items = <Map<String, String>>[];
    for (final batch in results) {
      for (final item in batch) {
        final title = item['title'] ?? '';
        if (title.isNotEmpty && seen.add(title)) items.add(item);
      }
    }
    return items.take(max).toList();
  }

  /// Fetches Bing News RSS for [query] and returns article items.
  /// Bing puts the actual article URL in the `<link>` tag — no redirect.
  static Future<List<Map<String, String>>> _bingNewsRssItems(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final encoded = Uri.encodeComponent(query.trim());
      final uri = Uri.parse(
        'https://www.bing.com/news/search?q=$encoded&format=RSS',
      );
      final resp = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/124.0 Safari/537.36',
        'Accept': 'application/rss+xml, application/xml, text/xml',
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final items = _parseRss(resp.body);
      // Keep only items whose URL is a real article link (not a Bing search page).
      return items
          .where((i) => (i['url'] ?? '').startsWith('http') &&
              !(i['url'] ?? '').contains('bing.com/search'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, String>>> _googleNewsRssItems(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final encoded = Uri.encodeComponent(query.trim());
      final uri = Uri.parse(
        'https://news.google.com/rss/search?q=$encoded&hl=en-US&gl=US&ceid=US:en',
      );
      final resp = await http.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (compatible; CredeXa/1.0; +https://credexa.app)',
        'Accept': 'application/rss+xml, application/xml, text/xml',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      return _parseRss(resp.body);
    } catch (_) {
      return [];
    }
  }

  /// Fetches up to [max] article URLs in parallel and extracts a plain-text
  /// excerpt from each page body (strips tags, scripts, styles).
  ///
  /// When [claimHint] is provided, excerpts that contain none of the claim's
  /// keywords are discarded — this filters out error pages, paywalls, and
  /// unrelated redirect targets that would mislead the AI models.
  static Future<List<Map<String, String>>> scrapeArticles(
    List<Map<String, String>> articles, {
    int max = 3,
    String? claimHint,
  }) async {
    final claimWords = claimHint != null
        ? _extractKeyPhrase(claimHint)
            .split(' ')
            .where((w) => w.length > 2)
            .toList()
        : <String>[];

    final targets = articles.take(max).toList();
    final futures = targets.map((a) async {
      final url = a['url'] ?? '';
      if (url.isEmpty) return null;
      final excerpt = await _scrapeUrl(url);

      // Discard excerpts that share no keywords with the claim — they are
      // almost certainly from an error page, consent wall, or wrong redirect.
      if (claimWords.isNotEmpty && excerpt.isNotEmpty) {
        final lower = excerpt.toLowerCase();
        final hasRelevantContent = claimWords.any((w) => lower.contains(w));
        if (!hasRelevantContent) return null;
      }
      // Also discard suspiciously short excerpts (error pages, blank pages).
      if (excerpt.length < 80) return null;

      return <String, String>{
        'title':   a['title']  ?? '',
        'source':  a['source'] ?? '',
        'url':     url,
        'excerpt': excerpt,
      };
    });
    final results = await Future.wait(futures);
    return results.whereType<Map<String, String>>().toList();
  }

  static Future<String> _scrapeUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return '';
      final resp = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/124.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(const Duration(seconds: 7));
      if (resp.statusCode != 200) return '';
      final raw = resp.body;
      final text = raw
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>',
              dotAll: true, caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>',
              dotAll: true, caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'&nbsp;'),  ' ')
          .replaceAll(RegExp(r'&amp;'),   '&')
          .replaceAll(RegExp(r'&lt;'),    '<')
          .replaceAll(RegExp(r'&gt;'),    '>')
          .replaceAll(RegExp(r'&quot;'),  '"')
          .replaceAll(RegExp(r'\s+'),     ' ')
          .trim();
      // Keep first 800 chars — enough context, keeps prompt lean.
      return text.length > 800 ? '${text.substring(0, 800)}…' : text;
    } catch (_) {
      return '';
    }
  }

  static List<Map<String, String>> _parseRss(String xml) {
    final items   = <Map<String, String>>[];
    final itemRx  = RegExp(r'<item>(.*?)</item>',   dotAll: true);
    for (final m in itemRx.allMatches(xml)) {
      final chunk = m.group(1) ?? '';
      final title  = _tag(chunk, 'title');
      final source = _tag(chunk, 'source');
      final date   = _shortDate(_tag(chunk, 'pubDate'));
      // Google News RSS puts the redirect URL in both <link> and <guid>.
      // Fall back to <guid> if the <link> tag is missing or self-closing.
      final rawUrl = _rawLink(chunk);
      final url    = rawUrl.isNotEmpty ? rawUrl : _tag(chunk, 'guid');
      if (title.isNotEmpty) {
        items.add({
          'title': title, 'source': source, 'pubDate': date, 'url': url,
        });
      }
    }
    return items;
  }

  // Extracts the raw <link> URL without HTML-cleaning (preserves the URL intact).
  static String _rawLink(String xml) {
    final rx = RegExp(r'<link>(.*?)</link>', dotAll: true);
    return rx.firstMatch(xml)?.group(1)?.trim() ?? '';
  }

  static String _tag(String xml, String tag) {
    final rx    = RegExp('<$tag[^>]*>(.*?)</$tag>', dotAll: true);
    final match = rx.firstMatch(xml);
    if (match == null) return '';
    return _clean(match.group(1) ?? '');
  }

  static String _clean(String raw) {
    return raw
        .replaceAllMapped(
            RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true), (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .trim();
  }

  // Shortens "Mon, 26 May 2026 04:12:00 GMT" → "May 26 2026"
  static String _shortDate(String rfc822) {
    if (rfc822.isEmpty) return '';
    try {
      final parts = rfc822.split(' ');
      if (parts.length >= 4) return '${parts[2]} ${parts[1]} ${parts[3]}';
    } catch (_) {}
    return rfc822;
  }
}
