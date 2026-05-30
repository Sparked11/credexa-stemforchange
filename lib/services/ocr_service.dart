import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../app_config.dart';

class OcrService {
  static const _apiKey = kOpenRouterApiKey;
  static const _apiUrl = 'https://openrouter.ai/api/v1/chat/completions';

  // Social platforms whose og:image is a photo/video frame, not a text slide.
  // For these we trust og:description + og:title instead of trying to OCR the image.
  static const _skipImageOcrDomains = {
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
    'tiktok.com',
    'www.tiktok.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'threads.net',
    'www.threads.net',
    'youtube.com',
    'www.youtube.com',
    'youtu.be',
  };

  // Refusal phrases returned by the model when it declines to process an image.
  static const _refusalPrefixes = [
    "i'm sorry",
    "i am sorry",
    "i can't assist",
    "i cannot assist",
    "i'm unable",
    "i am unable",
    "i can't help",
    "i cannot help",
    "sorry, but i",
    "sorry, i can",
    "i don't feel comfortable",
    "i'm not able",
  ];

  /// OCR an image — returns all visible text, or empty string on refusal/failure.
  static Future<String> extractText(Uint8List bytes, String mimeType) async {
    final b64 = base64Encode(bytes);
    final resp = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'openai/gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content':
                'You are an OCR tool. Your only job is to read and return text '
                'visible in images. Always respond with the extracted text only.',
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'data:$mimeType;base64,$b64'},
              },
              {
                'type': 'text',
                'text':
                    'Transcribe every piece of text visible in this image — '
                    'captions, headlines, usernames, hashtags, comments, labels. '
                    'Output ONLY the raw text, nothing else.',
              },
            ],
          }
        ],
        'max_tokens': 700,
        'temperature': 0.0,
      }),
    ).timeout(const Duration(seconds: 15));

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final text =
        ((data['choices'] as List?)?.first['message']['content'] as String?)
                ?.trim() ??
            '';

    // Treat model refusals as empty so callers fall back gracefully.
    final lower = text.toLowerCase();
    if (_refusalPrefixes.any((p) => lower.startsWith(p))) return '';
    return text;
  }

  /// Fetch a social-media/news URL and extract post content.
  ///
  /// For social platforms (Instagram, X, TikTok, etc.) the og:image is a
  /// photo/video thumbnail — OCR-ing it just gets the model to refuse. Instead
  /// we use og:description + og:title, which already contain the caption/headline.
  ///
  /// For news/blog URLs we do try to OCR the og:image as it is often a slide or
  /// infographic with embedded text worth reading.
  static Future<String> extractFromUrl(String pageUrl) async {
    final uri = Uri.tryParse(pageUrl);
    final host = uri?.host.toLowerCase() ?? '';
    final isSocialPlatform = _skipImageOcrDomains.contains(host);

    // 1. Fetch the HTML
    final resp = await http
        .get(
          Uri.parse(pageUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (compatible; Twitterbot/1.0)',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(const Duration(seconds: 15));

    final html = resp.body;

    // 2. Parse Open Graph / Twitter Card tags
    final ogTitle = _meta(html, ['og:title', 'twitter:title']) ?? '';
    final ogDesc =
        _meta(html, ['og:description', 'twitter:description']) ?? '';
    final ogImage =
        _meta(html, ['og:image', 'twitter:image:src', 'twitter:image']) ?? '';

    // 3a. Social platforms — skip image OCR, use text metadata directly.
    if (isSocialPlatform) {
      final combined =
          [ogTitle, ogDesc].where((s) => s.isNotEmpty).join('\n\n');
      return combined;
    }

    // 3b. Non-social URLs — try OCR on the og:image (infographics, article headers).
    if (ogImage.isNotEmpty) {
      try {
        final imgResp = await http
            .get(Uri.parse(ogImage))
            .timeout(const Duration(seconds: 15));
        if (imgResp.statusCode == 200) {
          final mime =
              imgResp.headers['content-type']?.split(';').first ?? 'image/jpeg';
          final ocrText = await extractText(imgResp.bodyBytes, mime);
          if (ocrText.trim().isNotEmpty) return ocrText.trim();
        }
      } catch (_) {}
    }

    // 4. Fall back to OG text metadata
    return [ogTitle, ogDesc].where((s) => s.isNotEmpty).join('\n\n');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String? _meta(String html, List<String> keys) {
    for (final key in keys) {
      for (final re in [
        RegExp(
            'property=["\']${RegExp.escape(key)}["\'][^>]+content=["\']([^"\']*)["\']',
            caseSensitive: false),
        RegExp(
            'content=["\']([^"\']*)["\'][^>]+property=["\']${RegExp.escape(key)}["\']',
            caseSensitive: false),
        RegExp(
            'name=["\']${RegExp.escape(key)}["\'][^>]+content=["\']([^"\']*)["\']',
            caseSensitive: false),
        RegExp(
            'content=["\']([^"\']*)["\'][^>]+name=["\']${RegExp.escape(key)}["\']',
            caseSensitive: false),
      ]) {
        final m = re.firstMatch(html);
        if (m != null) {
          final val = m.group(1) ?? '';
          if (val.isNotEmpty) return _decode(val);
        }
      }
    }
    return null;
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ');
}
