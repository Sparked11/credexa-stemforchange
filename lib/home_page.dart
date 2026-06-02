import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_config.dart';
import 'auth_service.dart';
import 'bias_fingerprint.dart';
import 'models/analysis_result.dart';
import 'services/analysis_service.dart';
import 'services/ocr_service.dart';
import 'services/profile_service.dart';
import 'services/shared_content_router.dart';
import 'services/user_progress_service.dart';

// ── Color system ──────────────────────────────────────────────────────────────
const _kPrimary    = Color(0xFF1E293B);
const _kSecondary  = Color(0xFF64748B);
const _kAccent     = Color(0xFF22C55E);
const _kDanger     = Color(0xFFEF4444);
const _kBackground = Color(0xFFF1F5F9);

// ── Typography helper ─────────────────────────────────────────────────────────
TextStyle _m({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = _kPrimary,
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

// ── Press-animation button wrapper ────────────────────────────────────────────
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
      onTapDown: (_) { _c.forward(); HapticFeedback.mediumImpact(); },
      onTapUp: (_) {
        _c.reverse();
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

// ── Animated score ring ───────────────────────────────────────────────────────
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({
    required this.score,
    required this.color,
    this.size = 88,
    this.strokeWidth = 8,
  });
  final double score;
  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (_, progress, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(progress: progress, color: color, sw: strokeWidth),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(progress * 100).round()}',
                  style: _m(size: size * 0.26, weight: FontWeight.w900, color: _kPrimary),
                ),
                Text(
                  '/100',
                  style: _m(size: size * 0.1, weight: FontWeight.w700, color: _kSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color, required this.sw});
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
        ..color = const Color(0xFFE2E8F0),
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
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
//  HOME PAGE
// ─────────────────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      height: 64,
      decoration: BoxDecoration(
        color: _scrolled ? Colors.white : _kBackground,
        border: _scrolled
            ? const Border(bottom: BorderSide(color: Color(0x12000000), width: 1))
            : null,
        boxShadow: _scrolled
            ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))]
            : [],
      ),
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
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 64)),
              const SliverToBoxAdapter(child: _ExplainWhySection()),
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
//  EXPLAIN WHY SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _ExplainWhySection extends StatefulWidget {
  const _ExplainWhySection();

  @override
  State<_ExplainWhySection> createState() => _ExplainWhySectionState();
}

