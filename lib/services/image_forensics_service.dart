import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// ── Result types ───────────────────────────────────────────────────────────────

class ForensicSignal {
  const ForensicSignal({
    required this.label,
    required this.icon,
    required this.explanation,
    required this.severity, // 0 = pass  1 = warning  2 = alert
  });
  final String label;
  final String icon;
  final String explanation;
  final int severity;
}

class ForensicsResult {
  const ForensicsResult({
    required this.aiScore,
    required this.manipScore,
    required this.signals,
    required this.imageWidth,
    required this.imageHeight,
    required this.hasExif,
    this.softwareTag,
    this.cameraModel,
  });

  final double aiScore;    // 0.0–1.0
  final double manipScore; // 0.0–1.0
  final List<ForensicSignal> signals;
  final int imageWidth;
  final int imageHeight;
  final bool hasExif;
  final String? softwareTag;
  final String? cameraModel;

  double get combinedScore => math.max(aiScore, manipScore);
  int get authScore => ((1.0 - combinedScore) * 100).round().clamp(0, 100);
}

// ── Public service ─────────────────────────────────────────────────────────────

class ImageForensicsService {
  // Runs all checks in an isolate so the UI never freezes.
  static Future<ForensicsResult> analyze(Uint8List bytes) =>
      compute(_runForensics, bytes);
}

// ── Isolate entry point (must be top-level) ────────────────────────────────────

