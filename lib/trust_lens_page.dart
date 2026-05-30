import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'models/analysis_result.dart';
import 'services/analysis_service.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kLens  = Color(0xFF00BFFF);
const _kGreen = Color(0xFF22C55E);
const _kAmber = Color(0xFFF59E0B);
const _kRed   = Color(0xFFEF4444);
const _kBg    = Color(0xFF0D1B2A);

// ─────────────────────────────────────────────────────────────────────────────
//  DATA TYPES
// ─────────────────────────────────────────────────────────────────────────────

class _Flag {
  const _Flag(this.id, this.label, this.severity, this.emoji);
  final String id;
  final String label;
  final int severity; // 0=clean 1=caution 2=alert
  final String emoji;

  Color get color {
    if (severity == 0) return _kGreen;
    if (severity == 1) return _kAmber;
    return _kRed;
  }
}

class _Region {
  const _Region({required this.text, required this.rect, required this.flags});
  final String text;
  final Rect rect;
  final List<_Flag> flags;

  int get severity =>
      flags.isEmpty ? 0 : flags.map((f) => f.severity).reduce(math.max);

  Color get color {
    if (severity == 0) return _kGreen;
    if (severity == 1) return _kAmber;
    return _kRed;
  }
}

class _Face {
  const _Face({required this.rect});
  final Rect rect;
}

// ─────────────────────────────────────────────────────────────────────────────
//  ON-DEVICE QUICK CLASSIFIER
// ─────────────────────────────────────────────────────────────────────────────

class _Classifier {
  // All patterns require ≥2-word phrases so common news words don't trigger false positives.
  // Single words like "crisis", "devastating", "shocking" are deliberately excluded.
  static const _emotional = [
    "mainstream media won't tell",
    "they don't want you to know",
    "hidden from the public",
    "suppressed by the media",
    "what they're hiding from you",
    "real story they won't cover",
    "truth the establishment",
    "woke agenda destroys",
    "they are coming for your",
    "anti-american agenda",
  ];
  static const _clickbait = [
    "you won't believe what",
    "what happened next will",
    "watch before they delete",
    "this one weird trick",
    "doctors hate this",
    "banned from the internet",
    "the video they don't want",
    "share before it's taken down",
    "censored by big tech",
  ];
  static const _usVsThem = [
    'deep state', 'the globalists', 'sheeple',
    'shadow government', 'new world order',
    'great reset agenda', 'mainstream media lies',
    'fake news media', 'they control everything',
    'crisis actors', 'controlled opposition',
  ];
  static const _fear = [
    "your family is in danger",
    "emergency warning for all",
    "before it's too late",
    "imminent threat to your",
    "they will come for your",
    "collapse is coming",
    "prepare for the worst",
    "urgent action required now",
  ];
  static const _unverified = [
    'rumor has it',
    'according to anonymous',
    'unnamed government official',
    'word has it that',
  ];
  static const _propaganda = [
    'plandemic', 'scamdemic', 'stolen election',
    'rigged election', 'false flag attack',
    'government hoax', 'do your own research',
    'wake up sheeple', 'great replacement',
    'white genocide', 'crisis actor',
  ];

