import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'auth_service.dart';
import 'bias_fingerprint.dart';
import 'models/debias_result.dart';
import 'services/debias_service.dart';
import 'services/ocr_service.dart';
import 'services/profile_service.dart';
import 'services/shared_content_router.dart';

// ── Shared constants ──────────────────────────────────────────────────────────
const _kPrimary    = Color(0xFF1E293B);
const _kSecondary  = Color(0xFF64748B);
const _kAccent     = Color(0xFF22C55E);
const _kBackground = Color(0xFFF1F5F9);

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

// ── Bias pattern glossary ─────────────────────────────────────────────────────
class _GlossaryEntry {
  const _GlossaryEntry({
    required this.icon,
    required this.definition,
    required this.psychology,
    required this.example,
    required this.howToSpot,
  });
  final String icon, definition, psychology, example, howToSpot;
}

const _glossary = <String, _GlossaryEntry>{
  'Loaded Language': _GlossaryEntry(
    icon: '🔥',
    definition: 'Words chosen specifically to trigger an emotional reaction rather than describe facts neutrally.',
    psychology: 'Emotional words bypass your critical thinking and go straight to your fear or anger response, making you accept claims without questioning them.',
    example: '"Death panels" instead of "end-of-life care advisory boards" — used in the 2009 US healthcare debate to trigger fear of government control.',
    howToSpot: 'Ask: "Does this word describe what happened, or does it tell me how to feel about it?"',
  ),
  'Fear Appeal': _GlossaryEntry(
    icon: '😱',
    definition: 'Exaggerating dangers or consequences to make you afraid so you stop thinking critically.',
    psychology: 'Fear switches your brain into survival mode. In that state you seek certainty and are much more likely to trust whoever is warning you.',
    example: '"If we don\'t act now, civilization will collapse" — climate and political messaging both use catastrophic language to override nuanced debate.',
    howToSpot: 'Ask: "Is the danger described with specific evidence, or is it just vague catastrophising?"',
  ),
  'Vilification': _GlossaryEntry(
    icon: '🎭',
    definition: 'Painting an entire group of people as evil, corrupt, or subhuman to make opposing them seem morally correct.',
    psychology: 'Once your brain labels a group as "bad", it stops processing individual facts about them. This is the root of dehumanisation.',
    example: '"Corrupt elites" — used across the political spectrum to dismiss any argument from the opposing group without engaging with it.',
    howToSpot: 'Ask: "Is this describing what people did with evidence, or just declaring them evil?"',
  ),
  'Us-vs-Them Framing': _GlossaryEntry(
    icon: '⚔️',
    definition: 'Dividing the world into two opposing sides — good "us" and bad "them" — leaving no room for nuance or common ground.',
    psychology: 'Tribal thinking is hardwired into humans. Once you\'re placed on a "team", you automatically defend that team\'s claims and dismiss the other side.',
    example: '"Real Americans" vs "radical elites" — any statement that implies only one group represents the true nation uses this technique.',
    howToSpot: 'Ask: "Are there people who don\'t fit neatly into either side being described?"',
  ),
  'Absolute Language': _GlossaryEntry(
    icon: '🚨',
    definition: 'Using words like "always", "never", "all", "entire", "completely", or "forever" to make a claim sound universal when reality is always more complex.',
    psychology: 'Certainty feels safer than uncertainty. Absolute language exploits this by making complicated situations seem simple and decided.',
    example: '"Politicians never tell the truth" — the word "never" is impossible to verify and shuts down any attempt at nuanced evaluation.',
    howToSpot: 'Replace "always/never/all" with a number. If you can\'t, the claim is probably overstated.',
  ),
  'Missing Balance': _GlossaryEntry(
    icon: '📍',
    definition: 'Presenting only one side of a story as if the other side doesn\'t exist, doesn\'t have arguments, or isn\'t worth hearing.',
    psychology: 'When you only ever hear one position, your brain starts treating it as obvious common sense rather than one perspective among many.',
    example: 'A news segment that interviews only people who oppose a policy, with zero input from supporters or experts who disagree.',
    howToSpot: 'Ask: "Who or what is completely absent from this story? Who would disagree and why?"',
  ),
  'One-Sided Framing': _GlossaryEntry(
    icon: '📣',
    definition: 'Selecting only the facts that support one conclusion, ignoring or burying facts that complicate the picture.',
    psychology: 'Selective exposure to information creates a distorted mental map of reality. Your decisions can then be based on an incomplete picture.',
    example: 'A report on a drug\'s benefits that omits side effects discovered in the same study.',
    howToSpot: 'Ask: "What would I expect to see in a balanced account of this topic that is missing here?"',
  ),
  'Misleading Stats': _GlossaryEntry(
    icon: '📊',
    definition: 'Using real numbers in ways that create false impressions — cherry-picking data, omitting context, or misrepresenting what a statistic actually measures.',
    psychology: 'Numbers feel objective and scientific, so they\'re trusted without scrutiny. This makes statistical manipulation especially effective.',
    example: '"Crime up 100%" sounds alarming — but if there were 2 incidents last year and 4 this year, the real number is tiny.',
    howToSpot: 'Always ask: "What is the baseline? How big is the sample? What does this number actually measure?"',
  ),
  'Sensationalism': _GlossaryEntry(
    icon: '💥',
    definition: 'Exaggerating the drama, scale, or urgency of an event to maximise emotional impact and engagement — even at the expense of accuracy.',
    psychology: 'Your brain evolved to pay attention to extreme events. Sensational content exploits this by making everything feel like an emergency.',
    example: '"SHOCK: Scientists STUNNED by discovery that CHANGES EVERYTHING" — the ALL-CAPS and extreme words are designed to hijack your attention.',
    howToSpot: 'Ask: "Is this actually the biggest thing that happened today, or does it just feel that way because of how it\'s written?"',
  ),
  'Unverified Claim': _GlossaryEntry(
    icon: '❓',
    definition: 'Stating something as a proven fact when it is actually an allegation, rumour, or unproven assertion.',
    psychology: 'Repeated claims start to feel true even when unproven — called the "illusory truth effect". First impressions stick, corrections don\'t.',
    example: '"Scientists prove X" when the study was preliminary and not peer-reviewed yet.',
    howToSpot: 'Look for source citations. If a dramatic claim has no link to a primary source, treat it as unverified.',
  ),
  'Emotional Manipulation': _GlossaryEntry(
    icon: '💔',
    definition: 'Using emotional stories or imagery to override your rational judgement and get you to accept a conclusion without examining the evidence.',
    psychology: 'A single vivid personal story activates your empathy system far more powerfully than statistics, even when the stats represent millions of people.',
    example: 'A policy article that opens with a heart-wrenching personal story, then makes a sweeping policy claim without data.',
    howToSpot: 'Ask: "Is the emotional story representative of the broader situation, or is it an extreme outlier being used to stand in for a general rule?"',
  ),
  'Scapegoating': _GlossaryEntry(
    icon: '🐐',
    definition: 'Blaming all of society\'s problems on one specific group, ignoring the real, complex causes.',
    psychology: 'Complex problems with no clear cause are psychologically uncomfortable. Scapegoating provides a simple villain, which feels like an explanation even when it isn\'t.',
    example: 'Blaming immigration for unemployment while ignoring automation, trade policy, and corporate decisions.',
    howToSpot: 'Ask: "Would removing this group actually fix the problem? What other factors are being ignored?"',
  ),
};

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
      onTapDown: (_) { _c.forward(); HapticFeedback.mediumImpact(); },
      onTapUp: (_) { _c.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(scale: 1 - _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DE-BIAS PAGE
// ─────────────────────────────────────────────────────────────────────────────
class DebiasPage extends StatefulWidget {
  const DebiasPage({super.key});

  @override
  State<DebiasPage> createState() => _DebiasPageState();
}

class _DebiasPageState extends State<DebiasPage> {
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
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))]
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
              const SliverToBoxAdapter(child: _DebiasToolSection()),
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
//  DE-BIAS TOOL SECTION
// ─────────────────────────────────────────────────────────────────────────────