ForensicsResult _runForensics(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) throw Exception('Could not decode image');

  final signals = <ForensicSignal>[];
  double aiScore    = 0.0;
  double manipScore = 0.0;

  // ── 1. EXIF / metadata ──────────────────────────────────────────────────────
  final exif    = image.exif;
  // IfdDirectory has no isNotEmpty; check for any common known tags instead.
  const knownTags = [0x010F, 0x0110, 0x0131, 0x0132, 0x9003];
  final hasExif = knownTags.any(
    (t) => exif.imageIfd.containsKey(t) || exif.exifIfd.containsKey(t),
  );

  String? softwareTag;
  String? cameraModel;
  String? cameraMake;

  if (hasExif) {
    final sw    = exif.imageIfd[0x0131]; // Software
    final make  = exif.imageIfd[0x010F]; // Make
    final model = exif.imageIfd[0x0110]; // Model
    if (sw    != null) softwareTag = sw.toString().trim();
    if (make  != null) cameraMake  = make.toString().trim();
    if (model != null) cameraModel = model.toString().trim();
  }

  if (!hasExif) {
    aiScore += 0.18;
    signals.add(const ForensicSignal(
      label:       'No Metadata',
      icon:        '📋',
      severity:    1,
      explanation: 'No EXIF data found. AI-generated images and screenshots '
          'commonly lack all metadata.',
    ));
  } else if (cameraMake == null && cameraModel == null && softwareTag == null) {
    aiScore += 0.12;
    signals.add(const ForensicSignal(
      label:       'Empty Metadata',
      icon:        '📷',
      severity:    1,
      explanation: 'Metadata block exists but contains no camera hardware or '
          'software entries — atypical of real photographs.',
    ));
  } else if (cameraMake == null && cameraModel == null) {
    aiScore += 0.12;
    signals.add(const ForensicSignal(
      label:       'No Camera Hardware',
      icon:        '📷',
      severity:    1,
      explanation: 'Metadata has no camera make or model. Real photographs '
          'always record the capturing device.',
    ));
  }

  if (softwareTag != null) {
    final lower = softwareTag.toLowerCase();
    const aiTools = [
      'stable diffusion', 'midjourney', 'dall-e', 'dall·e',
      'firefly', 'imagen', 'novelai', 'invokeai', 'comfyui',
      'automatic1111', 'kandinsky', 'leonardo', 'getimg',
    ];
    const editTools = [
      'photoshop', 'lightroom', 'gimp', 'affinity photo',
      'pixlr', 'snapseed', 'facetune', 'meitu', 'picsart', 'vsco',
      'capture one', 'darktable',
    ];

    if (aiTools.any((t) => lower.contains(t))) {
      aiScore += 0.55;
      signals.add(ForensicSignal(
        label:       'AI Tool Signature',
        icon:        '🤖',
        severity:    2,
        explanation: 'Software metadata identifies "$softwareTag" — a known '
            'AI image generator.',
      ));
    } else if (editTools.any((t) => lower.contains(t))) {
      manipScore += 0.40;
      signals.add(ForensicSignal(
        label:       'Editing Software Detected',
        icon:        '🖊',
        severity:    2,
        explanation: 'Software metadata identifies "$softwareTag" — this image '
            'was processed in image editing software.',
      ));
    }
  }

  // ── 2. Dimension heuristics ─────────────────────────────────────────────────
  const aiDims = {
    128, 256, 384, 512, 576, 640, 704, 768, 832, 896, 960,
    1024, 1152, 1280, 1408, 1536, 1664, 1792, 2048,
  };
  final w = image.width;
  final h = image.height;

  if (aiDims.contains(w) && aiDims.contains(h)) {
    // Square dimensions (e.g. 512×512) are more suspicious than rectangular
    final bonus = (w == h) ? 0.15 : 0.08;
    aiScore += bonus;
    signals.add(ForensicSignal(
      label:       'AI-Standard Dimensions',
      icon:        '📐',
      severity:    1,
      explanation: '$w×${h}px — both dimensions match common AI generator '
          'output sizes.',
    ));
  }

  // ── 3. Noise analysis (Laplacian variance) ──────────────────────────────────
  // Real cameras always introduce shot noise; AI images are suspiciously smooth.
  final small   = img.copyResize(image, width: math.min(w, 350));
  final sigma   = _noiseSigma(small);

  if (sigma < 1.8) {
    aiScore += 0.20;
    signals.add(ForensicSignal(
      label:       'Unnaturally Smooth',
      icon:        '🔬',
      severity:    1,
      explanation: 'Noise level (σ=${sigma.toStringAsFixed(1)}) is far below '
          'natural camera noise — characteristic of AI-generated images.',
    ));
  } else if (sigma < 3.5) {
    aiScore += 0.07;
    signals.add(ForensicSignal(
      label:       'Low Noise Level',
      icon:        '🔬',
      severity:    1,
      explanation: 'Noise level (σ=${sigma.toStringAsFixed(1)}) is lower than '
          'typical photographs — possible AI assistance or heavy smoothing.',
    ));
  }

  // ── 4. Error Level Analysis (JPEG forensics) ────────────────────────────────
  // High variance between original and re-encoded → splicing/editing.
  // Very low uniform ELA → AI-generated (no prior compression history).
  final ela = _errorLevelAnalysis(small);

  if (ela.highVariance) {
    manipScore += 0.30;
    signals.add(const ForensicSignal(
      label:       'ELA Inconsistency',
      icon:        '⚡',
      severity:    2,
      explanation: 'Error Level Analysis found regions with inconsistent '
          'compression history — a common artifact of image splicing or cloning.',
    ));
  } else if (ela.veryLow) {
    aiScore += 0.12;
    signals.add(const ForensicSignal(
      label:       'Uniform ELA Response',
      icon:        '🌊',
      severity:    1,
      explanation: 'Unusually uniform ELA across the image — no evidence of '
          'prior compression cycles, consistent with AI generation.',
    ));
  }

  // ── 5. Aspect ratio check ───────────────────────────────────────────────────
  // Pure 1:1 is common in AI social-media generation.
  if (w == h && w >= 512) {
    aiScore += 0.05;
  }

  // ── Summary signal when nothing suspicious found ────────────────────────────
  if (signals.isEmpty ||
      signals.every((s) => s.severity == 0)) {
    signals.add(const ForensicSignal(
      label:       'No Anomalies Detected',
      icon:        '✅',
      severity:    0,
      explanation: 'All forensic checks passed — no significant manipulation '
          'or AI-generation indicators found.',
    ));
  }

  return ForensicsResult(
    aiScore:     aiScore.clamp(0.0, 1.0),
    manipScore:  manipScore.clamp(0.0, 1.0),
    signals:     signals,
    imageWidth:  w,
    imageHeight: h,
    hasExif:     hasExif,
    softwareTag: softwareTag,
    cameraModel: cameraModel,
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────────

// Laplacian-based noise estimation (standard deviation of high-pass response).
double _noiseSigma(img.Image image) {
  final w = image.width;
  final h = image.height;
  if (w < 3 || h < 3) return 5.0;

  const stride = 4; // sample every 4th pixel for speed
  final values = <double>[];

  for (int y = 1; y < h - 1; y += stride) {
    for (int x = 1; x < w - 1; x += stride) {
      final c = _luma(image.getPixel(x,     y    ));
      final t = _luma(image.getPixel(x,     y - 1));
      final b = _luma(image.getPixel(x,     y + 1));
      final l = _luma(image.getPixel(x - 1, y    ));
      final r = _luma(image.getPixel(x + 1, y    ));
      values.add((4 * c - t - b - l - r).abs());
    }
  }

  if (values.isEmpty) return 5.0;
  final mean     = values.fold(0.0, (a, v) => a + v) / values.length;
  final variance = values.fold(0.0, (a, v) => a + (v - mean) * (v - mean)) /
      values.length;
  return math.sqrt(variance);
}

class _ElaResult {
  const _ElaResult({
    required this.highVariance,
    required this.veryLow,
    required this.meanError,
  });
  final bool   highVariance;
  final bool   veryLow;
  final double meanError;
}

// Computes JPEG Error Level Analysis on a (already-downsampled) image.
_ElaResult _errorLevelAnalysis(img.Image image) {
  final reenc    = img.encodeJpg(image, quality: 75);
  final redecoded = img.decodeImage(Uint8List.fromList(reenc));
  if (redecoded == null) {
    return const _ElaResult(highVariance: false, veryLow: false, meanError: 0);
  }

  final w = math.min(image.width,  redecoded.width);
  final h = math.min(image.height, redecoded.height);

  const stride = 3;
  final diffs  = <double>[];

  for (int y = 0; y < h; y += stride) {
    for (int x = 0; x < w; x += stride) {
      final o = image.getPixel(x, y);
      final r = redecoded.getPixel(x, y);
      final d = ((o.r - r.r).abs() + (o.g - r.g).abs() + (o.b - r.b).abs()) / 3.0;
      diffs.add(d.toDouble());
    }
  }

  if (diffs.isEmpty) {
    return const _ElaResult(highVariance: false, veryLow: false, meanError: 0);
  }

  final mean     = diffs.fold(0.0, (a, v) => a + v) / diffs.length;
  final variance = diffs.fold(0.0, (a, v) => a + (v - mean) * (v - mean)) /
      diffs.length;
  final sigma    = math.sqrt(variance);

  return _ElaResult(
    highVariance: sigma > 16.0,
    veryLow:      mean < 2.5 && sigma < 4.0,
    meanError:    mean,
  );
}

double _luma(img.Pixel p) => 0.299 * p.r.toDouble()
    + 0.587 * p.g.toDouble()
    + 0.114 * p.b.toDouble();
