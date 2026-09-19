import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/news_article.dart';

class NewsService {
  /// True when the last result came from an old cache because the network failed.
  static bool servedStale = false;

  static const _baseUrl = 'https://credexa-tawny.vercel.app/api/news';
  static const _cacheTtl = Duration(hours: 24);

  static Future<List<NewsArticle>> fetchTeenNews({
    String category = 'general',
    int pageSize = 10,
  }) =>
      _fetchWithCache(category: category, pageSize: pageSize);

  static Future<List<NewsArticle>> fetchNewsByCategory(String category) =>
      _fetchWithCache(category: category);

  static Future<List<NewsArticle>> searchNews(String query) async {
    final articles = await _fetchWithCache(category: 'general');
    if (query.trim().isEmpty) return articles;
    final q = query.toLowerCase();
    return articles
        .where((a) =>
            a.title.toLowerCase().contains(q) ||
            a.description.toLowerCase().contains(q))
        .toList();
  }

  static Future<List<NewsArticle>> _fetchWithCache({
    String category = 'general',
    int pageSize = 10,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'news_$category';
    final tsKey = 'news_ts_$category';

    // Return cached data if still fresh
    final cachedJson = prefs.getString(cacheKey);
    final cachedTs = prefs.getString(tsKey);
    if (cachedJson != null && cachedTs != null) {
      final ts = DateTime.tryParse(cachedTs);
      if (ts != null && DateTime.now().difference(ts) < _cacheTtl) {
        return _parseList(cachedJson);
      }
    }

    // Fetch fresh from backend
    Object failure = Exception('News is unavailable right now.');
    try {
      final uri = Uri.parse('$_baseUrl?category=$category&pageSize=$pageSize');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final articles = (body['articles'] as List)
            .map((e) => NewsArticle.fromJson(e as Map<String, dynamic>))
            .toList();
        // Persist to local cache
        await prefs.setString(
            cacheKey, jsonEncode(articles.map((a) => a.toJson()).toList()));
        await prefs.setString(tsKey, DateTime.now().toIso8601String());
        servedStale = false;
        return articles;
      }
      failure = Exception('News service returned ${response.statusCode}');
    } catch (e) {
      failure = e;
    }

    // Fall back to stale cache rather than failing, but let the UI say so.
    if (cachedJson != null) {
      servedStale = true;
      return _parseList(cachedJson);
    }
    servedStale = false;
    throw failure;
  }

  static List<NewsArticle> _parseList(String json) {
    return (jsonDecode(json) as List)
        .map((e) => NewsArticle.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