const _exampleTexts = [
  (
    label: 'Climate headline',
    text: 'Radical climate alarmists demand economy-destroying carbon taxes that will devastate working families and plunge millions into poverty.',
  ),
  (
    label: 'Vaccine claim',
    text: 'Dangerous experimental jabs are being forced on innocent children by power-hungry governments ignoring the cries of concerned parents.',
  ),
  (
    label: 'Election story',
    text: 'Corrupt politicians rigged the entire election, stealing votes from real patriots and destroying democracy forever.',
  ),
];

class _DebiasToolSection extends StatefulWidget {
  const _DebiasToolSection();

  @override
  State<_DebiasToolSection> createState() => _DebiasToolSectionState();
}

class _DebiasToolSectionState extends State<_DebiasToolSection>
    with SingleTickerProviderStateMixin {
  final _textCtrl = TextEditingController();
  bool _rewriting = false;
  bool _showResults = false;
  String? _error;
  DebiasResult? _result;
  late final AnimationController _resultsCtrl;

  Uint8List? _imageBytes;
  String _imageMimeType = 'image/jpeg';
  String? _imageName;

  @override
  void initState() {
    super.initState();
    _resultsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    // Listen for content routed from the Share Extension
    SharedContentRouter.forDebias.addListener(_onSharedContent);
    // Consume immediately if already set (e.g. routed before this page mounted)
    if (SharedContentRouter.forDebias.value != null) _onSharedContent();
  }

  @override
  void dispose() {
    SharedContentRouter.forDebias.removeListener(_onSharedContent);
    _textCtrl.dispose();
    _resultsCtrl.dispose();
    super.dispose();
  }

  void _onSharedContent() {
    final content = SharedContentRouter.forDebias.value;
    if (content == null || !mounted) return;
    SharedContentRouter.forDebias.value = null; // consume
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
          _extractAndRewriteUrl(text);
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

  Future<void> _extractAndRewriteUrl(String url) async {
    setState(() { _rewriting = true; _showResults = false; _error = null; });
    try {
      final extracted = await OcrService.extractFromUrl(url);
      if (!mounted) return;
      if (extracted.trim().isNotEmpty) {
        _textCtrl.text = extracted.trim();
        _imageBytes = null;
        _imageName = null;
        await _rewrite();
      } else {
        setState(() {
          _textCtrl.text = url;
          _rewriting = false;
          _error = 'Could not extract post content from this link. '
              'Try sharing a screenshot of the post instead.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _textCtrl.text = url;
        _rewriting = false;
        _error = 'Could not extract post content from this link. '
            'Try sharing a screenshot of the post instead.';
      });
    }
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

  void _clearImage() => setState(() { _imageBytes = null; _imageName = null; _showResults = false; });

  Future<void> _rewrite() async {
    final text = _textCtrl.text.trim();
    final hasImage = _imageBytes != null;
    if (text.isEmpty && !hasImage) return;

    setState(() { _rewriting = true; _showResults = false; _error = null; });
    _resultsCtrl.reset();

    try {
      final DebiasResult result;
      if (hasImage) {
        result = await DebiasService.debiasImage(_imageBytes!, _imageMimeType);
        if (mounted && result.originalText.isNotEmpty) {
          _textCtrl.text = result.originalText;
        }
      } else {
        result = await DebiasService.debiasText(text);
      }
      if (!mounted) return;
      setState(() { _rewriting = false; _showResults = true; _result = result; });
      _resultsCtrl.forward();
      ProfileService.incrementDebias();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rewriting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _loadExample(String text) {
    setState(() {
      _textCtrl.text = text;
      _imageBytes = null;
      _imageName = null;
      _showResults = false;
      _error = null;
      _result = null;
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
          _Label(text: 'CREDEXA · DE-BIAS TOOL'),
          const SizedBox(height: 8),
          Text('Rewrite in\nNeutral Tone',
              style: _m(size: 32, weight: FontWeight.w900, height: 1.1)),
          const SizedBox(height: 8),
          Text(
            'Paste any text or share a screenshot. GPT rewrites it in balanced language and shows you exactly what bias techniques were used — from three different perspectives.',
            style: _m(size: 14, weight: FontWeight.w500, color: _kSecondary, height: 1.65),
          ),
          const SizedBox(height: 24),

          _InputCard(
            textCtrl: _textCtrl,
            rewriting: _rewriting,
            imageBytes: _imageBytes,
            imageName: _imageName,
            onRewrite: _rewriting ? null : _rewrite,
            onChanged: () {
              if (_showResults) setState(() { _showResults = false; _result = null; });
            },
            onPickImage: _rewriting ? null : _pickImage,
            onTakePhoto: _rewriting ? null : _takePhoto,
            onClearImage: _clearImage,
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: _m(size: 13, weight: FontWeight.w500, color: const Color(0xFFDC2626), height: 1.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (!_showResults && !_rewriting) ...[
            Text('Try an example:',
                style: _m(size: 12, weight: FontWeight.w700, color: _kSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _exampleTexts
                  .map((e) => _ExampleChip(label: e.label, onTap: () => _loadExample(e.text)))
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],

          if (_showResults && _result != null)
            SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _resultsCtrl, curve: Curves.easeOut)),
              child: FadeTransition(
                opacity: _resultsCtrl,
                child: _ResultsPanel(result: _result!),
              ),
            ),

          if (!_rewriting) _TipCard(hasResults: _showResults),
        ],
      ),
    );
  }
}

// ── Label chip ────────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  const _Label({required this.text});
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
          style: _m(size: 10, weight: FontWeight.w800, color: _kAccent, spacing: 1.1)),
    );
  }
}

// ── Example chip ──────────────────────────────────────────────────────────────
class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))
          ],
        ),
        child: Text(label, style: _m(size: 12, weight: FontWeight.w600, color: _kSecondary)),
      ),
    );
  }
}

