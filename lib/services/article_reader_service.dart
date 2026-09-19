import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class ArticleBlock {
  final String text;
  final bool isHeading;
  const ArticleBlock(this.text, {this.isHeading = false});
}

/// Fetches an article page and extracts its readable text.
/// Returns null when the page can't be read (blocked, paywalled, not an article).
class ArticleReaderService {
  static final Map<String, List<ArticleBlock>?> _cache = {};

  static const _userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static const _noise = [
    'script', 'style', 'noscript', 'nav', 'header', 'footer', 'aside',
    'form', 'iframe', 'svg', 'button', 'figcaption',
  ];

  static const _boilerplate = [
    'advertisement', 'sign up', 'subscribe', 'newsletter', 'cookie',
    'all rights reserved', 'follow us', 'share this', 'read more:',
    'click here', 'privacy policy',
  ];

  static Future<List<ArticleBlock>?> fetch(String url) async {
    if (url.isEmpty) return null;
    if (_cache.containsKey(url)) return _cache[url];

    List<ArticleBlock>? result;
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        result = _extract(body);
      }
    } catch (_) {
      result = null;
    }
    _cache[url] = result;
    return result;
  }

  static List<ArticleBlock>? _extract(String htmlSource) {
    final doc = html_parser.parse(htmlSource);
    for (final tag in _noise) {
      for (final el in doc.querySelectorAll(tag)) {
        el.remove();
      }
    }

    final candidates = <dom.Element>[
      ...doc.querySelectorAll('article'),
      ...doc.querySelectorAll('[itemprop="articleBody"]'),
      ...doc.querySelectorAll('main'),
    ];
    dom.Element? root;
    var best = 0;
    for (final c in candidates) {
      final len = c
          .querySelectorAll('p')
          .fold<int>(0, (sum, p) => sum + p.text.trim().length);
      if (len > best) {
        best = len;
        root = c;
      }
    }
    root ??= doc.body;
    if (root == null) return null;

    final blocks = <ArticleBlock>[];
    final seen = <String>{};
    for (final el in root.querySelectorAll('p, h2, h3')) {
      final text = el.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty || !seen.add(text)) continue;
      final isHeading = el.localName != 'p';
      if (isHeading) {
        if (text.length > 3 && text.length < 120) {
          blocks.add(ArticleBlock(text, isHeading: true));
        }
        continue;
      }
      if (text.length < 40) continue;
      final lower = text.toLowerCase();
      if (text.length < 140 && _boilerplate.any(lower.contains)) continue;
      blocks.add(ArticleBlock(text));
    }

    // Drop headings that aren't followed by body text.
    final cleaned = <ArticleBlock>[];
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].isHeading &&
          (i == blocks.length - 1 || blocks[i + 1].isHeading)) {
        continue;
      }
      cleaned.add(blocks[i]);
    }

    final paragraphs = cleaned.where((b) => !b.isHeading).toList();
    final totalChars = paragraphs.fold<int>(0, (s, b) => s + b.text.length);
    if (paragraphs.length < 3 || totalChars < 500) return null;
    return cleaned;
  }
}