  static List<_Flag> classify(String text) {
    final lower = text.toLowerCase();
    final flags  = <_Flag>[];

    // ALL CAPS is intentionally NOT flagged — news chyrons, TV graphics, social
    // media overlays, and headlines routinely use all-caps as a design convention.
    // It is not a reliable signal of manipulation in a camera-based scanner.

    if (_emotional.any((p) => lower.contains(p))) {
      flags.add(const _Flag('emotional', 'Manipulative Framing', 2, '😡'));
    }
    if (_clickbait.any((p) => lower.contains(p))) {
      flags.add(const _Flag('clickbait', 'Clickbait Structure', 1, '🪤'));
    }
    if (_usVsThem.any((p) => lower.contains(p))) {
      flags.add(const _Flag('usvsthem', 'Us-vs-Them Framing', 2, '🎯'));
    }
    if (_fear.any((p) => lower.contains(p))) {
      flags.add(const _Flag('fear', 'Fear Appeal Language', 2, '😱'));
    }
    if (_unverified.any((p) => lower.contains(p))) {
      flags.add(const _Flag('unverified', 'Unverified Claim', 1, '❓'));
    }
    if (_propaganda.any((p) => lower.contains(p))) {
      flags.add(const _Flag('propaganda', 'Propaganda Pattern', 2, '🎭'));
    }
    // Absolutist language — only when paired with strong framing words
    if (RegExp(r'\b(no one|nobody|everyone|everybody)\b').hasMatch(lower) &&
        RegExp(r'\b(always|never|all of them|every single)\b').hasMatch(lower)) {
      flags.add(const _Flag('absolute', 'Absolutist Language', 1, '🔴'));
    }
    return flags;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MOT — SORT-STYLE TRACKER
//  Detector: ML Kit (text + face).  Prediction: 1-D constant-velocity Kalman.
//  Association: greedy IoU (equivalent to Hungarian for n < ~20 objects).
//  Lifecycle: tentative → confirmed → coasting → dead  (per SORT paper).
// ─────────────────────────────────────────────────────────────────────────────

// ── 1-D Kalman filter ───────────────────────────────────────────────────────
// Symmetric 2×2 covariance (p00, p01≡p10, p11).  Process noise is small
// because predict() runs at 60 fps — if it were large, velocity variance would
// explode between detections and the gain would saturate, causing hard snaps.
class _K1D {
  _K1D(double init) : _x = init, _v = 0;
  double _x, _v;
  double _p00 = 100, _p01 = 0, _p11 = 1;
  static const _q0 = 0.25, _q1 = 0.3, _r = 100.0;

  void predict(double dt) {
    _x += _v * dt;
    // F·P·Fᵀ + Q,  F = [[1, dt], [0, 1]]
    final np00 = _p00 + 2 * dt * _p01 + dt * dt * _p11 + _q0;
    final np01 = _p01 + dt * _p11;
    final np11 = _p11 + _q1;
    _p00 = np00; _p01 = np01; _p11 = np11;
  }

  void update(double z) {
    final s  = _p00 + _r;
    final k0 = _p00 / s;
    final k1 = _p01 / s; // symmetric: p10 ≡ p01
    final y  = z - _x;
    _x += k0 * y;
    _v += k1 * y;
    // (I − K·H)·P — evaluate entirely from prior values before overwriting
    final np00 = _p00 * (1 - k0);
    final np01 = _p01 * (1 - k0);
    final np11 = _p11 - k1 * _p01;
    _p00 = np00; _p01 = np01; _p11 = np11;
  }

  double get value => _x;
}

// ── 2-D bounding-box Kalman wrapper ─────────────────────────────────────────
class _KBox {
  _KBox(Rect r)
      : l = _K1D(r.left), t = _K1D(r.top),
        r_ = _K1D(r.right), b = _K1D(r.bottom);
  final _K1D l, t, r_, b;
  void predict(double dt) { l.predict(dt); t.predict(dt); r_.predict(dt); b.predict(dt); }
  void update(Rect r)     { l.update(r.left); t.update(r.top); r_.update(r.right); b.update(r.bottom); }
  Rect get rect           => Rect.fromLTRB(l.value, t.value, r_.value, b.value);
}

// ── SORT track-lifecycle states ──────────────────────────────────────────────
// tentative  : just spawned; not shown until hit-streak reaches _nInit
// confirmed  : visible; actively matched by the detector
// coasting   : visible; detector missed it — Kalman predicts position
// dead       : removed from the track list this cycle
enum _TrackState { tentative, confirmed, coasting }

// Global monotonically-increasing ID so every track has a unique identity.
int _nextTrackId = 0;

// ── Face track ───────────────────────────────────────────────────────────────
class _FaceTrack {
  _FaceTrack(Rect r) : _kbox = _KBox(r), measured = r, id = _nextTrackId++;
  final _KBox _kbox;
  final int   id;
  Rect        measured;           // last detector rect — IoU association target
  _TrackState state     = _TrackState.tentative;
  int         hitStreak = 0;      // consecutive matched detection cycles
  int         missCount = 0;      // consecutive missed detection cycles
  bool        _dead     = false;

  // Require 2 hits before showing — suppresses single-frame ghost detections.
  static const _nInit   = 2;
  // Allow 4 missed cycles (~2.7 s at 1.5 Hz) before deleting a confirmed track.
  static const _maxMiss = 4;

  void predict(double dt) => _kbox.predict(dt);

  void update(Rect r) {
    _kbox.update(r);
    measured  = r;
    missCount = 0;
    hitStreak++;
    if (state != _TrackState.confirmed && hitStreak >= _nInit) {
      state = _TrackState.confirmed;
    }
  }

  void markMissed() {
    hitStreak = 0;
    missCount++;
    // Tentative tracks die on the first miss (they've never been confirmed).
    if (state == _TrackState.tentative || missCount > _maxMiss) {
      _dead = true;
    } else {
      state = _TrackState.coasting;
    }
  }

  bool get isDead    => _dead;
  bool get isVisible => !_dead && state != _TrackState.tentative;
  Rect get rect      => _kbox.rect;
}

// ── Text-region track ────────────────────────────────────────────────────────
class _RegionTrack {
  _RegionTrack(_Region r)
      : _kbox = _KBox(r.rect), measured = r.rect,
        text = r.text, flags = r.flags, id = _nextTrackId++;
  final _KBox  _kbox;
  final int    id;
  Rect         measured;
  String       text;
  List<_Flag>  flags;
  // Text recognition is reliable — confirm immediately, no tentative phase.
  _TrackState  state     = _TrackState.confirmed;
  int          hitStreak = 0;
  int          missCount = 0;
  bool         _dead     = false;

  // Allow 2 missed cycles (~1.3 s) — text exits frame quickly.
  static const _maxMiss = 2;

  void predict(double dt) => _kbox.predict(dt);

  void update(_Region r) {
    _kbox.update(r.rect);
    measured  = r.rect;
    text      = r.text;
    flags     = r.flags;
    missCount = 0;
    hitStreak++;
    if (state == _TrackState.coasting) state = _TrackState.confirmed;
  }

  void markMissed() {
    hitStreak = 0;
    missCount++;
    if (missCount > _maxMiss) { _dead = true; }
    else { state = _TrackState.coasting; }
  }

  bool get isDead    => _dead;
  bool get isVisible => !_dead;
  Rect get rect      => _kbox.rect;

  _Region toRegion() => _Region(text: text, rect: rect, flags: flags);
}

// ─────────────────────────────────────────────────────────────────────────────
//  PAGE WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class TrustLensPage extends StatefulWidget {
  const TrustLensPage({super.key});

  @override
  State<TrustLensPage> createState() => _TrustLensState();
}

class _TrustLensState extends State<TrustLensPage>
    with SingleTickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────────────────────────
  CameraController? _ctrl;
  bool _isReady = false;
  bool _hasError = false;
  String _errorMsg = '';
  bool _useBackCamera = true;
  bool _showIntro    = false;

  // ── ML Kit ──────────────────────────────────────────────────────────────────
  final _textRec = TextRecognizer(script: TextRecognitionScript.latin);
  final _faceDet = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableLandmarks: false,
      enableContours: false,
      enableTracking: false,
      minFaceSize: 0.1,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  // ── Detection state ──────────────────────────────────────────────────────────
  final _faceTracks   = <_FaceTrack>[];
  final _regionTracks = <_RegionTrack>[];
  List<_Region> _regions = []; // latest detections for HUD metrics / auto-check
  bool _isBusy = false;
  bool _isScanning = false;
  int? _selectedIndex;
  Size? _screenSize;
  int _frameSkip = 0;