// ── Input card ────────────────────────────────────────────────────────────────
class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.textCtrl,
    required this.rewriting,
    required this.onRewrite,
    required this.onChanged,
    required this.onPickImage,
    required this.onTakePhoto,
    required this.onClearImage,
    this.imageBytes,
    this.imageName,
  });
  final TextEditingController textCtrl;
  final bool rewriting;
  final VoidCallback? onRewrite;
  final VoidCallback onChanged;
  final VoidCallback? onPickImage;
  final VoidCallback? onTakePhoto;
  final VoidCallback onClearImage;
  final Uint8List? imageBytes;
  final String? imageName;

  bool get _hasImage => imageBytes != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: Text('✍️', style: TextStyle(fontSize: 15))),
                ),
                const SizedBox(width: 10),
                Text('Paste Text or Share a Screenshot',
                    style: _m(size: 13, weight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 14),

            if (_hasImage) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(imageBytes!, width: 52, height: 52, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(imageName ?? 'Image',
                              style: _m(size: 12, weight: FontWeight.w700),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('GPT will extract text & de-bias it',
                              style: _m(size: 11, weight: FontWeight.w500, color: _kSecondary)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () { HapticFeedback.lightImpact(); onClearImage(); },
                      child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(child: Icon(Icons.close, size: 14, color: Color(0xFFDC2626))),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (!_hasImage)
              TextField(
                controller: textCtrl,
                maxLines: 5,
                onChanged: (_) => onChanged(),
                style: _m(size: 14, weight: FontWeight.w500, height: 1.65),
                decoration: InputDecoration(
                  hintText: 'Paste a headline, social post, or paragraph with loaded or emotional language…',
                  hintStyle: _m(size: 13, weight: FontWeight.w500, color: const Color(0xFFCBD5E1), height: 1.6),
                  filled: true,
                  fillColor: _kBackground,
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _kAccent, width: 2)),
                ),
              ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _PressBtn(
                    onTap: onPickImage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(color: _kPrimary, borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.photo_library_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('Gallery', style: _m(size: 13, weight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PressBtn(
                    onTap: onTakePhoto,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('Camera', style: _m(size: 13, weight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            _PressBtn(
              onTap: onRewrite,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: rewriting
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: rewriting ? const Color(0xFF86EFAC) : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: rewriting ? [] : [
                    BoxShadow(color: _kAccent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: rewriting
                      ? [
                          const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                          const SizedBox(width: 10),
                          Text(_hasImage ? 'Extracting & Rewriting…' : 'Rewriting…',
                              style: _m(size: 15, weight: FontWeight.w800, color: Colors.white)),
                        ]
                      : [
                          const Text('✍️', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(_hasImage ? 'Extract Text & De-Bias' : 'Rewrite in Neutral Tone',
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
//  RESULTS PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({required this.result});
  final DebiasResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BiasMeter(score: result.biasScore, label: result.biasLabel),
        const SizedBox(height: 16),

        // ── Bias Fingerprint ───────────────────────────────────────────────
        BiasFingerprintCard(
          fingerprint: BiasFingerprint.fromDebias(result),
        ),
        const SizedBox(height: 16),

        if (result.extractedText != null && result.extractedText!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📷', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Text extracted from image: "${result.extractedText}"',
                      style: _m(size: 12, weight: FontWeight.w500, color: const Color(0xFF1E40AF), height: 1.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        _TextCompareCard(
          label: 'ORIGINAL',
          labelColor: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFFF5F5),
          borderColor: const Color(0xFFFECACA),
          icon: '⚠️',
          text: result.originalText,
        ),
        const SizedBox(height: 12),
        _TextCompareCard(
          label: 'NEUTRAL REWRITE',
          labelColor: _kAccent,
          bgColor: const Color(0xFFF0FDF4),
          borderColor: const Color(0xFFBBF7D0),
          icon: '✅',
          text: result.neutralText,
          showCopy: true,
        ),
        const SizedBox(height: 20),

        // ── Feature #2: Three Perspectives ──
        if (result.hasPerspectives) ...[
          _PerspectivesCard(result: result),
          const SizedBox(height: 20),
        ],

        // ── Feature #3: What Changed (with tappable glossary) ──
        if (result.changes.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(child: Text('🔍', style: TextStyle(fontSize: 17))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('What We Changed', style: _m(size: 15, weight: FontWeight.w900)),
                          Text(
                            '${result.changes.length} bias pattern${result.changes.length == 1 ? '' : 's'} removed  •  tap any to learn more',
                            style: _m(size: 11, weight: FontWeight.w500, color: _kSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ...result.changes.asMap().entries.map((e) => Padding(
                      padding: EdgeInsets.only(bottom: e.key < result.changes.length - 1 ? 14 : 0),
                      child: _ChangeRow(item: e.value),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

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
              Text('Why This Matters', style: _m(size: 13, weight: FontWeight.w900)),
              const SizedBox(height: 12),
              ...[
                ('🧠', 'Emotional words activate your brain\'s fear response before you can think critically.'),
                ('⚖️', 'Neutral language gives you the facts — and lets you form your own opinion.'),
                ('🔄', 'Practice spotting loaded language in everything you read, watch, and share.'),
              ].map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$1, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(t.$2,
                              style: _m(size: 12, weight: FontWeight.w500, color: _kSecondary, height: 1.55)),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Bias score meter ──────────────────────────────────────────────────────────
class _BiasMeter extends StatelessWidget {
  const _BiasMeter({required this.score, required this.label});
  final int score;
  final String label;

  Color get _color {
    if (score <= 20) return const Color(0xFF22C55E);
    if (score <= 50) return const Color(0xFFF59E0B);
    if (score <= 80) return const Color(0xFFEF4444);
    return const Color(0xFF991B1B);
  }

  @override
  Widget build(BuildContext context) {
    final fraction = (score / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bias Score', style: _m(size: 12, weight: FontWeight.w700, color: _kSecondary)),
                    const SizedBox(height: 2),
                    Text(label, style: _m(size: 18, weight: FontWeight.w900, color: _color)),
                  ],
                ),
              ),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Center(child: Text('$score', style: _m(size: 18, weight: FontWeight.w900, color: _color))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: _kBackground,
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Neutral', style: _m(size: 10, weight: FontWeight.w600, color: _kSecondary)),
              Text('Manipulative', style: _m(size: 10, weight: FontWeight.w600, color: _kSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Feature #2: Perspectives card ────────────────────────────────────────────
class _PerspectivesCard extends StatefulWidget {
  const _PerspectivesCard({required this.result});
  final DebiasResult result;

  @override
  State<_PerspectivesCard> createState() => _PerspectivesCardState();
}

class _PerspectivesCardState extends State<_PerspectivesCard> {
  int _selected = 1; // 0=left, 1=center, 2=right

  static const _colors = [
    Color(0xFF6366F1), // indigo — left
    Color(0xFF22C55E), // green  — center
    Color(0xFFF59E0B), // amber  — right
  ];

  static const _labels = ['← Left', 'Center', 'Right →'];

  List<DebiasPerspective> get _perspectives => [
        widget.result.leftPerspective!,
        widget.result.centerPerspective!,
        widget.result.rightPerspective!,
      ];

  @override
  Widget build(BuildContext context) {
    final persp = _perspectives[_selected];
    final color = _colors[_selected];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: Text('🌐', style: TextStyle(fontSize: 17))),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Three Perspectives', style: _m(size: 15, weight: FontWeight.w900)),
                  Text('Same story — different framings', style: _m(size: 11, weight: FontWeight.w500, color: _kSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tab selector
          Container(
            decoration: BoxDecoration(
              color: _kBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: List.generate(3, (i) {
                final selected = i == _selected;
                return Expanded(
                  child: GestureDetector(
                    onTap: () { HapticFeedback.selectionClick(); setState(() => _selected = i); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected ? _colors[i] : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: selected
                            ? [BoxShadow(color: _colors[i].withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                            : [],
                      ),
                      child: Text(
                        _labels[i],
                        textAlign: TextAlign.center,
                        style: _m(
                          size: 12, weight: FontWeight.w800,
                          color: selected ? Colors.white : _kSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          // Perspective text
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Container(
              key: ValueKey(_selected),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(persp.label,
                        style: _m(size: 10, weight: FontWeight.w800, color: color, spacing: 0.5)),
                  ),
                  const SizedBox(height: 10),
                  Text(persp.text,
                      style: _m(size: 13, weight: FontWeight.w500, color: _kPrimary, height: 1.7)),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💬', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(persp.note,
                            style: _m(size: 11, weight: FontWeight.w500, color: _kSecondary, height: 1.4)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All three are factual — but the word choices shape how you feel. Neutral gives you facts; the others reveal how real outlets frame the same story.',
                    style: _m(size: 11, weight: FontWeight.w500, color: const Color(0xFF92400E), height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Text compare card ─────────────────────────────────────────────────────────
class _TextCompareCard extends StatelessWidget {
  const _TextCompareCard({
    required this.label,
    required this.labelColor,
    required this.bgColor,
    required this.borderColor,
    required this.icon,
    required this.text,
    this.showCopy = false,
  });
  final String label, icon, text;
  final Color labelColor, bgColor, borderColor;
  final bool showCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(label,
                    style: _m(size: 10, weight: FontWeight.w800, color: labelColor, spacing: 1.0)),
              ),
              if (showCopy)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Neutral rewrite copied!'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.copy_rounded, size: 12, color: _kAccent),
                        const SizedBox(width: 4),
                        Text('Copy', style: _m(size: 11, weight: FontWeight.w700, color: _kAccent)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: _m(size: 13, weight: FontWeight.w500, color: _kPrimary, height: 1.7)),
        ],
      ),
    );
  }
}

// ── Feature #3: Change row with tappable glossary ─────────────────────────────
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.item});
  final DebiasChange item;

  void _showGlossary(BuildContext context) {
    final entry = _glossary[item.type];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GlossarySheet(biasType: item.type, entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasGlossary = _glossary.containsKey(item.type);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _kBackground, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: hasGlossary ? () => _showGlossary(context) : null,
            child: Row(
              children: [
                Text(item.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(item.type, style: _m(size: 12, weight: FontWeight.w800, color: _kPrimary)),
                ),
                if (hasGlossary) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 11, color: _kAccent),
                        const SizedBox(width: 3),
                        Text('Learn', style: _m(size: 10, weight: FontWeight.w700, color: _kAccent)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(item.explanation, style: _m(size: 11, weight: FontWeight.w500, color: _kSecondary, height: 1.5)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)),
                child: Text('Before', style: _m(size: 9, weight: FontWeight.w800, color: const Color(0xFFDC2626), spacing: 0.3)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.original,
                    style: _m(size: 12, weight: FontWeight.w500, color: _kSecondary, height: 1.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(4)),
                child: Text('After', style: _m(size: 9, weight: FontWeight.w800, color: _kAccent, spacing: 0.3)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.rewritten,
                    style: _m(size: 12, weight: FontWeight.w500, color: _kPrimary, height: 1.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Glossary bottom sheet ─────────────────────────────────────────────────────
class _GlossarySheet extends StatelessWidget {
  const _GlossarySheet({required this.biasType, required this.entry});
  final String biasType;
  final _GlossaryEntry? entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: entry == null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No glossary entry for "$biasType" yet.',
                          style: _m(size: 14, weight: FontWeight.w500, color: _kSecondary)),
                    ))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(entry!.icon, style: const TextStyle(fontSize: 28)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(biasType,
                                  style: _m(size: 20, weight: FontWeight.w900)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _GlossarySection(
                          icon: '📖',
                          title: 'What is it?',
                          text: entry!.definition,
                          bgColor: const Color(0xFFF8FAFC),
                        ),
                        const SizedBox(height: 12),
                        _GlossarySection(
                          icon: '🧠',
                          title: 'Why does it work on your brain?',
                          text: entry!.psychology,
                          bgColor: const Color(0xFFF0FDF4),
                        ),
                        const SizedBox(height: 12),
                        _GlossarySection(
                          icon: '📰',
                          title: 'Real-world example',
                          text: entry!.example,
                          bgColor: const Color(0xFFFFFBEB),
                        ),
                        const SizedBox(height: 12),
                        _GlossarySection(
                          icon: '🔎',
                          title: 'How to spot it',
                          text: entry!.howToSpot,
                          bgColor: const Color(0xFFEFF6FF),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlossarySection extends StatelessWidget {
  const _GlossarySection({
    required this.icon,
    required this.title,
    required this.text,
    required this.bgColor,
  });
  final String icon, title, text;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _m(size: 12, weight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(text, style: _m(size: 13, weight: FontWeight.w500, color: _kSecondary, height: 1.6)),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Text('💡', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasResults
                    ? 'Try editing the text above and rewriting again — see how even small word choices shift the tone and perspective.'
                    : 'You can also screenshot a biased post and use the Camera or Gallery button — GPT will extract the text and de-bias it automatically.',
                style: _m(size: 12, weight: FontWeight.w600, color: const Color(0xFF92400E), height: 1.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