class _ExplainWhySectionState extends State<_ExplainWhySection>
    with SingleTickerProviderStateMixin {
  final _textCtrl = TextEditingController();
  bool _scanning = false;
  bool _showResults = false;
  String? _error;
  AnalysisResult? _result;
  late final AnimationController _resultsCtrl;

  String _query = '';
  Uint8List? _imageBytes;
  String _imageMimeType = 'image/jpeg';
  String? _imageName;

  // Accuracy tracking — reset on every new scan.
  String? _userPrediction;   // 'true' or 'false', set before results arrive
  bool?   _predictionCorrect; // set after AI verdict is known

  static const _examples = [
    '5G towers are causing birds to fall from the sky.',
    'Scientists prove coffee cures cancer.',
    'Vaccines contain government microchips.',
    'Climate change is a hoax invented by scientists.',
  ];

  @override
  void initState() {
    super.initState();
    _resultsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    SharedContentRouter.forFactcheck.addListener(_onSharedContent);
    // Consume immediately if content was routed before this widget mounted
    if (SharedContentRouter.forFactcheck.value != null) _onSharedContent();
  }

  void _onSharedContent() {
    final content = SharedContentRouter.forFactcheck.value;
    if (content == null || !mounted) return;
    SharedContentRouter.forFactcheck.value = null; // consume
    final type = content['type'] as String?;
    if (type == 'image') {
      final b64 = content['imageBase64'] as String?;
      final mime = content['mimeType'] as String? ?? 'image/jpeg';
      if (b64 != null && b64.isNotEmpty) {
        try {
          final bytes = base64Decode(b64);
          setState(() {
            _imageBytes = bytes;
            _imageMimeType = mime;
            _imageName = 'Shared image';
            _showResults = false;
            _error = null;
          });
        } catch (_) {}
      }
    } else {
      final text = content['text'] as String? ?? '';
      if (text.isNotEmpty) {
        if (text.startsWith('http')) {
          _extractAndScanUrl(text);
        } else {
          setState(() {
            _textCtrl.text = text;
            _imageBytes = null;
            _imageName = null;
            _showResults = false;
            _error = null;
          });
        }
      }
    }
  }

  Future<void> _extractAndScanUrl(String url) async {
    setState(() { _scanning = true; _showResults = false; _error = null; });
    try {
      final extracted = await OcrService.extractFromUrl(url);
      if (!mounted) return;
      if (extracted.trim().isNotEmpty) {
        _textCtrl.text = extracted.trim();
        _imageBytes = null;
        _imageName = null;
        await _scan();
      } else {
        setState(() {
          _textCtrl.text = url;
          _scanning = false;
          _error = 'Could not extract post content from this link. '
              'Try sharing a screenshot of the post instead.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _textCtrl.text = url;
        _scanning = false;
        _error = 'Could not extract post content from this link. '
            'Try sharing a screenshot of the post instead.';
      });
    }
  }

  @override
  void dispose() {
    SharedContentRouter.forFactcheck.removeListener(_onSharedContent);
    _textCtrl.dispose();
    _resultsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1920);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageMimeType = picked.mimeType ?? 'image/jpeg';
      _imageName = picked.name;
      _showResults = false;
      _error = null;
    });
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1920);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageMimeType = picked.mimeType ?? 'image/jpeg';
      _imageName = 'Photo';
      _showResults = false;
      _error = null;
    });
  }

  void _clearImage() => setState(() { _imageBytes = null; _imageName = null; });

  Future<void> _scan() async {
    final text = _textCtrl.text.trim();
    final hasImage = _imageBytes != null;
    if (text.isEmpty && !hasImage) return;
    _query = text;
    setState(() {
      _scanning = true;
      _showResults = false;
      _error = null;
      _userPrediction = null;
      _predictionCorrect = null;
    });
    _resultsCtrl.reset();
    try {
      final AnalysisResult result;
      if (hasImage) {
        final extracted = await OcrService.extractText(_imageBytes!, _imageMimeType);
        if (extracted.trim().isNotEmpty) {
          _query = extracted.trim();
          if (mounted && _textCtrl.text.trim().isEmpty) {
            setState(() => _textCtrl.text = extracted.trim());
          }
          result = await AnalysisService.analyzeWithSearch(extracted.trim());
        } else {
          result = await AnalysisService.analyzeImage(_imageBytes!, _imageMimeType);
        }
      } else {
        result = await AnalysisService.analyzeWithSearch(text);
      }
      if (!mounted) return;

      // Record accuracy prediction if the user made one before seeing the result.
      bool? correct;
      if (_userPrediction != null) {
        correct = await UserProgressService.recordPrediction(
            _userPrediction!, result.synthesis.finalVerdict);
      }

      setState(() {
        _scanning = false;
        _showResults = true;
        _result = result;
        _predictionCorrect = correct;
        if (result.extractedText != null && result.extractedText!.isNotEmpty) {
          _textCtrl.text = result.extractedText!;
        }
      });
      _resultsCtrl.forward();
      ProfileService.incrementCheck();
    } catch (e) {
      if (!mounted) return;
      setState(() { _scanning = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  void _useExample(String text) {
    setState(() {
      _textCtrl.text = text;
      _imageBytes = null;
      _imageName = null;
      _showResults = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBackground,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ────────────────────────────────────────────────────
          _SectionLabel(text: 'CREDEXA · AI TOOL'),
          const SizedBox(height: 8),
          Text('Explain Why', style: _m(size: 32, weight: FontWeight.w900, height: 1.1)),
          const SizedBox(height: 8),
          Text(
            'Paste any headline or claim — we\'ll break down exactly why it might be misleading.',
            style: _m(size: 14, weight: FontWeight.w500, color: _kSecondary, height: 1.6),
          ),
          const SizedBox(height: 24),

          // ── Input card ─────────────────────────────────────────────────────
          _InputCard(
            textCtrl: _textCtrl,
            scanning: _scanning,
            showResults: _showResults,
            onScan: _scanning ? null : _scan,
            onChanged: () {
              if (_showResults) setState(() => _showResults = false);
            },
            imageBytes: _imageBytes,
            imageName: _imageName,
            onPickImage: _scanning ? null : _pickImage,
            onTakePhoto: _scanning ? null : _takePhoto,
            onClearImage: _clearImage,
          ),
          const SizedBox(height: 16),

          // ── Prediction prompt (shown while AI is thinking) ─────────────────
          if (_scanning) ...[
            const SizedBox(height: 8),
            if (_userPrediction == null)
              _PredictionPrompt(
                onPrediction: (p) => setState(() => _userPrediction = p),
              )
            else
              _PredictionLocked(prediction: _userPrediction!),
            const SizedBox(height: 16),
            _AnalysisAnimation(
              claim: _imageBytes != null && _textCtrl.text.trim().isEmpty
                  ? 'this image'
                  : _textCtrl.text.trim(),
            ),
          ],

          // ── Prediction result chip ─────────────────────────────────────────
          if (_showResults && _predictionCorrect != null) ...[
            const SizedBox(height: 8),
            _PredictionResultChip(correct: _predictionCorrect!),
          ],

          // ── Example chips ──────────────────────────────────────────────────
          if (!_showResults && !_scanning) ...[
            Text('Try an example:', style: _m(size: 12, weight: FontWeight.w700, color: _kSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _examples
                  .map((e) => _ExampleChip(text: e, onTap: () => _useExample(e)))
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],

          // ── Error ──────────────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEDE8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: _m(size: 12, weight: FontWeight.w600, color: _kDanger, height: 1.5)),
                  ),
                ],
              ),
            ),
          ],

          // ── Results ────────────────────────────────────────────────────────
          if (_showResults && _result != null)
            SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _resultsCtrl, curve: Curves.easeOut)),
              child: FadeTransition(
                opacity: _resultsCtrl,
                child: _ResultsPanel(result: _result!, query: _query),
              ),
            ),

          // ── Tip card at bottom ─────────────────────────────────────────────
          if (!_scanning) ...[
            const SizedBox(height: 8),
            _TipCard(hasResults: _showResults),
          ],
        ],
      ),
    );
  }
}

// ── Shared label widget ───────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(text,
          style: _m(size: 10, weight: FontWeight.w800, color: _kAccent, spacing: 1.1)),
    );
  }
}

// ── Example chip ──────────────────────────────────────────────────────────────
class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final short = text.length > 36 ? '${text.substring(0, 34)}…' : text;
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))
          ],
        ),
        child: Text(short, style: _m(size: 11, weight: FontWeight.w600, color: _kSecondary)),
      ),
    );
  }
}

