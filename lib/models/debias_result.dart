class DebiasChange {
  const DebiasChange({
    required this.type,
    required this.icon,
    required this.original,
    required this.rewritten,
    required this.explanation,
  });
  final String type, icon, original, rewritten, explanation;

  factory DebiasChange.fromJson(Map<String, dynamic> j) => DebiasChange(
        type:        j['type']        as String? ?? 'Bias',
        icon:        j['icon']        as String? ?? '🔍',
        original:    j['original']    as String? ?? '',
        rewritten:   j['rewritten']   as String? ?? '',
        explanation: j['explanation'] as String? ?? '',
      );
}

class DebiasPerspective {
  const DebiasPerspective({
    required this.label,
    required this.text,
    required this.note,
  });
  final String label, text, note;

  factory DebiasPerspective.fromJson(Map<String, dynamic> j) => DebiasPerspective(
        label: j['label'] as String? ?? '',
        text:  j['text']  as String? ?? '',
        note:  j['note']  as String? ?? '',
      );
}

class DebiasResult {
  const DebiasResult({
    required this.originalText,
    required this.neutralText,
    required this.biasScore,
    required this.changes,
    required this.biasTypes,
    this.extractedText,
    this.leftPerspective,
    this.centerPerspective,
    this.rightPerspective,
  });
  final String originalText;
  final String neutralText;
  final int biasScore;
  final List<DebiasChange> changes;
  final List<String> biasTypes;
  final String? extractedText;
  final DebiasPerspective? leftPerspective;
  final DebiasPerspective? centerPerspective;
  final DebiasPerspective? rightPerspective;

  bool get hasPerspectives =>
      leftPerspective != null && centerPerspective != null && rightPerspective != null;

  factory DebiasResult.fromJson(Map<String, dynamic> j, String originalInput) {
    DebiasPerspective? persp(String key) {
      final p = (j['perspectives'] as Map<String, dynamic>?)?[key];
      if (p == null) return null;
      return DebiasPerspective.fromJson(p as Map<String, dynamic>);
    }
    return DebiasResult(
      originalText:      originalInput,
      neutralText:       j['neutral_text']   as String? ?? originalInput,
      biasScore:         (j['bias_score']    as num?)?.toInt() ?? 0,
      changes: (j['changes'] as List<dynamic>?)
              ?.map((e) => DebiasChange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      biasTypes: (j['bias_types'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      extractedText:    j['extracted_text'] as String?,
      leftPerspective:   persp('left'),
      centerPerspective: persp('center'),
      rightPerspective:  persp('right'),
    );
  }

  String get biasLabel {
    if (biasScore <= 20) return 'Mostly Neutral';
    if (biasScore <= 50) return 'Mildly Biased';
    if (biasScore <= 80) return 'Clearly Biased';
    return 'Highly Manipulative';
  }
}
