import 'widgets/adaptive_chrome.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'auth_service.dart';
import 'services/image_forensics_service.dart';
import 'theme/app_tokens.dart';
import 'widgets/app_widgets.dart';
import 'widgets/glass_button.dart';

// ── Shared constants ──────────────────────────────────────────────────────────
const _kPrimary    = Color(0xFF1E293B);
const _kAccent     = Color(0xFF22C55E);

// Theme-aware helpers (light + dark).
Color _bg(BuildContext c) => Theme.of(c).scaffoldBackgroundColor;
Color _surface(BuildContext c) => Theme.of(c).colorScheme.surface;
Color _sec(BuildContext c) =>
    Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.7);
bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

// ── Map ForensicsResult → UI check rows ───────────────────────────────────────
List<_CheckResult> _checksFromForensics(ForensicsResult r) =>
    r.signals.map((s) => _CheckResult(
          icon:   s.icon,
          label:  s.label,
          detail: s.explanation,
          status: s.severity == 0
              ? _CheckStatus.pass
              : s.severity == 1
                  ? _CheckStatus.warning
                  : _CheckStatus.fail,
        )).toList();

TextStyle _m({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double? height,
  double spacing = 0,
}) =>
    TextStyle(
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing,
    );

// ── Press-animation wrapper ───────────────────────────────────────────────────
class _PressBtn extends StatefulWidget {
  const _PressBtn({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressBtn> createState() => _PressBtnState();
}

class _PressBtnState extends State<_PressBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0,
      upperBound: 0.06,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) {
        _c.reverse();
        if (widget.onTap != null) HapticFeedback.mediumImpact();
        widget.onTap?.call();
      },
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) =>
            Transform.scale(scale: 1 - _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────
enum _CheckStatus { pass, warning, fail }

class _CheckResult {
  const _CheckResult({
    required this.icon,
    required this.label,
    required this.detail,
    required this.status,
  });
  final String icon, label, detail;
  final _CheckStatus status;
}

class _SampleImage {
  const _SampleImage({
    required this.label,
    required this.sublabel,
    required this.emoji,
    required this.gradient,
    required this.verdict,
    required this.verdictColor,
    required this.verdictIcon,
    required this.score,
    required this.summary,
    required this.checks,
  });
  final String label, sublabel, emoji, verdict, verdictIcon, summary;
  final List<Color> gradient;
  final Color verdictColor;
  final double score;
  final List<_CheckResult> checks;
}

final _samples = [
  _SampleImage(
    label: 'Viral Social Post',
    sublabel: 'Suspected AI portrait',
    emoji: '🤳',
    gradient: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
    verdict: 'MANIPULATED',
    verdictIcon: '🔴',
    verdictColor: const Color(0xFFEF4444),
    score: 14,
    summary:
        'Strong indicators of AI generation detected. Facial geometry, texture patterns, and background blending are inconsistent with a real photograph.',
    checks: [
      _CheckResult(
        icon: '🤖',
        label: 'AI-Generated Signs',
        detail: 'GAN texture artifacts in skin tones & hair edges detected.',
        status: _CheckStatus.fail,
      ),
      _CheckResult(
        icon: '💡',
        label: 'Lighting Inconsistency',
        detail: 'Shadow direction conflicts with highlight on the left cheek.',
        status: _CheckStatus.fail,
      ),
      _CheckResult(
        icon: '🔬',
        label: 'Pixel-Level Distortions',
        detail: 'Irregular frequency patterns in background transition zones.',
        status: _CheckStatus.fail,
      ),
      _CheckResult(
        icon: '🎭',
        label: 'Face-Swap Patterns',
        detail: 'Blending seams detected along jawline and ear boundaries.',
        status: _CheckStatus.warning,
      ),
      _CheckResult(
        icon: '🌑',
        label: 'Shadow & Highlight Integrity',
        detail: 'No cast shadow consistent with the implied light source.',
        status: _CheckStatus.fail,
      ),
      _CheckResult(
        icon: '📋',
        label: 'Metadata Conflicts',
        detail: 'No EXIF data present — typical of AI-generated outputs.',
        status: _CheckStatus.fail,
      ),
    ],
  ),
  _SampleImage(
    label: 'News Photograph',
    sublabel: 'Press agency image',
    emoji: '📰',
    gradient: [const Color(0xFF0EA5E9), const Color(0xFF0284C7)],
    verdict: 'LIKELY AUTHENTIC',
    verdictIcon: '🟢',
    verdictColor: const Color(0xFF22C55E),
    score: 91,
    summary:
        'No significant manipulation indicators found. Minor JPEG compression artifacts are consistent with standard web publishing. EXIF data matches the reported timestamp and device.',
    checks: [
      _CheckResult(
        icon: '🤖',
        label: 'AI-Generated Signs',
        detail: 'No GAN artifacts or generative texture patterns detected.',
        status: _CheckStatus.pass,
      ),
      _CheckResult(
        icon: '💡',
        label: 'Lighting Inconsistency',
        detail: 'Consistent single-source lighting with correct shadow casting.',
        status: _CheckStatus.pass,
      ),
      _CheckResult(
        icon: '🔬',
        label: 'Pixel-Level Distortions',
        detail: 'Standard JPEG compression artifacts only — no cloning or splicing.',
        status: _CheckStatus.warning,
      ),
      _CheckResult(
        icon: '🎭',
        label: 'Face-Swap Patterns',
        detail: 'Facial geometry and blending are natural and consistent.',
        status: _CheckStatus.pass,
      ),
      _CheckResult(
        icon: '🌑',
        label: 'Shadow & Highlight Integrity',
        detail: 'All shadows and highlights align with light source direction.',
        status: _CheckStatus.pass,
      ),
      _CheckResult(
        icon: '📋',
        label: 'Metadata Conflicts',
        detail: 'EXIF matches reported camera model, date, and GPS coordinates.',
        status: _CheckStatus.pass,
      ),
    ],
  ),
  _SampleImage(
    label: 'Profile Picture',
    sublabel: 'Unknown origin',
    emoji: '👤',
    gradient: [const Color(0xFFF59E0B), const Color(0xFFD97706)],
    verdict: 'UNCERTAIN',
    verdictIcon: '🟡',
    verdictColor: const Color(0xFFF59E0B),
    score: 47,
    summary:
        'Mixed signals detected. Lighting and shadows appear natural, but pixel patterns in the background suggest possible compositing. Metadata is absent, which is inconclusive.',
    checks: [
      _CheckResult(
        icon: '🤖',
        label: 'AI-Generated Signs',
        detail: 'Possible diffusion model texture in background elements.',
        status: _CheckStatus.warning,
      ),
      _CheckResult(
        icon: '💡',
        label: 'Lighting Inconsistency',
        detail: 'Lighting direction on subject is consistent and natural.',
        status: _CheckStatus.pass,
      ),
      _CheckResult(
        icon: '🔬',
        label: 'Pixel-Level Distortions',
        detail: 'Background shows higher frequency irregularities than foreground.',
        status: _CheckStatus.warning,
      ),
      _CheckResult(
        icon: '🎭',
        label: 'Face-Swap Patterns',
        detail: 'No face-swap blending artifacts detected on the subject.',
        status: _CheckStatus.pass,
      ),
      _CheckResult(
        icon: '🌑',
        label: 'Shadow & Highlight Integrity',
        detail: 'Subject shadows are consistent; background shadows are absent.',
        status: _CheckStatus.warning,
      ),
      _CheckResult(
        icon: '📋',
        label: 'Metadata Conflicts',
        detail: 'No EXIF data — could be a screenshot or AI-generated image.',
        status: _CheckStatus.warning,
      ),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
//  VISUAL ANALYZER PAGE
// ─────────────────────────────────────────────────────────────────────────────
class VisualAnalyzerPage extends StatefulWidget {
  const VisualAnalyzerPage({super.key});

  @override
  State<VisualAnalyzerPage> createState() => _VisualAnalyzerPageState();
}

class _VisualAnalyzerPageState extends State<VisualAnalyzerPage> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final scrolled = _scroll.offset > 10;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _buildNavbar() {
    return GlassTopBar.simple(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Image.asset('assets/logomain.png', height: 62, fit: BoxFit.contain),
            const Spacer(),
            const ProfileIcon(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 64)),
              const SliverToBoxAdapter(child: _AnalyzerSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildNavbar()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ANALYZER SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _AnalyzerSection extends StatefulWidget {
  const _AnalyzerSection();

  @override
  State<_AnalyzerSection> createState() => _AnalyzerSectionState();
}

class _AnalyzerSectionState extends State<_AnalyzerSection>
    with TickerProviderStateMixin {
  _SampleImage? _selected;
  bool _analyzing = false;
  bool _showResults = false;
  int _analysisStep = 0;
  String? _uploadedFileName;
  String? _apiError;
  VoidCallback? _retry;
  Uint8List? _photoBytes;

  late final AnimationController _resultsCtrl;
  late final AnimationController _pulseCtrl;

  static const _analysisSteps = [
    'Scanning pixel-level patterns…',
    'Checking lighting & shadows…',
    'Detecting AI generation signs…',
    'Analyzing facial geometry…',
    'Reading metadata…',
    'Compiling report…',
  ];

  @override
  void initState() {
    super.initState();
    _resultsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _resultsCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Sample demo (no API) ──────────────────────────────────────────────────
  Future<void> _analyzeSample(_SampleImage sample) async {
    setState(() {
      _selected = sample;
      _analyzing = true;
      _showResults = false;
      _analysisStep = 0;
      _uploadedFileName = null;
      _photoBytes = null;
      _apiError = null;
      _retry = null;
    });
    _resultsCtrl.reset();

    for (int i = 0; i < _analysisSteps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 340));
      if (!mounted) return;
      setState(() => _analysisStep = i);
    }
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    setState(() { _analyzing = false; _showResults = true; });
    _resultsCtrl.forward();
  }

  // ── Camera capture ────────────────────────────────────────────────────────
  Future<void> _pickFromCamera() async {
    final Uint8List bytes;
    final String name;
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 1920,
      );
      if (photo == null) return;
      bytes = await photo.readAsBytes();
      name = photo.name;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiError = 'The camera is unavailable. Enable camera access in Settings > Credexa, then try again.';
        _retry = _pickFromCamera;
      });
      return;
    }
    if (!mounted) return;
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      setState(() {
        _apiError = 'Image too large. Please use an image under 10 MB.';
        _retry = _pickFromCamera;
      });
      return;
    }
    await _analyzeFile(bytes, name);
  }

  // ── Gallery picker ────────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    final Uint8List bytes;
    final String name;
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (photo == null) return;
      bytes = await photo.readAsBytes();
      name = photo.name;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiError = 'Could not open your photo library. Check Photos access in Settings and try again.';
        _retry = _pickFile;
      });
      return;
    }
    if (!mounted) return;
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      setState(() {
        _apiError = 'Image too large. Please use an image under 10 MB.';
        _retry = _pickFile;
      });
      return;
    }
    await _analyzeFile(bytes, name);
  }

  Future<void> _analyzeFile(Uint8List bytes, String fileName) async {
    setState(() {
      _uploadedFileName = fileName;
      _photoBytes = bytes;
      _selected = null;
      _analyzing = true;
      _showResults = false;
      _analysisStep = 0;
      _apiError = null;
      _retry = null;
    });
    _resultsCtrl.reset();

    // On-device forensics and progress animation run concurrently.
    final forensicsFuture = _runLocalAnalysis(bytes, fileName);

    for (int i = 0; i < _analysisSteps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 380));
      if (!mounted) return;
      setState(() => _analysisStep = i);
    }
    await Future.delayed(const Duration(milliseconds: 300));

    final sample = await forensicsFuture;
    if (!mounted) return;

    if (sample != null) {
      setState(() { _selected = sample; _analyzing = false; _showResults = true; });
      _resultsCtrl.forward();
    } else {
      setState(() => _analyzing = false);
    }
  }

  Future<_SampleImage?> _runLocalAnalysis(Uint8List bytes, String fileName) async {
    try {
      final r = await ImageForensicsService.analyze(bytes);

      final combined = r.combinedScore;
      final isAI     = r.aiScore    >= 0.65;
      final isManip  = r.manipScore >= 0.65;
      final auth     = r.authScore;

      List<Color> gradient;
      String emoji, verdict, verdictIcon;
      Color verdictColor;

      if (isManip && !isAI) {
        gradient    = [const Color(0xFF7C3AED), const Color(0xFF6D28D9)];
        emoji       = '✂️'; verdict = 'MANIPULATED'; verdictIcon = '🔴';
        verdictColor = const Color(0xFFEF4444);
      } else if (isAI) {
        gradient    = [const Color(0xFFEF4444), const Color(0xFFDC2626)];
        emoji       = '🤖'; verdict = 'AI-GENERATED'; verdictIcon = '🔴';
        verdictColor = const Color(0xFFEF4444);
      } else if (combined >= 0.35) {
        gradient    = [const Color(0xFFF59E0B), const Color(0xFFD97706)];
        emoji       = '🔍'; verdict = 'UNCERTAIN'; verdictIcon = '🟡';
        verdictColor = const Color(0xFFF59E0B);
      } else {
        gradient    = [const Color(0xFF22C55E), const Color(0xFF16A34A)];
        emoji       = '✅'; verdict = 'LIKELY AUTHENTIC'; verdictIcon = '🟢';
        verdictColor = const Color(0xFF22C55E);
      }

      final summary = isManip && !isAI
          ? 'Manipulation indicators detected (authenticity score: $auth/100). '
            'Inconsistent compression regions and editing software signatures found.'
          : isAI
          ? 'AI-generation signals detected (authenticity score: $auth/100). '
            'Noise patterns, metadata, and pixel structure are inconsistent with a real photograph.'
          : combined >= 0.35
          ? 'Mixed signals detected (authenticity score: $auth/100). '
            'Some indicators suggest post-processing, but evidence is not conclusive.'
          : 'No significant manipulation indicators found (authenticity score: $auth/100). '
            'The image appears consistent with an unmodified photograph.';

      final displayName = fileName.length > 24
          ? '${fileName.substring(0, 21)}…'
          : fileName;

      return _SampleImage(
        label:       displayName,
        sublabel:    'Uploaded image',
        emoji:       emoji,
        gradient:    gradient,
        verdict:     verdict,
        verdictIcon: verdictIcon,
        verdictColor: verdictColor,
        score:       auth.toDouble(),
        summary:     summary,
        checks:      _checksFromForensics(r),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _apiError = 'We couldn\'t read that image. Try a different photo (JPG, PNG or WEBP).';
          _retry = _pickFile;
        });
      }
      return null;
    }
  }

  void _onUploadZoneTap() {
    if (_selected != null || _uploadedFileName != null) {
      _reset();
    } else {
      _pickFile();
    }
  }

  void _reset() {
    setState(() {
      _selected = null;
      _showResults = false;
      _analyzing = false;
      _analysisStep = 0;
      _uploadedFileName = null;
      _photoBytes = null;
      _apiError = null;
      _retry = null;
    });
    _resultsCtrl.reset();
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = _selected != null || _uploadedFileName != null;

    return Container(
      color: _bg(context),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          _Label('CREDEXA · VISUAL ANALYZER'),
          const SizedBox(height: 8),
          Text('Real vs. Edited\nMedia Detector',
              style: _m(size: 32, weight: FontWeight.w900, height: 1.1)),
          const SizedBox(height: 8),
          Text(
            'Upload any image — Credexa\'s computer vision engine checks for AI generation, face swaps, pixel manipulation, and more.',
            style: _m(size: 14, weight: FontWeight.w500, color: _sec(context), height: 1.65),
          ),
          const SizedBox(height: 24),

          // ── Upload zone ───────────────────────────────────────────────────
          _UploadZone(
            hasSelected: hasContent,
            analyzing: _analyzing,
            onTap: _onUploadZoneTap,
            selected: _selected,
            uploadedFileName: _uploadedFileName,
            photoBytes: _photoBytes,
            pulseCtrl: _pulseCtrl,
          ),
          const SizedBox(height: 10),

          // ── Upload / Camera buttons (idle only) ───────────────────────────
          if (!_analyzing && !hasContent)
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Choose File',
                    icon: Icons.upload_file_rounded,
                    accent: _kPrimary,
                    height: 48,
                    radius: 14,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onTap: _pickFile,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassButton(
                    label: 'Take Photo',
                    icon: Icons.photo_camera_rounded,
                    accent: _kAccent,
                    height: 48,
                    radius: 14,
                    fontSize: 13,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onTap: _pickFromCamera,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),

          // ── API error ─────────────────────────────────────────────────────
          if (_apiError != null)
            AppErrorCard(
              title: 'Couldn\'t analyze that image',
              message: _apiError!,
              icon: Icons.image_not_supported_rounded,
              onRetry: () {
                HapticFeedback.lightImpact();
                final retry = _retry ?? _pickFile;
                setState(() { _apiError = null; _retry = null; });
                retry();
              },
            ),

          const SizedBox(height: 8),

          // ── Sample picker (shown when idle) ───────────────────────────────
          if (!_analyzing && !_showResults) ...[
            Text('Try a sample:',
                style: _m(size: 12, weight: FontWeight.w700, color: _sec(context))),
            const SizedBox(height: 12),
            Row(
              children: _samples
                  .map((s) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: s == _samples.last ? 0 : 10),
                          child: _SampleCard(
                            sample: s,
                            onTap: () => _analyzeSample(s),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],

          // ── Analysis progress ─────────────────────────────────────────────
          if (_analyzing)
            _AnalysisProgress(
              steps: _analysisSteps,
              currentStep: _analysisStep,
              pulseCtrl: _pulseCtrl,
            ),

          // ── Results ───────────────────────────────────────────────────────
          if (_showResults && _selected != null)
            SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
                      .animate(CurvedAnimation(
                          parent: _resultsCtrl, curve: Curves.easeOut)),
              child: FadeTransition(
                opacity: _resultsCtrl,
                child: _ResultsPanel(
                  sample: _selected!,
                  photoBytes: _photoBytes,
                  onReset: _reset,
                ),
              ),
            ),

          // ── Tip card ──────────────────────────────────────────────────────
          if (!_analyzing)
            _TipCard(hasResults: _showResults),
        ],
      ),
    );
  }
}