// ── Input card ────────────────────────────────────────────────────────────────
class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.textCtrl,
    required this.scanning,
    required this.showResults,
    required this.onScan,
    required this.onChanged,
    this.imageBytes,
    this.imageName,
    this.onPickImage,
    this.onTakePhoto,
    this.onClearImage,
  });
  final TextEditingController textCtrl;
  final bool scanning;
  final bool showResults;
  final VoidCallback? onScan;
  final VoidCallback onChanged;
  final Uint8List? imageBytes;
  final String? imageName;
  final VoidCallback? onPickImage;
  final VoidCallback? onTakePhoto;
  final VoidCallback? onClearImage;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null;
    final btnLabel  = hasImage && textCtrl.text.trim().isEmpty ? 'Analyze Image' : 'Explain Why';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Input label
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _kAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: Text('🔍', style: TextStyle(fontSize: 16))),
                ),
                const SizedBox(width: 10),
                Text('Claim or Headline',
                    style: _m(size: 14, weight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 14),
            // Text field
            TextField(
              controller: textCtrl,
              maxLines: 4,
              onChanged: (_) => onChanged(),
              style: _m(size: 14, weight: FontWeight.w500, height: 1.6),
              decoration: InputDecoration(
                hintText: 'Paste a headline, tweet, quote, or any claim…',
                hintStyle: _m(size: 14, weight: FontWeight.w500, color: const Color(0xFFCBD5E1), height: 1.6),
                filled: true,
                fillColor: _kBackground,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _kAccent, width: 2)),
              ),
            ),
            const SizedBox(height: 10),

            // ── Image attachment strip ────────────────────────────────────
            if (hasImage) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _kBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(imageBytes!, width: 48, height: 48, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        imageName ?? 'Image attached',
                        style: _m(size: 12, weight: FontWeight.w600, color: _kPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: scanning ? null : () { HapticFeedback.lightImpact(); onClearImage!(); },
                      child: const Icon(Icons.close_rounded, size: 20, color: _kSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _PressBtn(
                      onTap: scanning ? null : onPickImage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _kPrimary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_library_outlined, size: 15, color: Colors.white),
                            const SizedBox(width: 6),
                            Text('Gallery',
                                style: _m(size: 13, weight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PressBtn(
                      onTap: scanning ? null : onTakePhoto,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: _kAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt_outlined, size: 15, color: Colors.white),
                            const SizedBox(width: 6),
                            Text('Camera',
                                style: _m(size: 13, weight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            // Scan button
            _PressBtn(
              onTap: onScan,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: scanning
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: scanning ? const Color(0xFF86EFAC) : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: scanning
                      ? []
                      : [BoxShadow(color: _kAccent.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: scanning
                      ? [
                          const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          ),
                          const SizedBox(width: 10),
                          Text('Analyzing…',
                              style: _m(size: 15, weight: FontWeight.w800, color: Colors.white)),
                        ]
                      : [
                          Text(hasImage ? '🖼' : '⚡', style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(btnLabel,
                              style: _m(size: 15, weight: FontWeight.w800, color: Colors.white)),
                        ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ANALYSIS LOADING ANIMATION
// ─────────────────────────────────────────────────────────────────────────────
class _AnalysisAnimation extends StatefulWidget {
  const _AnalysisAnimation({required this.claim});
  final String claim;

  @override
  State<_AnalysisAnimation> createState() => _AnalysisAnimationState();
}

class _AnalysisAnimationState extends State<_AnalysisAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _phaseCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _breathCtrl;
  final _scrollCtrl = ScrollController();
  int _lastVisibleCount = 0;

  static const _modelMeta = [
    (label: 'Claude Haiku',  color: Color(0xFFD4704A), asset: 'assets/Claudelogo.png'),
    (label: 'GPT-4o Mini',  color: Color(0xFF10A37F), asset: 'assets/GPTlogo.png'),
    (label: 'Gemini Flash', color: Color(0xFF4285F4), asset: 'assets/Geminilogo.png'),
  ];

  late final List<({double phase, int model, String text})> _messages;

  @override
  void initState() {
    super.initState();
    final claim = widget.claim;
    final short = claim.length > 48 ? '${claim.substring(0, 45)}…' : claim;
    _messages = [
      (phase: 0.08, model: 0, text: 'Evaluating: "$short"'),
      (phase: 0.17, model: 1, text: 'Cross-referencing claim against known fact-check databases…'),
      (phase: 0.25, model: 2, text: 'Scanning for emotional language and persuasive framing…'),
      (phase: 0.34, model: 0, text: 'Source attribution appears absent or unverifiable.'),
      (phase: 0.42, model: 2, text: 'Linguistic signals suggest persuasive framing.'),
      (phase: 0.50, model: 1, text: 'No peer-reviewed citations found to support this claim.'),
      (phase: 0.58, model: 0, text: 'Credibility indicators are inconsistent with reliable reporting.'),
      (phase: 0.65, model: 1, text: 'Concur — statistical claims lack methodological grounding.'),
      (phase: 0.72, model: 2, text: 'Pattern matches known misinformation structures.'),
      (phase: 0.80, model: 0, text: 'Finalizing credibility score and evidence assessment…'),
      (phase: 0.87, model: 1, text: 'Scores submitted to synthesis layer.'),
      (phase: 0.94, model: 2, text: 'Consensus reached. Deferring to final synthesis.'),
    ];

    _phaseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 11))
      ..forward();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    _breathCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _phaseCtrl.dispose();
    _pulseCtrl.dispose();
    _breathCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String _phaseLabel(double phase) {
    if (phase < 0.15) return 'Querying models…';
    if (phase < 0.50) return 'Each model is analyzing your claim…';
    if (phase < 0.85) return 'Comparing results across models…';
    return 'Synthesizing final answer…';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_phaseCtrl, _pulseCtrl, _breathCtrl]),
      builder: (context, _) {
        final phase   = _phaseCtrl.value;
        final pulse   = _pulseCtrl.value;
        final breath  = _breathCtrl.value;
        final isSynth = phase > 0.85;

        final visible = _messages.where((m) => phase >= m.phase).toList();
        if (visible.length != _lastVisibleCount) {
          _lastVisibleCount = visible.length;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        return Column(
          children: [
            // ── Triangle canvas ──────────────────────────────────────────────
            SizedBox(
              height: 180,
              child: LayoutBuilder(builder: (context, constraints) {
                final w = constraints.maxWidth;
                const h = 180.0;
                const r = 22.0;

                final positions = [
                  Offset(w * 0.5,  32.0),
                  Offset(32.0,     148.0),
                  Offset(w - 32.0, 148.0),
                ];

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: Size(w, h),
                      painter: _CouncilPainter(
                        positions: positions,
                        phase: phase,
                        pulse: pulse,
                        colors: [
                          _modelMeta[0].color,
                          _modelMeta[1].color,
                          _modelMeta[2].color,
                        ],
                      ),
                    ),
                    ..._modelMeta.asMap().entries.map((e) {
                      final i   = e.key;
                      final m   = e.value;
                      final pos = positions[i];
                      final scale = 1.0 + breath * 0.045;
                      return Positioned(
                        left: pos.dx - r,
                        top:  pos.dy - r,
                        child: Transform.scale(
                          scale: scale,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: r * 2,
                                height: r * 2,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: isSynth ? _kAccent : m.color.withOpacity(0.7),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isSynth ? _kAccent : m.color)
                                          .withOpacity(isSynth ? 0.4 : 0.2),
                                      blurRadius: isSynth ? 14 : 8,
                                      spreadRadius: isSynth ? 2 : 0,
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: Image.asset(m.asset, fit: BoxFit.contain),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                m.label,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: isSynth ? _kAccent : m.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ),
            const SizedBox(height: 12),

            // ── Conversation feed ────────────────────────────────────────────
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final msg  = visible[index];
                    final meta = _modelMeta[msg.model];
                    final opacity = ((phase - msg.phase) / 0.06).clamp(0.0, 1.0);
                    return Opacity(
                      opacity: opacity,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: meta.color.withOpacity(0.45),
                                  width: 1.5,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Image.asset(meta.asset, fit: BoxFit.contain),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    meta.label,
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: meta.color,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 11, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: meta.color.withOpacity(0.07),
                                      borderRadius: const BorderRadius.only(
                                        topRight:    Radius.circular(12),
                                        bottomLeft:  Radius.circular(12),
                                        bottomRight: Radius.circular(12),
                                      ),
                                      border: Border.all(
                                          color: meta.color.withOpacity(0.15)),
                                    ),
                                    child: Text(
                                      msg.text,
                                      style: _m(
                                        size: 12,
                                        weight: FontWeight.w500,
                                        color: _kPrimary,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Phase label ──────────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(
                _phaseLabel(phase),
                key: ValueKey(_phaseLabel(phase)),
                style: _m(size: 12, weight: FontWeight.w700, color: _kSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),

            // ── Progress bar ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: phase,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isSynth ? _kAccent : const Color(0xFF6366F1),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _CouncilPainter extends CustomPainter {
  _CouncilPainter({
    required this.positions,
    required this.phase,
    required this.pulse,
    required this.colors,
  });

  final List<Offset> positions;
  final double phase;
  final double pulse;
  final List<Color> colors;

  static const _pairs = [(0, 1), (1, 2), (0, 2)];

  @override
  void paint(Canvas canvas, Size size) {
    if (phase < 0.04) return;

    final lineAlpha = (phase / 0.15).clamp(0.0, 1.0);
    final isSynth   = phase > 0.85;
    final center    = Offset(size.width / 2, size.height * 0.50);

    // Lines
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFCBD5E1).withOpacity(lineAlpha * 0.55);
    for (final (a, b) in _pairs) {
      canvas.drawLine(positions[a], positions[b], linePaint);
    }

    if (phase < 0.12) return;

    // Particles
    for (final (a, b) in _pairs) {
      final end = isSynth ? center : positions[b];
      _drawParticle(canvas, positions[a], end, pulse, colors[a], 1.0);
      if (!isSynth) {
        _drawParticle(
          canvas, positions[b], positions[a],
          (pulse + 0.5) % 1.0, colors[b], 0.45,
        );
      }
    }

    // Synthesis center glow
    if (isSynth) {
      final gp = ((phase - 0.85) / 0.15).clamp(0.0, 1.0);
      canvas.drawCircle(
        center, 22 * gp,
        Paint()
          ..color = _kAccent.withOpacity(0.22 * gp)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
      canvas.drawCircle(
        center, 5 * gp,
        Paint()..color = _kAccent.withOpacity(0.85 * gp),
      );
    }
  }

  void _drawParticle(
      Canvas canvas, Offset from, Offset to, double t, Color color, double opacity) {
    final pos = Offset.lerp(from, to, t)!;
    canvas.drawCircle(
      pos, 8,
      Paint()
        ..color = color.withOpacity(0.18 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(pos, 3.5, Paint()..color = color.withOpacity(opacity));
  }

  @override
  bool shouldRepaint(_CouncilPainter old) =>
      old.phase != phase || old.pulse != pulse;
}

// ── Verdict / flag style helpers ──────────────────────────────────────────────
({Color color, Color bg, String label, String icon}) _verdictStyle(String v) {
  switch (v) {
    case 'LIKELY_TRUE':  return (color: _kAccent,                bg: const Color(0xFFEFFFF5), label: 'LIKELY TRUE',      icon: '✅');
    case 'LIKELY_FALSE': return (color: _kDanger,                bg: const Color(0xFFFFEDE8), label: 'LIKELY MISLEADING', icon: '⚠');
    case 'SATIRE':       return (color: const Color(0xFF8B5CF6), bg: const Color(0xFFEDE9FE), label: 'SATIRE',            icon: '😄');
    default:             return (color: const Color(0xFFF59E0B), bg: const Color(0xFFFEF9C3), label: 'UNCERTAIN',         icon: '⚠');
  }
}

({String emoji, Color bg, Color accent}) _flagStyle(String type) {
  switch (type) {
    case 'EMOTIONAL_LANGUAGE': return (emoji: '🔥', bg: const Color(0xFFFEF3C7), accent: const Color(0xFFF59E0B));
    case 'NO_SOURCE':          return (emoji: '📍', bg: const Color(0xFFFFEDE8), accent: const Color(0xFFEF4444));
    case 'KNOWN_PATTERN':      return (emoji: '🔄', bg: const Color(0xFFEDE9FE), accent: const Color(0xFF8B5CF6));
    case 'MISLEADING_STATS':   return (emoji: '📊', bg: const Color(0xFFFFF7ED), accent: const Color(0xFFF97316));
    case 'OUTDATED':           return (emoji: '🕐', bg: const Color(0xFFF0F9FF), accent: const Color(0xFF0EA5E9));
    case 'SATIRE':             return (emoji: '😄', bg: const Color(0xFFEDE9FE), accent: const Color(0xFF8B5CF6));
    default:                   return (emoji: '🚩', bg: const Color(0xFFF1F5F9), accent: _kSecondary);
  }
}

String _titleCase(String s) => s
    .replaceAll('_', ' ')
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

// ── Results panel ─────────────────────────────────────────────────────────────
class _ResultsPanel extends StatefulWidget {
  const _ResultsPanel({required this.result, required this.query});
  final AnalysisResult result;
  final String query;

  @override
  State<_ResultsPanel> createState() => _ResultsPanelState();
}

class _ResultsPanelState extends State<_ResultsPanel> {
  bool _sourcesExpanded = false;
  bool _loadingSources = false;
  bool _sourcesError = false;
  bool _debateMode = false;
  List<({String title, String url, String description})> _sources = [];

  static const _kApiKey = kOpenRouterApiKey;

  Future<void> _toggleSources() async {
    if (_loadingSources) return;

    // Collapse if already expanded
    if (_sourcesExpanded) {
      HapticFeedback.selectionClick();
      setState(() => _sourcesExpanded = false);
      return;
    }

    // Expand
    HapticFeedback.mediumImpact();
    setState(() { _sourcesExpanded = true; _sourcesError = false; });
    if (_sources.isNotEmpty) return; // Already fetched, just re-expand

    // Fetch sources
    setState(() => _loadingSources = true);
    try {
      final q = widget.query.isNotEmpty ? widget.query : widget.result.synthesis.summary;
      final resp = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_kApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'openai/gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': 'You are a trusted sources finder. Always respond with ONLY a raw JSON array, no markdown, no explanation.',
            },
            {
              'role': 'user',
              'content': 'For this claim, provide exactly 4 real, reputable online sources. '
                  'Format: [{"title":"...","url":"https://...","description":"One sentence."},...]\n\n'
                  'Claim: "$q"',
            }
          ],
          'max_tokens': 700,
          'temperature': 0.1,
        }),
      );
      if (!mounted) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = (data['choices'] as List).first['message']['content'] as String;
      // Extract JSON array robustly even if model adds surrounding text
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      final jsonStr = (start != -1 && end > start) ? raw.substring(start, end + 1) : raw.trim();
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final parsed = list
          .whereType<Map>()
          .map((e) => (
                title: (e['title'] as String?) ?? '',
                url: (e['url'] as String?) ?? '',
                description: (e['description'] as String?) ?? '',
              ))
          .where((s) => s.title.isNotEmpty)
          .toList();
      if (!mounted) return;
      if (parsed.isEmpty) {
        setState(() { _loadingSources = false; _sourcesError = true; });
        return;
      }
      setState(() { _sources = parsed; _loadingSources = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loadingSources = false; _sourcesError = true; });
      // Keep _sourcesExpanded = true so the error card is visible
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.result.synthesis;
    final vs = _verdictStyle(s.finalVerdict);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Score + summary ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: const Color(0x0F000000), blurRadius: 20, offset: const Offset(0, 6))
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _ScoreRing(score: s.finalScore.toDouble(), color: vs.color, size: 80, strokeWidth: 8),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: vs.bg,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text('${vs.icon} ${vs.label}',
                              style: _m(size: 10, weight: FontWeight.w800, color: vs.color, spacing: 0.5)),
                        ),
                        const SizedBox(height: 8),
                        Text('Credibility Score: ${s.finalScore}/100',
                            style: _m(size: 13, weight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('${s.flags.length} flag${s.flags.length == 1 ? '' : 's'} detected',
                            style: _m(size: 12, weight: FontWeight.w500, color: _kSecondary)),
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
                  color: _kBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('💡 ${s.summary}',
                    style: _m(size: 12, weight: FontWeight.w600, color: _kPrimary, height: 1.6)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Bias Fingerprint ───────────────────────────────────────────────
        BiasFingerprintCard(
          fingerprint: BiasFingerprint.fromAnalysis(widget.result),
        ),
        const SizedBox(height: 16),

        // ── Model council ──────────────────────────────────────────────────
        if (widget.result.modelResults.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🤖', style: TextStyle(fontSize: 15)),
                    const SizedBox(width: 8),
                    Text('Model Council', style: _m(size: 14, weight: FontWeight.w900)),
                    const Spacer(),
                    _CouncilModeToggle(
                      debateMode: _debateMode,
                      onChanged: (v) => setState(() => _debateMode = v),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: _debateMode
                      ? _DebateThread(
                          key: const ValueKey('debate'),
                          modelResults: widget.result.modelResults,
                          synthesis: widget.result.synthesis,
                        )
                      : Column(
                          key: const ValueKey('scores'),
                          children: [
                            ...widget.result.modelResults.asMap().entries.map((e) {
                              final i = e.key;
                              final m = e.value;
                              return Padding(
                                padding: EdgeInsets.only(
                                    bottom: i < widget.result.modelResults.length - 1 ? 10 : 0),
                                child: m.failed
                                    ? _ModelFailedRow(model: m)
                                    : _ModelScoreRow(model: m),
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Agreements ─────────────────────────────────────────────────────
        if (s.agreements.isNotEmpty) ...[
          _PointsCard(
            icon: '🤝', title: 'All models agree',
            points: s.agreements,
            bg: const Color(0xFFEFFFF5), accent: _kAccent,
          ),
          const SizedBox(height: 12),
        ],

        // ── Conflicts ──────────────────────────────────────────────────────
        if (s.conflicts.isNotEmpty) ...[
          _PointsCard(
            icon: '⚡', title: 'Where they differ',
            points: s.conflicts,
            bg: const Color(0xFFFFFBEB), accent: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 16),
        ],

        // ── Flags ──────────────────────────────────────────────────────────
        if (s.flags.isNotEmpty) ...[
          Row(
            children: [
              Text('Why we flagged this', style: _m(size: 16, weight: FontWeight.w900)),
              const Spacer(),
              Text('${s.flags.length} ${s.flags.length == 1 ? 'reason' : 'reasons'}',
                  style: _m(size: 12, weight: FontWeight.w600, color: _kSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          ...s.flags.asMap().entries.map((e) => Padding(
            padding: EdgeInsets.only(bottom: e.key < s.flags.length - 1 ? 12 : 0),
            child: _FlagCard(flag: e.value),
          )),
          const SizedBox(height: 16),
        ],

        // ── What to do ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What should you do?', style: _m(size: 13, weight: FontWeight.w800)),
              const SizedBox(height: 12),
              ...[
                ('✅', 'Check a fact-checking site like Snopes or FullFact'),
                ('🔗', 'Look for peer-reviewed studies, not social posts'),
                ('🤔', 'Ask: Who benefits if people believe this?'),
              ].map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.$1, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t.$2,
                        style: _m(size: 12, weight: FontWeight.w500, color: _kSecondary, height: 1.5))),
                  ],
                ),
              )),
              _PressBtn(
                onTap: _loadingSources ? null : _toggleSources,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _sourcesExpanded ? _kAccent.withValues(alpha: 0.06) : Colors.transparent,
                    border: Border.all(color: _kAccent, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _loadingSources
                      ? const SizedBox(
                          height: 18,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
                            ),
                          ),
                        )
                      : Text(
                          _sourcesExpanded ? 'Hide Trusted Sources ↑' : 'View Trusted Sources →',
                          textAlign: TextAlign.center,
                          style: _m(size: 13, weight: FontWeight.w700, color: _kAccent),
                        ),
                ),
              ),
              // ── Expanding sources card ─────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: !_sourcesExpanded
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _loadingSources
                            ? const SizedBox(
                                height: 56,
                                child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: _kAccent),
                                ),
                              )
                            : _sourcesError
                                ? Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF7F7),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFFFCDD2)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Could not load sources.',
                                            style: _m(
                                                size: 12,
                                                weight: FontWeight.w700,
                                                color: _kDanger)),
                                        const SizedBox(height: 6),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _sourcesError = false;
                                              _sourcesExpanded = false;
                                            });
                                            _toggleSources();
                                          },
                                          child: Text('Tap here to retry →',
                                              style: _m(
                                                  size: 12,
                                                  weight: FontWeight.w600,
                                                  color: _kAccent)),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text('🔗',
                                              style: TextStyle(fontSize: 13)),
                                          const SizedBox(width: 6),
                                          Text('Trusted Sources',
                                              style: _m(
                                                  size: 12,
                                                  weight: FontWeight.w800,
                                                  color: _kSecondary)),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      ..._sources.asMap().entries.map((e) {
                                        final src = e.value;
                                        return Padding(
                                          padding: EdgeInsets.only(
                                              bottom: e.key < _sources.length - 1
                                                  ? 8
                                                  : 0),
                                          child: Material(
                                            color: _kBackground,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              onTap: () async {
                                                HapticFeedback.lightImpact();
                                                var urlStr = src.url;
                                                if (!urlStr.startsWith('http')) {
                                                  urlStr = 'https://$urlStr';
                                                }
                                                final uri = Uri.tryParse(urlStr);
                                                if (uri != null) {
                                                  try {
                                                    await launchUrl(uri,
                                                        mode: LaunchMode.externalApplication);
                                                  } catch (_) {
                                                    await launchUrl(uri,
                                                        mode: LaunchMode.platformDefault);
                                                  }
                                                }
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12),
                                                  border: Border.all(
                                                      color: const Color(
                                                          0xFFE2E8F0)),
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(src.title,
                                                              style: _m(
                                                                  size: 12,
                                                                  weight: FontWeight
                                                                      .w700)),
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(src.description,
                                                              style: _m(
                                                                  size: 11,
                                                                  weight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color:
                                                                      _kSecondary,
                                                                  height:
                                                                      1.4)),
                                                          const SizedBox(
                                                              height: 6),
                                                          Text(src.url,
                                                              style: _m(
                                                                size: 10,
                                                                weight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: const Color(
                                                                    0xFF1D4ED8),
                                                              ).copyWith(
                                                                decoration:
                                                                    TextDecoration
                                                                        .underline,
                                                                decorationColor:
                                                                    const Color(
                                                                        0xFF1D4ED8),
                                                              ),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              maxLines: 1),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Icon(
                                                        Icons.open_in_new,
                                                        size: 15,
                                                        color: Color(
                                                            0xFF1D4ED8)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                      }),
                                    ],
                                  ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Model score row ───────────────────────────────────────────────────────────
class _ModelScoreRow extends StatelessWidget {
  const _ModelScoreRow({required this.model});
  final ModelResult model;

  @override
  Widget build(BuildContext context) {
    final vs = _verdictStyle(model.verdict);
    return Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(model.model,
              style: _m(size: 11, weight: FontWeight.w700, color: _kSecondary),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(builder: (_, c) => Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: model.credibilityScore / 100),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOut,
                builder: (_, v, _) => Container(
                  height: 8,
                  width: c.maxWidth * v,
                  decoration: BoxDecoration(
                    color: vs.color,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ],
          )),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 26,
          child: Text('${model.credibilityScore}',
              style: _m(size: 11, weight: FontWeight.w800),
              textAlign: TextAlign.right),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: vs.bg, borderRadius: BorderRadius.circular(100)),
          child: Text(model.verdict.replaceAll('_', ' '),
              style: _m(size: 9, weight: FontWeight.w800, color: vs.color)),
        ),
      ],
    );
  }
}

// ── Failed model row ──────────────────────────────────────────────────────────
class _ModelFailedRow extends StatelessWidget {
  const _ModelFailedRow({required this.model});
  final ModelResult model;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 112,
          child: Text(model.model,
              style: _m(size: 11, weight: FontWeight.w700, color: _kSecondary),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            model.error ?? 'Failed',
            style: _m(size: 11, weight: FontWeight.w500, color: _kSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text('UNAVAILABLE',
              style: _m(size: 9, weight: FontWeight.w800, color: _kSecondary)),
        ),
      ],
    );
  }
}

// ── Agreements / conflicts card ───────────────────────────────────────────────
class _PointsCard extends StatelessWidget {
  const _PointsCard({
    required this.icon, required this.title,
    required this.points, required this.bg, required this.accent,
  });
  final String icon, title;
  final List<String> points;
  final Color bg, accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Text(title, style: _m(size: 13, weight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          ...points.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•', style: _m(size: 13, weight: FontWeight.w700, color: accent)),
                const SizedBox(width: 8),
                Expanded(child: Text(p,
                    style: _m(size: 12, weight: FontWeight.w500, color: _kPrimary, height: 1.5))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ── Flag card ─────────────────────────────────────────────────────────────────
class _FlagCard extends StatelessWidget {
  const _FlagCard({required this.flag});
  final AnalysisFlag flag;

  @override
  Widget build(BuildContext context) {
    final fs = _flagStyle(flag.type);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fs.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fs.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: const Color(0x0F000000), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Center(child: Text(fs.emoji, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titleCase(flag.type), style: _m(size: 13, weight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(flag.explanation,
                    style: _m(size: 12, weight: FontWeight.w500, color: _kSecondary, height: 1.55)),
                if (flag.quote.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('"${flag.quote}"',
                      style: _m(size: 11, weight: FontWeight.w600, color: fs.accent, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Council mode toggle ───────────────────────────────────────────────────────
class _CouncilModeToggle extends StatelessWidget {
  const _CouncilModeToggle({required this.debateMode, required this.onChanged});
  final bool debateMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(100),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModePill(
            label: 'Scores',
            active: !debateMode,
            onTap: () { HapticFeedback.selectionClick(); onChanged(false); },
          ),
          _ModePill(
            label: 'Debate',
            active: debateMode,
            onTap: () { HapticFeedback.selectionClick(); onChanged(true); },
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          boxShadow: active
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 1))]
              : [],
        ),
        child: Text(
          label,
          style: _m(size: 11, weight: FontWeight.w700, color: active ? _kPrimary : _kSecondary),
        ),
      ),
    );
  }
}

// ── Debate thread ─────────────────────────────────────────────────────────────
class _DebateThread extends StatelessWidget {
  const _DebateThread({super.key, required this.modelResults, required this.synthesis});
  final List<ModelResult> modelResults;
  final Synthesis synthesis;

  static Color _colorFor(String model) {
    if (model.contains('Claude'))      return const Color(0xFFD4704A);
    if (model.contains('GPT'))         return const Color(0xFF10A37F);
    if (model.contains('Gemini'))      return const Color(0xFF4285F4);
    if (model.contains('Web Search'))  return const Color(0xFF0EA5E9);
    return _kSecondary;
  }

  static String _assetFor(String model) {
    if (model.contains('Claude'))      return 'assets/Claudelogo.png';
    if (model.contains('GPT'))         return 'assets/GPTlogo.png';
    if (model.contains('Gemini'))      return 'assets/Geminilogo.png';
    if (model.contains('Web Search'))  return 'assets/GPTlogo.png';
    return 'assets/Claudelogo.png';
  }

  @override
  Widget build(BuildContext context) {
    final valid  = modelResults.where((m) => !m.failed).toList();
    final failed = modelResults.where((m) => m.failed).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < valid.length; i++) ...[
          _DebateBubble(
            model: valid[i],
            color: _colorFor(valid[i].model),
            asset: _assetFor(valid[i].model),
          ),
          if (i < valid.length - 1) ...[
            const SizedBox(height: 8),
            if (valid[i].verdict != valid[i + 1].verdict)
              _DisputeChip(modelA: valid[i].model, modelB: valid[i + 1].model),
            const SizedBox(height: 8),
          ],
        ],
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...failed.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ModelFailedRow(model: m),
          )),
        ],
        const SizedBox(height: 12),
        _FinalRulingCard(synthesis: synthesis),
      ],
    );
  }
}

// ── Debate bubble ─────────────────────────────────────────────────────────────
class _DebateBubble extends StatefulWidget {
  const _DebateBubble({required this.model, required this.color, required this.asset});
  final ModelResult model;
  final Color color;
  final String asset;

  @override
  State<_DebateBubble> createState() => _DebateBubbleState();
}

class _DebateBubbleState extends State<_DebateBubble> {
  bool _expanded = false;
  static const _kMaxChars = 110;

  @override
  Widget build(BuildContext context) {
    final vs     = _verdictStyle(widget.model.verdict);
    final full   = widget.model.reasoning;
    final isLong = full.length > _kMaxChars;
    final display = _expanded || !isLong ? full : '${full.substring(0, _kMaxChars)}…';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: widget.color.withValues(alpha: 0.4), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Image.asset(widget.asset, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.model.model,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: widget.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: vs.bg, borderRadius: BorderRadius.circular(100)),
                child: Text('${vs.icon} ${vs.label}',
                    style: _m(size: 9, weight: FontWeight.w800, color: vs.color)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '"$display"',
            style: _m(size: 12, weight: FontWeight.w500, color: _kPrimary, height: 1.55),
          ),
          if (isLong) ...[
            const SizedBox(height: 5),
            GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); setState(() => _expanded = !_expanded); },
              child: Text(
                _expanded ? 'Show less ↑' : 'Read more ↓',
                style: _m(size: 11, weight: FontWeight.w700, color: widget.color),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Score: ${widget.model.credibilityScore}/100',
                  style: _m(size: 11, weight: FontWeight.w700, color: _kSecondary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text('${widget.model.confidence} confidence',
                    style: _m(size: 9, weight: FontWeight.w700, color: _kSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Dispute chip ──────────────────────────────────────────────────────────────
class _DisputeChip extends StatelessWidget {
  const _DisputeChip({required this.modelA, required this.modelB});
  final String modelA, modelB;

  static String _short(String n) => n.split(' ').first;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚡', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            Text(
              '${_short(modelA)} & ${_short(modelB)} disagree on verdict',
              style: _m(size: 11, weight: FontWeight.w700, color: const Color(0xFFD97706)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Final ruling card ─────────────────────────────────────────────────────────
class _FinalRulingCard extends StatelessWidget {
  const _FinalRulingCard({required this.synthesis});
  final Synthesis synthesis;

  @override
  Widget build(BuildContext context) {
    final vs = _verdictStyle(synthesis.finalVerdict);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [vs.color.withValues(alpha: 0.08), vs.color.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vs.color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏛️', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Why the Council decided:',
                    style: _m(size: 12, weight: FontWeight.w900)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: vs.bg, borderRadius: BorderRadius.circular(100)),
                child: Text('${vs.icon} ${vs.label}',
                    style: _m(size: 9, weight: FontWeight.w800, color: vs.color)),
              ),
            ],
          ),
          if (synthesis.conflicts.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...synthesis.conflicts.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚡', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(c,
                        style: _m(size: 11, weight: FontWeight.w600, color: _kPrimary, height: 1.5)),
                  ),
                ],
              ),
            )),
          ],
          const SizedBox(height: 8),
          Text(synthesis.summary,
              style: _m(size: 12, weight: FontWeight.w600, color: _kPrimary, height: 1.55)),
        ],
      ),
    );
  }
}

// ── Prediction prompt (shown during scanning) ──────────────────────────────────
class _PredictionPrompt extends StatelessWidget {
  const _PredictionPrompt({required this.onPrediction});
  final void Function(String) onPrediction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤔', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('Before the AI responds…',
                  style: _m(size: 13, weight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Do you think this claim is true or false?',
            style: _m(size: 12, weight: FontWeight.w500, color: _kSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); onPrediction('true'); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFFFF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kAccent),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('✅', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text('Likely True',
                            style: _m(size: 12, weight: FontWeight.w700, color: _kAccent)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); onPrediction('false'); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEDE8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kDanger),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('⚠️', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text('Likely False',
                            style: _m(size: 12, weight: FontWeight.w700, color: _kDanger)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Helps track your critical-thinking growth',
                style: _m(size: 10, weight: FontWeight.w500, color: _kSecondary)),
          ),
        ],
      ),
    );
  }
}

// ── Prediction locked (user already chose, waiting for AI) ────────────────────
class _PredictionLocked extends StatelessWidget {
  const _PredictionLocked({required this.prediction});
  final String prediction;

  @override
  Widget build(BuildContext context) {
    final isTrue = prediction == 'true';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isTrue ? const Color(0xFFEFFFF5) : const Color(0xFFFFEDE8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isTrue ? _kAccent : _kDanger),
      ),
      child: Row(
        children: [
          Text(isTrue ? '✅' : '⚠️', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Text(
            'Your prediction: ${isTrue ? "Likely True" : "Likely False"} — waiting for AI…',
            style: _m(size: 12, weight: FontWeight.w600,
                color: isTrue ? _kAccent : _kDanger),
          ),
        ],
      ),
    );
  }
}

// ── Prediction result chip (shown after results arrive) ───────────────────────
class _PredictionResultChip extends StatelessWidget {
  const _PredictionResultChip({required this.correct});
  final bool correct;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: correct ? const Color(0xFFEFFFF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: correct ? _kAccent : const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          Text(correct ? '🎉' : '💡', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  correct ? 'You predicted correctly! +5 pts' : 'Learning moment! +1 pt',
                  style: _m(
                      size: 13,
                      weight: FontWeight.w800,
                      color: correct ? _kAccent : const Color(0xFFD97706)),
                ),
                const SizedBox(height: 2),
                Text(
                  correct
                      ? 'Your media instincts are sharp. Keep it up.'
                      : 'The AI disagreed with your prediction — check the reasoning below.',
                  style: _m(
                      size: 11,
                      weight: FontWeight.w500,
                      color: correct
                          ? const Color(0xFF15803D)
                          : const Color(0xFF92400E),
                      height: 1.4),
                ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasResults
                  ? 'Try editing the claim above and tap Explain Why again to compare results.'
                  : 'Credexa checks for emotional language, missing sources, and known misinformation patterns — aligned with UN SDG Goal 16.',
              style: _m(size: 12, weight: FontWeight.w600, color: const Color(0xFF1E40AF), height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}
