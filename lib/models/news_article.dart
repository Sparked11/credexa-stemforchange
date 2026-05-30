class NewsArticle {
  final String id;
  final String title;
  final String description;
  final String content;
  final String imageUrl;
  final String source;
  final DateTime publishedAt;
  final String url;
  final String category;
  final int ageRating; // 13+, 15+, 18+

  NewsArticle({
    required this.id,
    required this.title,
    required this.description,
    required this.content,
    required this.imageUrl,
    required this.source,
    required this.publishedAt,
    required this.url,
    required this.category,
    required this.ageRating,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      id: json['id'] as String? ?? json['url'] as String? ?? '',
      title: json['title'] as String? ?? 'No title',
      description: json['description'] as String? ?? '',
      content: json['content'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      source: json['source'] as String? ?? 'Unknown',
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? '') ?? DateTime.now(),
      url: json['url'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      ageRating: json['ageRating'] as int? ?? 13,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'content': content,
      'imageUrl': imageUrl,
      'source': source,
      'publishedAt': publishedAt.toIso8601String(),
      'url': url,
      'category': category,
      'ageRating': ageRating,
    };
  }
}