// ── Label chip ────────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(text,
          style: _m(size: 11, weight: FontWeight.w800, color: _kAccent, spacing: 1.1)),
    );
  }
}

// ── Upload zone ───────────────────────────────────────────────────────────────
class _UploadZone extends StatelessWidget {
  const _UploadZone({
    required this.hasSelected,
    required this.analyzing,
    required this.onTap,
    required this.selected,
    required this.pulseCtrl,
    this.uploadedFileName,
    this.photoBytes,
  });
  final Uint8List? photoBytes;
  final bool hasSelected, analyzing;
  final VoidCallback onTap;
  final _SampleImage? selected;
  final String? uploadedFileName;
  final AnimationController pulseCtrl;

  // Extracts a short uppercase extension from a file name, e.g. "JPG".
  String? get _fileExt {
    final name = uploadedFileName;
    if (name == null || !name.contains('.')) return null;
    final ext = name.split('.').last.toUpperCase();
    return (ext.isEmpty || ext.length > 5) ? null : ext;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: AnimatedBuilder(
        animation: pulseCtrl,
        builder: (_, child) {
          // Shimmer the border color while analyzing (0.6 ↔ 1.0 opacity).
          final shimmer = 0.6 + pulseCtrl.value * 0.4;
          final borderColor = analyzing
              ? _kAccent.withValues(alpha: shimmer)
              : hasSelected
                  ? _kAccent.withValues(alpha: 0.4)
                  : Theme.of(context).colorScheme.outlineVariant;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: photoBytes != null ? 16 : 28),
            decoration: BoxDecoration(
              color: _surface(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: borderColor,
                width: (hasSelected || analyzing) ? 2 : 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4))
              ],
            ),
            child: child,
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: photoBytes != null
              ? [
                  // The user's own photo, with a scan sweep while analysing
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _ScanPhoto(
                      bytes: photoBytes!,
                      height: 190,
                      radius: 16,
                      scanning: analyzing,
                      ctrl: pulseCtrl,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      selected?.label ?? uploadedFileName ?? 'Photo',
                      style: _m(size: 14, weight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(analyzing ? 'Scanning…' : 'Uploaded image',
                      style: _m(size: 12, weight: FontWeight.w500, color: _sec(context))),
                  if (!analyzing) ...[
                    const SizedBox(height: 10),
                    Text('Tap to remove',
                        style: _m(size: 11, weight: FontWeight.w600, color: _kAccent)),
                  ],
                ]
              : selected != null
              ? [
                  // Analysed sample / uploaded result preview
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: selected!.gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Text(selected!.emoji,
                          style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(selected!.label,
                      style: _m(size: 14, weight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(selected!.sublabel,
                      style: _m(size: 12, weight: FontWeight.w500, color: _sec(context))),
                  if (!analyzing) ...[
                    const SizedBox(height: 10),
                    Text('Tap to remove',
                        style: _m(size: 11, weight: FontWeight.w600, color: _kAccent)),
                  ],
                ]
              : uploadedFileName != null
              ? [
                  // Uploaded file waiting for / during analysis
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Center(
                      child: Icon(Icons.image_rounded, size: 32, color: _kAccent),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      uploadedFileName!,
                      style: _m(size: 13, weight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_fileExt != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(_fileExt!,
                              style: _m(
                                  size: 11,
                                  weight: FontWeight.w800,
                                  color: _kAccent,
                                  spacing: 0.5)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text('Uploaded image',
                          style: _m(
                              size: 12,
                              weight: FontWeight.w500,
                              color: _sec(context))),
                    ],
                  ),
                  if (!analyzing) ...[
                    const SizedBox(height: 10),
                    Text('Tap to remove',
                        style: _m(size: 11, weight: FontWeight.w600, color: _kAccent)),
                  ],
                ]
              : [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _bg(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.upload_rounded,
                        size: 26, color: _sec(context)),
                  ),
                  const SizedBox(height: 12),
                  Text('Upload Image',
                      style: _m(size: 14, weight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('PNG, JPG, WEBP, GIF · or try a sample below',
                      style: _m(size: 12, weight: FontWeight.w500, color: _sec(context))),
                ],
        ),
      ),
    );
  }
}

// ── Sample card ───────────────────────────────────────────────────────────────
class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.sample, required this.onTap});
  final _SampleImage sample;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressBtn(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: sample.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(sample.emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(height: 8),
            Text(sample.label,
                textAlign: TextAlign.center,
                style: _m(size: 11, weight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(sample.sublabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _m(size: 11, weight: FontWeight.w500, color: _sec(context))),
          ],
        ),
      ),
    );
  }
}

