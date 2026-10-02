/// The visual format a quest's content is presented in — each renders as an
/// originally-designed mockup (never a real photo or scraped screenshot).
enum QuestFormat { post, headline, quote, chart }

QuestFormat questFormatFromString(String s) => switch (s) {
      'headline' => QuestFormat.headline,
      'quote' => QuestFormat.quote,
      'chart' => QuestFormat.chart,
      _ => QuestFormat.post,
    };

/// One bar/line series point set for a fabricated, deliberately-misleading
/// chart mockup (e.g. a truncated axis or cherry-picked timeframe).
class QuestChart {
  const QuestChart({
    required this.title,
    required this.xLabels,
    required this.series,
    this.axisMin = 0,
    this.unit = '',
  });
  final String title;
  final List<String> xLabels;
  final List<double> series;
  final double axisMin;
  final String unit;

  factory QuestChart.fromJson(Map<String, dynamic> j) => QuestChart(
        title: j['title'] as String? ?? '',
        xLabels: (j['xLabels'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        series: (j['series'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        axisMin: (j['axisMin'] as num?)?.toDouble() ?? 0,
        unit: j['unit'] as String? ?? '',
      );
}

/// A single Daily Quest item: a fabricated (never real) piece of media shown
/// alongside a question, four full-sentence answer options, and an
/// explanation naming the manipulation technique it demonstrates.
class QuestItem {
  const QuestItem({
    required this.id,
    required this.format,
    required this.difficulty,
    required this.category,
    required this.technique,
    required this.techniqueDefinition,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.postText,
    this.postHandle,
    this.postPlatform,
    this.headlineText,
    this.headlineOutlet,
    this.quoteText,
    this.quoteAttribution,
    this.chart,
  });

  final String id;
  final QuestFormat format;
  final int difficulty; // 1 (beginner) .. 5 (expert)
  final String category;
  final String technique;
  final String techniqueDefinition;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  // format == post
  final String? postText;
  final String? postHandle;
  final String? postPlatform; // twitter | instagram | tiktok | facebook | youtube

  // format == headline
  final String? headlineText;
  final String? headlineOutlet;

  // format == quote
  final String? quoteText;
  final String? quoteAttribution;

  // format == chart
  final QuestChart? chart;

  factory QuestItem.fromJson(Map<String, dynamic> j) {
    final format = questFormatFromString(j['format'] as String? ?? 'post');
    return QuestItem(
      id: j['id'] as String? ?? '',
      format: format,
      difficulty: (j['difficulty'] as num?)?.toInt().clamp(1, 5) ?? 1,
      category: j['category'] as String? ?? 'General',
      technique: j['technique'] as String? ?? '',
      techniqueDefinition: j['techniqueDefinition'] as String? ?? '',
      question: j['question'] as String? ?? 'What\'s the issue here?',
      options: (j['options'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      correctIndex: (j['correctIndex'] as num?)?.toInt() ?? 0,
      explanation: j['explanation'] as String? ?? '',
      postText: (j['post'] as Map<String, dynamic>?)?['text'] as String?,
      postHandle: (j['post'] as Map<String, dynamic>?)?['handle'] as String?,
      postPlatform:
          (j['post'] as Map<String, dynamic>?)?['platformIcon'] as String?,
      headlineText:
          (j['headline'] as Map<String, dynamic>?)?['text'] as String?,
      headlineOutlet:
          (j['headline'] as Map<String, dynamic>?)?['outlet'] as String?,
      quoteText: (j['quote'] as Map<String, dynamic>?)?['text'] as String?,
      quoteAttribution:
          (j['quote'] as Map<String, dynamic>?)?['attribution'] as String?,
      chart: j['chart'] != null
          ? QuestChart.fromJson(j['chart'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Adapts the legacy AI-generated shape (QuestService.generateQuest, which
  /// only ever produces a short-option social-post quest) into a QuestItem —
  /// used only if the bundled quest bank asset can't be read.
  factory QuestItem.fromLegacyAiMap(Map<String, dynamic> m) {
    final options =
        (m['options'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    return QuestItem(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
      format: QuestFormat.post,
      difficulty: switch (m['difficulty']) {
        'easy' => 2,
        'hard' => 4,
        _ => 3,
      },
      category: (m['topic'] as String?) ?? 'General',
      technique: (m['technique'] as String?) ?? '',
      techniqueDefinition: '',
      question: 'What manipulation technique is this post using?',
      options: options,
      correctIndex: (m['correct_index'] as num?)?.toInt() ?? 0,
      explanation: (m['explanation'] as String?) ?? '',
      postText: (m['post_text'] as String?) ?? '',
      postHandle: '@anonymous',
      postPlatform: 'twitter',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'format': format.name,
        'difficulty': difficulty,
        'category': category,
        'technique': technique,
        'techniqueDefinition': techniqueDefinition,
        'question': question,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
        if (postText != null)
          'post': {
            'text': postText,
            'handle': postHandle,
            'platformIcon': postPlatform,
          },
        if (headlineText != null)
          'headline': {'text': headlineText, 'outlet': headlineOutlet},
        if (quoteText != null)
          'quote': {'text': quoteText, 'attribution': quoteAttribution},
        if (chart != null)
          'chart': {
            'title': chart!.title,
            'xLabels': chart!.xLabels,
            'series': chart!.series,
            'axisMin': chart!.axisMin,
            'unit': chart!.unit,
          },
      };
}
