class AnalysisFlag {
  const AnalysisFlag({
    required this.type,
    required this.quote,
    required this.explanation,
  });
  final String type;
  final String quote;
  final String explanation;

  factory AnalysisFlag.fromJson(Map<String, dynamic> j) => AnalysisFlag(
        type:        j['type']        as String? ?? 'UNKNOWN',
        quote:       j['quote']       as String? ?? '',
        explanation: j['explanation'] as String? ?? '',
      );
}

class ModelResult {
  const ModelResult({
    required this.model,
    required this.credibilityScore,
    required this.verdict,
    required this.confidence,
    required this.reasoning,
    required this.flags,
    this.error,
  });
  final String model;
  final int credibilityScore;
  final String verdict;
  final String confidence;
  final String reasoning;
  final List<AnalysisFlag> flags;
  final String? error;

  bool get failed => error != null;

  factory ModelResult.fromJson(Map<String, dynamic> j) => ModelResult(
        model:            j['model']             as String? ?? 'Unknown',
        credibilityScore: (j['credibility_score'] as num?)?.toInt() ?? 50,
        verdict:          j['verdict']            as String? ?? 'UNCERTAIN',
        confidence:       j['confidence']         as String? ?? 'LOW',
        reasoning:        j['reasoning']          as String? ?? '',
        flags: (j['flags'] as List<dynamic>?)
                ?.map((e) => AnalysisFlag.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        error: j['error'] as String?,
      );
}

class Synthesis {
  const Synthesis({
    required this.finalScore,
    required this.finalVerdict,
    required this.agreements,
    required this.conflicts,
    required this.flags,
    required this.summary,
  });
  final int finalScore;
  final String finalVerdict;
  final List<String> agreements;
  final List<String> conflicts;
  final List<AnalysisFlag> flags;
  final String summary;

  factory Synthesis.fromJson(Map<String, dynamic> j) => Synthesis(
        finalScore:   (j['final_score']   as num?)?.toInt() ?? 50,
        finalVerdict: j['final_verdict']   as String? ?? 'UNCERTAIN',
        agreements: (j['agreements'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        conflicts: (j['conflicts'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        flags: (j['flags'] as List<dynamic>?)
                ?.map((e) => AnalysisFlag.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        summary: j['summary'] as String? ?? '',
      );
}

class AnalysisResult {
  const AnalysisResult({
    required this.modelResults,
    required this.synthesis,
    this.extractedText,
    this.sourceUrl,
  });
  final List<ModelResult> modelResults;
  final Synthesis synthesis;
  final String? extractedText;
  final String? sourceUrl;

  factory AnalysisResult.fromJson(Map<String, dynamic> j) => AnalysisResult(
        modelResults: (j['model_results'] as List<dynamic>)
            .map((e) => ModelResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        synthesis: Synthesis.fromJson(j['synthesis'] as Map<String, dynamic>),
        extractedText: j['extracted_claim'] as String?,
        sourceUrl: j['source_url'] as String?,
      );
}