// ── Analysis progress ─────────────────────────────────────────────────────────
class _AnalysisProgress extends StatelessWidget {
  const _AnalysisProgress({
    required this.steps,
    required this.currentStep,
    required this.pulseCtrl,
  });
  final List<String> steps;
  final int currentStep;
  final AnimationController pulseCtrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: pulseCtrl,
                builder: (_, _) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.4 + pulseCtrl.value * 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('Analyzing media…',
                  style: _m(size: 14, weight: FontWeight.w800)),
              const Spacer(),
              Text('${((currentStep + 1) / steps.length * 100).round()}%',
                  style: _m(size: 13, weight: FontWeight.w700, color: _kAccent)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                  begin: 0,
                  end: (currentStep + 1) / steps.length),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                backgroundColor: _bg(context),
                valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(height: 18),
          ...steps.asMap().entries.map((e) {
            final isDone = e.key < currentStep;
            final isCurrent = e.key == currentStep;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isDone
                          ? _kAccent
                          : isCurrent
                              ? _kAccent.withValues(alpha: 0.15)
                              : _bg(context),
                      shape: BoxShape.circle,
                      border: isCurrent
                          ? Border.all(color: _kAccent, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: isDone
                          ? const Icon(Icons.check_rounded,
                              size: 13, color: Colors.white)
                          : isCurrent
                              ? AnimatedBuilder(
                                  animation: pulseCtrl,
                                  builder: (_, _) => Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _kAccent
                                          .withValues(alpha: 0.5 + pulseCtrl.value * 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                )
                              : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    e.value,
                    style: _m(
                      size: 12,
                      weight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isDone
                          ? _sec(context)
                          : isCurrent
                              ? Theme.of(context).colorScheme.onSurface
                              : _sec(context),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Results panel ─────────────────────────────────────────────────────────────
class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({required this.sample, required this.onReset, this.photoBytes});
  final Uint8List? photoBytes;
  final _SampleImage sample;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final passCount = sample.checks.where((c) => c.status == _CheckStatus.pass).length;
    final failCount = sample.checks.where((c) => c.status == _CheckStatus.fail).length;
    final warnCount = sample.checks.where((c) => c.status == _CheckStatus.warning).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Verdict card ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surface(context),
            borderRadius: BorderRadius.circular(24),
            border: Border(
              top: BorderSide(color: sample.verdictColor, width: 3),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Thumbnail
                  if (photoBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(photoBytes!,
                          width: 56, height: 56, fit: BoxFit.cover),
                    )
                  else
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: sample.gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                          child: Text(sample.emoji,
                              style: const TextStyle(fontSize: 24))),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sample.label,
                            style: _m(size: 14, weight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(sample.sublabel,
                            style: _m(
                                size: 12,
                                weight: FontWeight.w500,
                                color: _sec(context))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  // Score ring
                  _ScoreRing(
                      score: sample.score, color: sample.verdictColor),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: sample.verdictColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            '${sample.verdictIcon}  ${sample.verdict}',
                            style: _m(
                                size: 11,
                                weight: FontWeight.w800,
                                color: sample.verdictColor,
                                spacing: 0.5),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _StatusPill(
                                count: passCount,
                                label: 'Pass',
                                color: _kAccent),
                            const SizedBox(width: 6),
                            _StatusPill(
                                count: warnCount,
                                label: 'Warn',
                                color: const Color(0xFFF59E0B)),
                            const SizedBox(width: 6),
                            _StatusPill(
                                count: failCount,
                                label: 'Fail',
                                color: const Color(0xFFEF4444)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  sample.summary,
                  style: _m(
                      size: 12,
                      weight: FontWeight.w600,
                      height: 1.65),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── 6 checks ────────────────────────────────────────────────────────
        Row(
          children: [
            Text('Detection Checks',
                style: _m(size: 16, weight: FontWeight.w900)),
            const Spacer(),
            Text('${sample.checks.length} scans run',
                style: _m(size: 12, weight: FontWeight.w600, color: _sec(context))),
          ],
        ),
        const SizedBox(height: 12),
        ...sample.checks.asMap().entries.map((e) => Padding(
              padding: EdgeInsets.only(
                  bottom: e.key < sample.checks.length - 1 ? 10 : 0),
              child: _StaggerIn(index: e.key, child: _CheckCard(result: e.value)),
            )),
        const SizedBox(height: 16),

        // ── Analyze another ──────────────────────────────────────────────
        GlassButton(
          label: 'Analyze Another Image →',
          accent: _kAccent,
          height: 52,
          radius: 14,
          onTap: onReset,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Score ring ────────────────────────────────────────────────────────────────
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.color});
  final double score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const size = 86.0;
    const sw = 8.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: score / 100),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOut,
      builder: (_, progress, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(size, size),
              painter: _RingPainter(
                  progress: progress,
                  color: color,
                  sw: sw,
                  track: Theme.of(context).colorScheme.outlineVariant),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(progress * 100).round()}',
                  style: _m(
                      size: 22, weight: FontWeight.w900),
                ),
                Text('/100',
                    style: _m(
                        size: 11, weight: FontWeight.w700, color: _sec(context))),
                const SizedBox(height: 1),
                Text('Auth. Score',
                    style: _m(
                        size: 11,
                        weight: FontWeight.w600,
                        color: _sec(context))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(
      {required this.progress, required this.color, required this.sw, required this.track});
  final Color track;
  final double progress;
  final Color color;
  final double sw;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - sw) / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      0, math.pi * 2, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.track != track;
}

// ── Status pill ───────────────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.count, required this.label, required this.color});
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text('$count $label',
          style: _m(size: 11, weight: FontWeight.w700, color: color)),
    );
  }
}

// ── Check card ────────────────────────────────────────────────────────────────
class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.result});
  final _CheckResult result;

  @override
  Widget build(BuildContext context) {
    final dark = _dark(context);
    final (bg, border, iconBg, statusColor, statusText) =
        switch (result.status) {
      _CheckStatus.pass => (
          const Color(0xFFF0FDF4),
          const Color(0xFFBBF7D0),
          const Color(0xFF22C55E),
          const Color(0xFF22C55E),
          'PASS',
        ),
      _CheckStatus.warning => (
          const Color(0xFFFFFBEB),
          const Color(0xFFFDE68A),
          const Color(0xFFF59E0B),
          const Color(0xFFF59E0B),
          'WARN',
        ),
      _CheckStatus.fail => (
          const Color(0xFFFFF5F5),
          const Color(0xFFFECACA),
          const Color(0xFFEF4444),
          const Color(0xFFEF4444),
          'FAIL',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? statusColor.withValues(alpha: 0.10) : bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? statusColor.withValues(alpha: 0.35) : border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _surface(context),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Center(
                child: Text(result.icon,
                    style: const TextStyle(fontSize: 17))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(result.label,
                          style: _m(size: 12, weight: FontWeight.w800)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(statusText,
                          style: _m(
                              size: 11,
                              weight: FontWeight.w800,
                              color: statusColor,
                              spacing: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(result.detail,
                    style: _m(
                        size: 11,
                        weight: FontWeight.w500,
                        color: _sec(context),
                        height: 1.55)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tip card ──────────────────────────────────────────────────────────────────
class _TipCard extends StatelessWidget {
  const _TipCard({required this.hasResults});
  final bool hasResults;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _dark(context) ? AppColors.sky.withValues(alpha: 0.10) : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.sky.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            const Text('💡', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasResults
                    ? 'Tap "Analyze Another Image" to test a different sample and compare results across media types.'
                    : 'Even a single manipulated image can spread to millions. Verifying before you share takes 10 seconds — and can stop misinformation in its tracks.',
                style: _m(
                    size: 12,
                    weight: FontWeight.w600,
                    color: _dark(context) ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                    height: 1.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Uploaded photo with an animated scan-line sweep ──────────────────────────
class _ScanPhoto extends StatelessWidget {
  const _ScanPhoto({
    required this.bytes,
    required this.height,
    required this.radius,
    required this.scanning,
    required this.ctrl,
  });
  final Uint8List bytes;
  final double height, radius;
  final bool scanning;
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.cover),
            if (scanning)
              AnimatedBuilder(
                animation: ctrl,
                builder: (_, _) {
                  final t = Curves.easeInOut.transform(ctrl.value);
                  final y = t * (height - 3);
                  return Stack(
                    children: [
                      Positioned(
                        top: (y - 44).clamp(0.0, height),
                        left: 0,
                        right: 0,
                        height: 44,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _kAccent.withValues(alpha: 0),
                                _kAccent.withValues(alpha: 0.28),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: y,
                        left: 0,
                        right: 0,
                        height: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _kAccent,
                            boxShadow: [
                              BoxShadow(
                                  color: _kAccent.withValues(alpha: 0.9),
                                  blurRadius: 10,
                                  spreadRadius: 1),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── Staggered fade + slide entrance ──────────────────────────────────────────
class _StaggerIn extends StatefulWidget {
  const _StaggerIn({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 80 * widget.index), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.25),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