  // ── Auto fact-check ──────────────────────────────────────────────────────────
  final _resultCache  = <String, AnalysisResult>{};
  final _pendingTexts = <String>{};
  DateTime? _lastAutoCheck;

  // ── Animation ────────────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;

  // ── MOT display lists — only confirmed / coasting tracks are shown ───────────
  List<_Region> get _displayRegions =>
      _regionTracks.where((t) => t.isVisible).map((t) => t.toRegion()).toList();

  List<_Face> get _displayFaces =>
      _faceTracks.where((t) => t.isVisible).map((t) => _Face(rect: t.rect)).toList();

  // ── Computed ─────────────────────────────────────────────────────────────────
  int get _totalFlags => _regions.fold(0, (s, r) => s + r.flags.length);
  int get _trustScore {
    if (_regions.isEmpty) return 100;
    final avg = _regions.fold(0, (s, r) => s + r.severity) / _regions.length;
    return (100 - avg * 40).clamp(0, 100).round();
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseCtrl.addListener(_smoothStep);
    _checkFirstLaunch();
  }

  // ── First-launch gate ─────────────────────────────────────────────────────

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final seen  = prefs.getBool('trust_lens_intro_seen') ?? false;
    if (!seen) {
      if (mounted) setState(() => _showIntro = true);
    } else {
      _initCamera();
    }
  }

  Future<void> _dismissIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trust_lens_intro_seen', true);
    if (mounted) {
      setState(() => _showIntro = false);
      _initCamera();
    }
  }

  // ── Camera lifecycle ─────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMsg = 'No camera found on this device.';
          });
        }
        return;
      }
      final direction = _useBackCamera
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == direction,
        orElse: () => cameras.first,
      );
      _ctrl = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await _ctrl!.initialize();
      if (!mounted) return;
      setState(() => _isReady = true);
      await _ctrl!.startImageStream(_onFrame);
    } catch (e) {
      if (mounted) setState(() { _hasError = true; _errorMsg = e.toString(); });
    }
  }

  Future<void> _flipCamera() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isReady = false;
      _regions = [];
      _faceTracks.clear();
      _regionTracks.clear();
    });
    await _ctrl?.stopImageStream();
    await _ctrl?.dispose();
    _ctrl = null;
    _useBackCamera = !_useBackCamera;
    await _initCamera();
  }

  // ── MOT: SORT algorithm ──────────────────────────────────────────────────────

  // Advance Kalman predictions at 60 fps — gives smooth on-screen motion between
  // the ~1.5 Hz ML Kit detection cycles. AnimatedBuilder redraws automatically
  // via _pulseCtrl, so no setState is needed here.
  void _smoothStep() {
    const dt = 1.0 / 60.0;
    for (final t in _faceTracks)   { t.predict(dt); }
    for (final t in _regionTracks) { t.predict(dt); }
  }

  static double _iou(Rect a, Rect b) {
    final ix    = math.max(0.0, math.min(a.right, b.right)   - math.max(a.left, b.left));
    final iy    = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.top,  b.top));
    final inter = ix * iy;
    if (inter == 0) return 0;
    return inter / (a.width * a.height + b.width * b.height - inter);
  }

  // Greedy IoU assignment: detection index → track index.
  // Uses the last *measured* rect (not the Kalman-predicted one) so association
  // stays reliable even after the prediction has drifted between detection cycles.
  static Map<int, int> _assign(
    List<Rect> dets, List<Rect> tracks, double threshold,
  ) {
    final result      = <int, int>{};
    final usedTracks  = <int>{};
    for (int di = 0; di < dets.length; di++) {
      double best = threshold;
      int bestTi  = -1;
      for (int ti = 0; ti < tracks.length; ti++) {
        if (usedTracks.contains(ti)) continue;
        final s = _iou(dets[di], tracks[ti]);
        if (s > best) { best = s; bestTi = ti; }
      }
      if (bestTi >= 0) { result[di] = bestTi; usedTracks.add(bestTi); }
    }
    return result;
  }

  void _updateFaceTracks(List<_Face> newFaces) {
    final assignment = _assign(
      newFaces.map((f) => f.rect).toList(),
      _faceTracks.map((t) => t.measured).toList(),
      0.25,
    );
    final matchedTracks = assignment.values.toSet();
    // Update matched tracks; advance lifecycle for unmatched ones.
    for (int ti = 0; ti < _faceTracks.length; ti++) {
      if (!matchedTracks.contains(ti)) { _faceTracks[ti].markMissed(); }
    }
    assignment.forEach((di, ti) => _faceTracks[ti].update(newFaces[di].rect));
    // Spawn new tracks for unmatched detections — collected after the loop so
    // freshly spawned tracks aren't accidentally matched in the same cycle.
    final matchedDets = assignment.keys.toSet();
    for (int di = 0; di < newFaces.length; di++) {
      if (!matchedDets.contains(di)) { _faceTracks.add(_FaceTrack(newFaces[di].rect)); }
    }
    _faceTracks.removeWhere((t) => t.isDead);
  }

  void _updateRegionTracks(List<_Region> newRegions) {
    final assignment = _assign(
      newRegions.map((r) => r.rect).toList(),
      _regionTracks.map((t) => t.measured).toList(),
      0.20,
    );
    final matchedTracks = assignment.values.toSet();
    for (int ti = 0; ti < _regionTracks.length; ti++) {
      if (!matchedTracks.contains(ti)) { _regionTracks[ti].markMissed(); }
    }
    assignment.forEach((di, ti) => _regionTracks[ti].update(newRegions[di]));
    final matchedDets = assignment.keys.toSet();
    for (int di = 0; di < newRegions.length; di++) {
      if (!matchedDets.contains(di)) { _regionTracks.add(_RegionTrack(newRegions[di])); }
    }
    _regionTracks.removeWhere((t) => t.isDead);
  }

  void _onFrame(CameraImage image) {
    _frameSkip++;
    if (_frameSkip < 20) return;
    _frameSkip = 0;
    if (_isBusy || _screenSize == null) return;
    _isBusy = true;
    _processFrame(image);
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      if (mounted) setState(() => _isScanning = true);
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final results = await Future.wait([
        _textRec.processImage(inputImage),
        _faceDet.processImage(inputImage),
      ]);
      if (!mounted) return;

      final recognized = results[0] as RecognizedText;
      final faceList   = results[1] as List<Face>;
      final imgSize    = Size(image.width.toDouble(), image.height.toDouble());
      // previewSize is the camera feed resolution; use it (not imgSize) for display
      // mapping so coords align with FittedBox(fit: BoxFit.cover) geometry.
      final previewSize = _ctrl!.value.previewSize ?? imgSize;
      final screen     = _screenSize!;
      final isFront    = !_useBackCamera;

      final newRegions = <_Region>[];
      for (final block in recognized.blocks) {
        final t = block.text.trim();
        if (t.length < 8) continue;
        final r = _transformTextBox(block.boundingBox, imgSize, previewSize, screen, isFront);
        if (r.right < 0 || r.left > screen.width ||
            r.bottom < 0 || r.top > screen.height) { continue; }
        newRegions.add(_Region(
          text: t,
          rect: r,
          flags: _Classifier.classify(t),
        ));
      }

      final newFaces = faceList
          .map((f) => _Face(rect: _transformFaceBox(f.boundingBox, imgSize, previewSize, screen, isFront)))
          .where((f) =>
              f.rect.right > 0 && f.rect.left < screen.width &&
              f.rect.bottom > 0 && f.rect.top < screen.height)
          .toList();

      setState(() {
        _updateFaceTracks(newFaces);
        _updateRegionTracks(newRegions);
        _regions    = newRegions; // latest detections for HUD metrics / auto-check
        _isScanning = false;
      });
      _maybeAutoCheck();
    } catch (_) {
      if (mounted) setState(() => _isScanning = false);
    } finally {
      _isBusy = false;
    }
  }

  InputImage? _buildInputImage(CameraImage img) {
    try {
      if (Platform.isIOS) {
        return InputImage.fromBytes(
          bytes: img.planes[0].bytes,
          metadata: InputImageMetadata(
            size: Size(img.width.toDouble(), img.height.toDouble()),
            rotation: InputImageRotation.rotation90deg,
            format: InputImageFormat.bgra8888,
            bytesPerRow: img.planes[0].bytesPerRow,
          ),
        );
      }
      // Android: combine YUV420 planes into NV21
      final nv21 = _yuv420ToNv21(img);
      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: InputImageRotation.rotation90deg,
          format: InputImageFormat.nv21,
          bytesPerRow: img.width,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _yuv420ToNv21(CameraImage img) {
    final y = img.planes[0];
    final u = img.planes[1];
    final v = img.planes[2];
    final out = Uint8List(img.width * img.height * 3 ~/ 2);
    int idx = 0;
    for (int row = 0; row < img.height; row++) {
      for (int col = 0; col < img.width; col++) {
        out[idx++] = y.bytes[row * y.bytesPerRow + col];
      }
    }
    // Interleave V then U for NV21; each UV sample is 1 byte per plane (planar YUV420)
    for (int row = 0; row < img.height ~/ 2; row++) {
      for (int col = 0; col < img.width ~/ 2; col++) {
        out[idx++] = v.bytes[row * v.bytesPerRow + col];
        out[idx++] = u.bytes[row * u.bytesPerRow + col];
      }
    }
    return out;
  }

  // Scale/crop/mirror: maps portrait previewSize coords → screen pixels.
  // Uses previewSize (not imgSize) because FittedBox.cover is sized by previewSize.
  Rect _scaleToScreen(
    double pLeft, double pTop, double pRight, double pBottom,
    double portW, double portH, Size screen, bool isFront,
  ) {
    final scale = math.max(screen.width / portW, screen.height / portH);
    final cropX = (portW * scale - screen.width)  / 2;
    final cropY = (portH * scale - screen.height) / 2;

    double left  = pLeft  * scale - cropX;
    double right = pRight * scale - cropX;
    final top    = pTop   * scale - cropY;
    final bottom = pBottom * scale - cropY;

    if (isFront) {
      final l = screen.width - right;
      right = screen.width - left;
      left  = l;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  // Face detector returns RAW landscape pixel coords (no internal rotation applied).
  // Steps: normalize by imgSize → apply 90° CW rotation → scale to previewSize portrait.
  Rect _transformFaceBox(
    Rect box, Size imgSize, Size previewSize, Size screen, bool isFront,
  ) {
    // 90° CW: portrait_x = 1 - ly_norm, portrait_y = lx_norm
    final leftNorm   = (imgSize.height - box.bottom) / imgSize.height;
    final topNorm    = box.left  / imgSize.width;
    final rightNorm  = (imgSize.height - box.top)    / imgSize.height;
    final bottomNorm = box.right / imgSize.width;

    final portW = previewSize.height; // landscape height → portrait width
    final portH = previewSize.width;  // landscape width  → portrait height
    return _scaleToScreen(
      leftNorm * portW, topNorm * portH,
      rightNorm * portW, bottomNorm * portH,
      portW, portH, screen, isFront,
    );
  }

  // Text recognizer is orientation-aware and returns boxes already in portrait
  // pixel space (x ∈ [0, imgSize.height), y ∈ [0, imgSize.width)).
  // Normalize by imgSize portrait dims, then scale to previewSize portrait.
  Rect _transformTextBox(
    Rect box, Size imgSize, Size previewSize, Size screen, bool isFront,
  ) {
    final imgPortW = imgSize.height;
    final imgPortH = imgSize.width;
    final portW = previewSize.height;
    final portH = previewSize.width;
    return _scaleToScreen(
      (box.left  / imgPortW) * portW,
      (box.top   / imgPortH) * portH,
      (box.right / imgPortW) * portW,
      (box.bottom / imgPortH) * portH,
      portW, portH, screen, isFront,
    );
  }

  // ── Interaction ──────────────────────────────────────────────────────────────

  void _onTap(Offset tap) {
    HapticFeedback.lightImpact();
    final dispRegions = _displayRegions;
    for (var i = 0; i < dispRegions.length; i++) {
      if (dispRegions[i].rect.inflate(10).contains(tap)) {
        setState(() => _selectedIndex = i);
        _showRegionSheet(dispRegions[i]);
        return;
      }
    }
    for (final face in _displayFaces) {
      if (face.rect.inflate(10).contains(tap)) {
        _showFaceSheet();
        return;
      }
    }
    setState(() => _selectedIndex = null);
  }

  // ── Auto fact-check ──────────────────────────────────────────────────────────

  void _maybeAutoCheck() {
    if (_regions.isEmpty) return;
    if (_pendingTexts.isNotEmpty) return; // only one check at a time
    final now = DateTime.now();
    if (_lastAutoCheck != null &&
        now.difference(_lastAutoCheck!).inSeconds < 10) { return; }

    // Pick best candidate: flagged regions first, then by text length
    final candidates = _regions
        .where((r) => r.text.length >= 25)
        .where((r) => !_resultCache.containsKey(r.text))
        .where((r) => !_pendingTexts.contains(r.text))
        .toList()
      ..sort((a, b) {
        if (a.flags.isEmpty != b.flags.isEmpty) {
          return a.flags.isEmpty ? 1 : -1;
        }
        return b.text.length.compareTo(a.text.length);
      });

    if (candidates.isEmpty) return;
    _lastAutoCheck = now;
    _runAutoCheck(candidates.first.text);
  }

  Future<void> _runAutoCheck(String text) async {
    if (!mounted) return;
    setState(() => _pendingTexts.add(text));
    try {
      final result = await AnalysisService.analyzeRssOnly(text);
      if (!mounted) return;
      setState(() {
        _resultCache[text] = result;
        _pendingTexts.remove(text);
      });
    } catch (_) {
      if (mounted) setState(() => _pendingTexts.remove(text));
    }
  }

  void _showRegionSheet(_Region region) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RegionSheet(
        region:        region,
        initialResult: _resultCache[region.text],
        isChecking:    _pendingTexts.contains(region.text),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selectedIndex = null);
    });
  }

  void _showFaceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FaceSheet(),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ctrl?.dispose();
    _textRec.close();
    _faceDet.close();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera feed ───────────────────────────────────────────────────
          if (_isReady && _ctrl != null)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width:  _ctrl!.value.previewSize!.height,
                  height: _ctrl!.value.previewSize!.width,
                  child:  CameraPreview(_ctrl!),
                ),
              ),
            )
          else if (!_hasError)
            const Center(child: _BootView()),

          if (_hasError) Center(child: _ErrorView(message: _errorMsg)),

          // ── AR overlay + gesture layer ────────────────────────────────────
          if (_isReady)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (_, c) {
                  _screenSize = Size(c.maxWidth, c.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (d) => _onTap(d.localPosition),
                    child: AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _) => CustomPaint(
                        painter: _OverlayPainter(
                          regions:      _displayRegions,
                          faces:        _displayFaces,
                          pulse:        _pulseCtrl.value,
                          selected:     _selectedIndex,
                          isScanning:   _isScanning,
                          resultCache:  _resultCache,
                          pendingTexts: _pendingTexts,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  );
                },
              ),
            ),

          // ── HUD top bar ───────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: _TopBar(
              isScanning: _isScanning,
              trustScore: _trustScore,
              flagCount: _totalFlags,
              faceCount: _faceTracks.where((t) => t.isVisible).length,
              hasDetections: _regionTracks.any((t) => t.isVisible) || _faceTracks.any((t) => t.isVisible),
            ),
          ),

          // ── Camera flip button ────────────────────────────────────────────
          if (_isReady)
            Positioned(
              bottom: 110,
              right: 20,
              child: GestureDetector(
                onTap: _flipCamera,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.flip_camera_ios_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

          // ── Bottom hint ───────────────────────────────────────────────────
          if (_isReady)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _BottomBar(
                regionCount: _regionTracks.where((t) => t.isVisible).length,
                flagCount: _totalFlags,
                faceCount: _faceTracks.where((t) => t.isVisible).length,
              ),
            ),

          // ── First-launch intro (sits on top of everything) ─────────────────
          if (_showIntro)
            Positioned.fill(
              child: _TrustLensIntro(onStart: _dismissIntro),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FIRST-LAUNCH INTRO OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _TrustLensIntro extends StatefulWidget {
  const _TrustLensIntro({required this.onStart});
  final VoidCallback onStart;

  @override
  State<_TrustLensIntro> createState() => _TrustLensIntroState();
}

class _TrustLensIntroState extends State<_TrustLensIntro>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _rotateCtrl;
  late final AnimationController _fadeCtrl;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 0,
    )..forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleStart() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    HapticFeedback.mediumImpact();
    await _fadeCtrl.reverse();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeCtrl,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF07111F), _kBg, Color(0xFF050E18)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 36),
                _buildScanner(),
                const SizedBox(height: 36),
                _buildTitle(),
                const SizedBox(height: 30),
                _buildFeatures(),
                const Spacer(),
                _buildConsent(),
                const SizedBox(height: 20),
                _buildButton(),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return SizedBox(
      width: 190,
      height: 190,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseCtrl, _rotateCtrl]),
        builder: (_, _) {
          final pulse = _pulseCtrl.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: 175 + pulse * 12,
                height: 175 + pulse * 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _kLens.withValues(alpha: 0.07 + pulse * 0.10),
                    width: 1,
                  ),
                ),
              ),
              // Mid glow ring
              Container(
                width: 148 + pulse * 6,
                height: 148 + pulse * 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _kLens.withValues(alpha: 0.13 + pulse * 0.13),
                    width: 1.5,
                  ),
                ),
              ),
              // Rotating dashed ring
              Transform.rotate(
                angle: _rotateCtrl.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(122, 122),
                  painter: _DashedRingPainter(
                    color: _kLens.withValues(alpha: 0.55),
                  ),
                ),
              ),
              // Inner circle with eye icon
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kLens.withValues(alpha: 0.07),
                  border: Border.all(
                    color: _kLens.withValues(alpha: 0.45),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kLens.withValues(alpha: 0.18 + pulse * 0.18),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.remove_red_eye_outlined,
                  color: _kLens,
                  size: 34,
                ),
              ),
              // Viewfinder corner brackets
              CustomPaint(
                size: const Size(190, 190),
                painter: _ViewfinderPainter(
                  color: _kLens.withValues(alpha: 0.65 + pulse * 0.20),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        const Text(
          'TRUST LENS',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w900,
            fontSize: 30,
            letterSpacing: 7,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Real-time truth detection for the world you see',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.50),
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatures() {
    final features = [
      (Icons.document_scanner_outlined, _kLens,  'Live Text Scanning',
          'Frames and reads text visible in your camera in real time.'),
      (Icons.newspaper_outlined,         _kAmber, 'News Verification',
          'Checks claims against live headlines — no AI guesswork.'),
      (Icons.verified_outlined,          _kGreen, 'Truth Verdict Overlay',
          'Shows ✓ / ⚠ / ✗ badges directly on detected regions.'),
    ];

    return Column(
      children: features.map((f) {
        final (icon, color, title, desc) = f;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.11),
                  border: Border.all(
                    color: color.withValues(alpha: 0.28),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      desc,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.42),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildConsent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline,
            size: 15,
            color: Colors.white.withValues(alpha: 0.38),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Requires camera access to scan your surroundings. '
              'No images or video are ever stored or transmitted.',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.38),
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton() {
    return GestureDetector(
      onTap: _handleStart,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, _) => Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                _kLens,
                Color.lerp(
                  _kLens,
                  const Color(0xFF0077E6),
                  0.55 + _pulseCtrl.value * 0.25,
                )!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _kLens.withValues(
                    alpha: 0.32 + _pulseCtrl.value * 0.18),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'Enable Camera & Start',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Rotating dashed ring for the scanner graphic
class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final r = (size.width - 1.5) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    const dashCount = 20;
    const step = (2 * math.pi) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      final start = step * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start, step * 0.6, false, paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}

// Four corner viewfinder brackets
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    const arm = 20.0;
    const margin = 10.0;
    final w = size.width;
    final h = size.height;
    // Top-left
    canvas.drawLine(const Offset(margin, margin), const Offset(margin + arm, margin), paint);
    canvas.drawLine(const Offset(margin, margin), const Offset(margin, margin + arm), paint);
    // Top-right
    canvas.drawLine(Offset(w - margin, margin), Offset(w - margin - arm, margin), paint);
    canvas.drawLine(Offset(w - margin, margin), Offset(w - margin, margin + arm), paint);
    // Bottom-left
    canvas.drawLine(Offset(margin, h - margin), Offset(margin + arm, h - margin), paint);
    canvas.drawLine(Offset(margin, h - margin), Offset(margin, h - margin - arm), paint);
    // Bottom-right
    canvas.drawLine(Offset(w - margin, h - margin), Offset(w - margin - arm, h - margin), paint);
    canvas.drawLine(Offset(w - margin, h - margin), Offset(w - margin, h - margin - arm), paint);
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
//  AR OVERLAY PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _OverlayPainter extends CustomPainter {
  const _OverlayPainter({
    required this.regions,
    required this.faces,
    required this.pulse,
    required this.isScanning,
    required this.resultCache,
    required this.pendingTexts,
    this.selected,
  });

  final List<_Region> regions;
  final List<_Face> faces;
  final double pulse;
  final bool isScanning;
  final Map<String, AnalysisResult> resultCache;
  final Set<String> pendingTexts;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    if (isScanning) _drawScanLine(canvas, size);
    for (var i = 0; i < regions.length; i++) {
      _drawRegion(canvas, regions[i], i == selected);
      _drawVerdictBadge(canvas, regions[i]);
    }
    for (final face in faces) {
      _drawFace(canvas, face);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 0.5;
    const step = 44.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _drawScanLine(Canvas canvas, Size size) {
    final y = pulse * size.height;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            _kGreen.withValues(alpha: 0.55),
            _kGreen.withValues(alpha: 0.9),
            _kGreen.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2))
        ..strokeWidth = 2,
    );
  }

  void _drawRegion(Canvas canvas, _Region r, bool selected) {
    final color = r.color;
    final rect = RRect.fromRectAndRadius(r.rect, const Radius.circular(5));

    // Fill
    canvas.drawRRect(
      rect,
      Paint()..color = color.withValues(
          alpha: selected ? 0.3 : (r.severity == 0 ? 0.06 : 0.15)),
    );

    // Glow halo on flagged regions
    if (r.severity > 0 || selected) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: selected ? 0.55 : 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }

    // Crisp border
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: selected ? 1.0 : 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.2 : 1.3,
    );

    _drawCorners(canvas, r.rect, color);

    if (r.flags.isNotEmpty) _drawBadge(canvas, r.rect, r);
  }

  void _drawCorners(Canvas canvas, Rect r, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const L = 12.0;
    canvas.drawLine(r.topLeft,     r.topLeft + const Offset(L, 0),  p);
    canvas.drawLine(r.topLeft,     r.topLeft + const Offset(0, L),  p);
    canvas.drawLine(r.topRight,    r.topRight + const Offset(-L, 0), p);
    canvas.drawLine(r.topRight,    r.topRight + const Offset(0, L),  p);
    canvas.drawLine(r.bottomLeft,  r.bottomLeft + const Offset(L, 0),  p);
    canvas.drawLine(r.bottomLeft,  r.bottomLeft + const Offset(0, -L), p);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(-L, 0), p);
    canvas.drawLine(r.bottomRight, r.bottomRight + const Offset(0, -L), p);
  }

  void _drawBadge(Canvas canvas, Rect rect, _Region r) {
    final color = r.color;
    final label = r.flags.length == 1
        ? '${r.flags.first.emoji} ${r.flags.first.label.split(" ").first}'
        : '${r.flags.first.emoji} ${r.flags.length} signals';

    final tp = TextPainter(
      text: TextSpan(
        text: ' $label ',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          fontFamily: 'Montserrat',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);

    final bw = tp.width + 4;
    final bh = tp.height + 6;
    final bx = math.max(0.0, rect.right - bw);
    final by = math.max(0.0, rect.top - bh - 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(4)),
      Paint()..color = color.withValues(alpha: 0.95),
    );
    tp.paint(canvas, Offset(bx + 2, by + 3));
  }

  void _drawFace(Canvas canvas, _Face face) {
    final rect = face.rect;
    final color = _kLens;
    const r = Radius.circular(10);

    // Pulsing glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, r),
      Paint()
        ..color = color.withValues(alpha: 0.08 + pulse * 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 + pulse * 10),
    );

    // Animated border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, r),
      Paint()
        ..color = color.withValues(alpha: 0.5 + pulse * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    _drawCorners(canvas, rect, color.withValues(alpha: 0.85 + pulse * 0.15));

    // FACE label
    final tp = TextPainter(
      text: const TextSpan(
        text: ' 👤 FACE ',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          fontFamily: 'Montserrat',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final lx = rect.left + 4;
    final ly = rect.top + 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(lx - 2, ly - 1, tp.width + 4, tp.height + 4),
        const Radius.circular(4),
      ),
      Paint()..color = color.withValues(alpha: 0.9),
    );
    tp.paint(canvas, Offset(lx, ly + 2));
  }

  void _drawVerdictBadge(Canvas canvas, _Region r) {
    final result  = resultCache[r.text];
    final pending = pendingTexts.contains(r.text);
    if (!pending && result == null) return;

    String label;
    Color  bg;

    if (pending) {
      label = '⏳ VERIFYING...';
      bg    = Colors.black.withValues(alpha: 0.70);
    } else {
      final score = result!.synthesis.finalScore;
      if (score >= 65) {
        label = '✓ TRUE  $score%';
        bg    = _kGreen.withValues(alpha: 0.92);
      } else if (score >= 40) {
        label = '⚠ UNCERTAIN  $score%';
        bg    = _kAmber.withValues(alpha: 0.92);
      } else {
        label = '✗ FALSE  $score%';
        bg    = _kRed.withValues(alpha: 0.92);
      }
    }

    final tp = TextPainter(
      text: TextSpan(
        text: ' $label ',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          fontFamily: 'Montserrat',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 220);

    final bw = tp.width + 4;
    final bh = tp.height + 6;
    final bx = math.max(0.0, r.rect.left);
    final by = r.rect.bottom + 4;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(4)),
      Paint()..color = bg,
    );
    tp.paint(canvas, Offset(bx + 2, by + 3));
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.pulse        != pulse        ||
      old.regions      != regions      ||
      old.faces        != faces        ||
      old.selected     != selected     ||
      old.isScanning   != isScanning   ||
      old.resultCache  != resultCache  ||
      old.pendingTexts != pendingTexts;
}

// ─────────────────────────────────────────────────────────────────────────────
//  HUD — TOP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isScanning,
    required this.trustScore,
    required this.flagCount,
    required this.faceCount,
    required this.hasDetections,
  });
  final bool isScanning;
  final int trustScore;
  final int flagCount;
  final int faceCount;
  final bool hasDetections;

  Color get _scoreColor {
    if (trustScore >= 72) return _kGreen;
    if (trustScore >= 48) return _kAmber;
    return _kRed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black.withValues(alpha: 0.88), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
          child: Row(
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 12),

              // Title + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'TRUST LENS',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _LivePill(isScanning: isScanning),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isScanning
                          ? 'Analyzing frame...'
                          : flagCount > 0
                              ? '$flagCount signal${flagCount == 1 ? '' : 's'} detected'
                              : 'Point at any screen to scan',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),

              // Score + face badges
              if (hasDetections) ...[
                _HUDBadge(
                    value: '$trustScore', sub: 'TRUST', color: _scoreColor),
                if (faceCount > 0) ...[
                  const SizedBox(width: 6),
                  _HUDBadge(
                      value: '$faceCount',
                      sub: faceCount == 1 ? 'FACE' : 'FACES',
                      color: _kLens),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HUDBadge extends StatelessWidget {
  const _HUDBadge(
      {required this.value, required this.sub, required this.color});
  final String value;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.0,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 7,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.5),
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatefulWidget {
  const _LivePill({required this.isScanning});
  final bool isScanning;

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isScanning ? _kGreen : Colors.red;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10 + _c.value * 0.08),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              widget.isScanning ? 'SCANNING' : 'LIVE',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 7,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HUD — BOTTOM BAR
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.regionCount,
    required this.flagCount,
    required this.faceCount,
  });
  final int regionCount;
  final int flagCount;
  final int faceCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.82)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (regionCount > 0 || faceCount > 0) ...[
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (regionCount > 0)
                      _Chip(
                        '$regionCount region${regionCount == 1 ? '' : 's'}',
                        '📝',
                        Colors.white.withValues(alpha: 0.75),
                      ),
                    if (flagCount > 0)
                      _Chip('$flagCount flag${flagCount == 1 ? '' : 's'}',
                          '⚠️', _kAmber),
                    if (faceCount > 0)
                      _Chip('$faceCount face${faceCount == 1 ? '' : 's'}',
                          '👤', _kLens),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Text(
                regionCount > 0
                    ? 'Tap any highlighted region to run AI analysis'
                    : 'Point at text on any screen to begin',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.emoji, this.color);
  final String label;
  final String emoji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  REGION DETAIL SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _RegionSheet extends StatefulWidget {
  const _RegionSheet({
    required this.region,
    this.initialResult,
    this.isChecking = false,
  });
  final _Region region;
  final AnalysisResult? initialResult;
  final bool isChecking;

  @override
  State<_RegionSheet> createState() => _RegionSheetState();
}

class _RegionSheetState extends State<_RegionSheet> {
  bool _analyzing = false;
  AnalysisResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult; // pre-populate if auto-check already finished
  }

  Future<void> _runAnalysis() async {
    setState(() { _analyzing = true; _error = null; });
    try {
      final r = await AnalysisService.analyzeWithSearch(widget.region.text);
      if (mounted) setState(() { _result = r; _analyzing = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _analyzing = false; });
    }
  }

  String get _label {
    switch (widget.region.severity) {
      case 0:  return '✓ CLEAR';
      case 1:  return '⚠ SUSPICIOUS';
      default: return '🚫 FLAGGED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.region;
    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: ctrl,
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 24 + MediaQuery.of(context).padding.bottom),
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Severity + count
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: r.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: r.color.withValues(alpha: 0.5)),
                  ),
                  child: Text(_label,
                      style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: r.color)),
                ),
                const Spacer(),
                Text(
                  '${r.flags.length} signal${r.flags.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Detected text
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text(
                '"${r.text}"',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.82),
                  height: 1.6,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Flags list
            if (r.flags.isNotEmpty)
              ...r.flags.map((flag) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Text(flag.emoji,
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(flag.label,
                              style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: flag.color)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: flag.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            flag.severity == 2 ? 'HIGH' : 'MED',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: flag.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ))
            else
              Row(children: [
                const Text('✅', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Text('No manipulation signals detected',
                    style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kGreen)),
              ]),

            const SizedBox(height: 18),

            // Analysis result / CTA
            if (_result != null) ...[
              _AnalysisCard(result: _result!),
              const SizedBox(height: 10),
              // Still allow refreshing with full AI council
              GestureDetector(
                onTap: _runAnalysis,
                child: Center(
                  child: Text(
                    '🔄 Re-run AI Council Analysis',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ] else if (_analyzing)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
                      SizedBox(height: 12),
                      Text('AI Council analyzing...',
                          style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 12,
                              color: Colors.white54)),
                    ],
                  ),
                ),
              )
            else ...[
              // Show "background check running" notice if auto-check is in progress
              if (widget.isChecking)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _kLens.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kLens.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              color: _kLens, strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Background verification running — result will appear on the overlay automatically.',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.55),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Error: $_error',
                      style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          color: _kRed)),
                ),
              GestureDetector(
                onTap: _runAnalysis,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🤖', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 10),
                      Text(
                        'Run AI Council Analysis',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Claude · GPT-4 · Gemini will analyze this text',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Compact analysis result card shown inside the region sheet
class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.result});
  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final s = result.synthesis;
    final c = s.finalScore >= 70
        ? _kGreen
        : s.finalScore >= 40
            ? _kAmber
            : _kRed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.withValues(alpha: 0.14), c.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${s.finalScore}',
                style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: c,
                    height: 1.0),
              ),
              Text('/100',
                  style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.3))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(s.finalVerdict.toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: c,
                        letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '💡 ${s.summary}',
            style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.5),
          ),
          if (s.conflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...s.conflicts.take(2).map((conflict) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⚡', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(conflict,
                            style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 11,
                                color:
                                    Colors.white.withValues(alpha: 0.52),
                                height: 1.4)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FACE DETAIL SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _FaceSheet extends StatelessWidget {
  const _FaceSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _kLens.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kLens.withValues(alpha: 0.4)),
                ),
                child: const Center(
                    child: Text('👤', style: TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Face Detected',
                        style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _kLens)),
                    Text('On-device face detection active',
                        style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            color: Colors.white54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Text(
              'Credexa detected a human face in view. For deepfake analysis, use the Visual Scanner — it processes still images with advanced AI models to detect facial manipulation.',
              style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  color: Colors.white60,
                  height: 1.6),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Center(
                child: Text('Close',
                    style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOADING / ERROR VIEWS
// ─────────────────────────────────────────────────────────────────────────────

class _BootView extends StatelessWidget {
  const _BootView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: _kGreen, strokeWidth: 2),
        const SizedBox(height: 16),
        Text(
          'Initializing Trust Lens...',
          style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.65)),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📷', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          const Text('Camera Unavailable',
              style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            message.length > 120
                ? '${message.substring(0, 118)}…'
                : message,
            style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.42),
                height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Text('Go Back',
                  style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
