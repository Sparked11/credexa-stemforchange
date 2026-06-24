import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';
import 'models/community_message.dart';
import 'services/community_service.dart';
import 'services/profile_service.dart';

// ── Typography helper ─────────────────────────────────────────────────────────
TextStyle _m({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = const Color(0xFF1E293B),
  double? height,
  double spacing = 0,
}) =>
    TextStyle(
      fontFamily:    'Montserrat',
      fontSize:      size,
      fontWeight:    weight,
      color:         color,
      height:        height,
      letterSpacing: spacing,
    );

const _kAccent     = Color(0xFF22C55E);
const _kReplyColor = Color(0xFF3B82F6);
const _kAiColor    = Color(0xFF6366F1);

Color _typeColor(MessageType type) {
  switch (type) {
    case MessageType.question: return _kAccent;
    case MessageType.reply:    return _kReplyColor;
    case MessageType.ai:       return _kAiColor;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  COMMUNITY HUB PAGE
// ─────────────────────────────────────────────────────────────────────────────
class CommunityHubPage extends StatefulWidget {
  const CommunityHubPage({super.key});

  @override
  State<CommunityHubPage> createState() => _CommunityHubPageState();
}

class _CommunityHubPageState extends State<CommunityHubPage> {
  final _textCtrl = TextEditingController();
  final _scroll   = ScrollController();
  StreamSubscription<List<CommunityMessage>>? _sub;

  List<CommunityMessage> _messages  = [];
  bool   _sending      = false;
  bool   _sendingIsAsk = false;
  bool   _moderating   = false;
  bool   _isAskMode    = true;
  String? _error;

  Uint8List? _pendingImageBytes;
  String?    _pendingMimeType;

  @override
  void initState() {
    super.initState();
    _sub = CommunityService.messagesStream().listen(
      (msgs) {
        if (!mounted) return;
        // With reverse:true the list always starts anchored at the newest
        // message (pixel 0). Only auto-scroll when the user is already there.
        final wasAtBottom = _isAtBottom();
        setState(() { _messages = msgs; _error = null; });
        if (wasAtBottom) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToNewest(animate: true));
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _error = 'Could not load messages. Check your connection.');
      },
    );
  }

  // With reverse:true, pixel 0 IS the newest message end.
  bool _isAtBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.position.pixels <= 80;
  }

  void _scrollToNewest({bool animate = false}) {
    if (!_scroll.hasClients) return;
    if (animate) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source:       ImageSource.gallery,
      imageQuality: 55,
      maxWidth:     700,
      maxHeight:    700,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();

    // Hard limit: ~480 KB in Firestore (base64 adds ~33% overhead → ~360 KB raw)
    if (bytes.length > 360 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Image is too large (max 360 KB). Please choose a smaller image.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    final ext  = picked.name.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png'
               : ext == 'gif' ? 'image/gif'
               : 'image/jpeg';

    setState(() {
      _pendingImageBytes = bytes;
      _pendingMimeType   = mime;
    });
  }

  void _clearImage() => setState(() {
    _pendingImageBytes = null;
    _pendingMimeType   = null;
  });

  Future<void> _send() async {
    final text  = _textCtrl.text.trim();
    final hasImg = _pendingImageBytes != null;

    if ((text.isEmpty && !hasImg) || _sending || _moderating) return;
    HapticFeedback.mediumImpact();

    // Text profanity check
    if (text.isNotEmpty) {
      final err = CommunityService.checkText(text);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          behavior:        SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade600,
        ));
        return;
      }
    }

    // Image moderation (vision AI)
    if (hasImg) {
      setState(() { _moderating = true; });
      bool imageSafe = false;
      String? reason;
      try {
        final result = await CommunityService.moderateImage(
            _pendingImageBytes!, _pendingMimeType!);
        imageSafe = result.safe;
        reason    = result.reason;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not verify image safety. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ));
        }
        setState(() { _moderating = false; });
        return;
      }
      setState(() { _moderating = false; });
      if (!imageSafe) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Image not allowed: ${reason ?? "inappropriate content"}. '
                'Please choose a different image.'),
            behavior:        SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade600,
          ));
        }
        return;
      }
    }

    // Capture and clear before async gap
    final imageBytes = _pendingImageBytes;
    final mimeType   = _pendingMimeType;
    _textCtrl.clear();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending           = true;
      _sendingIsAsk      = _isAskMode;
      _pendingImageBytes = null;
      _pendingMimeType   = null;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToNewest(animate: true));

    try {
      if (_isAskMode) {
        await CommunityService.ask(
          text,
          imageBytes: imageBytes,
          mimeType:   mimeType,
        );
      } else {
        await CommunityService.postReply(
          text,
          imageBytes: imageBytes,
          mimeType:   mimeType,
        );
        ProfileService.incrementCommunity();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not post: ${e.toString().replaceFirst('Exception: ', '')}'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          _buildNavbar(),
          Expanded(child: _buildBody()),
          _buildInput(),
        ],
      ),
    );
  }

  // ── Navbar ──────────────────────────────────────────────────────────────────
  Widget _buildNavbar() {
    final cs = Theme.of(context).colorScheme;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    return Container(
      color:   bgColor,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color:        const Color(0xFF6366F1).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('🌐', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Community Hub',
                    style: _m(size: 16, weight: FontWeight.w900,
                        color: cs.onSurface)),
                Text(
                  '${_messages.length}/50 messages · completely anonymous',
                  style: _m(size: 11, weight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          const ProfileIcon(),
        ],
      ),
    );
  }

  // ── Body ────────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: _m(size: 13, weight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.55), height: 1.5)),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty && !_sending) return _buildEmptyState();

    // reverse:true renders newest message at the bottom without any jump on
    // new arrivals — index 0 = newest, last index = oldest.
    final hasTyping = _sending && _sendingIsAsk;
    final itemCount = _messages.length + (hasTyping ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      reverse:    true,
      padding:    const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount:  itemCount,
      itemBuilder: (_, i) {
        // Typing indicator sits at index 0 (visual bottom) while sending.
        if (hasTyping && i == 0) return const _TypingIndicator();
        final msgIndex = _messages.length - 1 - (hasTyping ? i - 1 : i);
        if (msgIndex < 0 || msgIndex >= _messages.length) {
          return const SizedBox.shrink();
        }
        return _MessageBubble(
          message:       _messages[msgIndex],
          currentUserId: FirebaseAuth.instance.currentUser?.uid,
        );
      },
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Text('🌐', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 18),
          Text('Community Explanation Hub',
              textAlign: TextAlign.center,
              style: _m(size: 20, weight: FontWeight.w900,
                  color: cs.onSurface)),
          const SizedBox(height: 10),
          Text(
            'Ask "Is this real?" about any headline, claim, or social post — or share what you know to help others. AI analysis included. Completely anonymous.',
            textAlign: TextAlign.center,
            style: _m(size: 13, weight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.55), height: 1.65),
          ),
          const SizedBox(height: 24),
          // Who responds card
          Container(
            padding:     const EdgeInsets.all(16),
            decoration:  BoxDecoration(
              color:        cs.surface,
              borderRadius: BorderRadius.circular(18),
              border:       Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Who responds to questions:',
                    style: _m(size: 12, weight: FontWeight.w800,
                        color: cs.onSurface.withValues(alpha: 0.55))),
                const SizedBox(height: 12),
                ...[
                  (MessageType.ai,    'AI Analysis',
                      'Fact-checks the claim, names any bias technique, and gives a verification tip'),
                  (MessageType.reply, 'Community Members',
                      'Other users can add their own knowledge or perspective'),
                ].map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: _typeColor(r.$1).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            CommunityMessage(
                              id: '', text: '', type: r.$1,
                              timestamp: DateTime.now(),
                            ).authorIcon,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.$2,
                                style: _m(size: 12, weight: FontWeight.w800,
                                    color: _typeColor(r.$1))),
                            Text(r.$3,
                                style: _m(size: 11, weight: FontWeight.w500,
                                    color: cs.onSurface.withValues(alpha: 0.55))),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Example prompt hint
          Container(
            padding:    const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        cs.surface,
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💬', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Try asking: "Is it true that 5G towers cause cancer?" '
                    'or "Scientists prove coffee cures cancer — real?"',
                    style: TextStyle(
                      fontFamily:  'Montserrat',
                      fontSize:    12,
                      fontWeight:  FontWeight.w500,
                      color:       const Color(0xFF1E40AF),
                      height:      1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Input bar ───────────────────────────────────────────────────────────────
  Widget _buildInput() {
    final cs = Theme.of(context).colorScheme;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final busy = _sending || _moderating;
    return Container(
      decoration: BoxDecoration(
        color:  cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode toggle
          _buildModeToggle(busy),
          const SizedBox(height: 10),
          // Image preview strip
          if (_pendingImageBytes != null) _buildImagePreview(),
          // Text field row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Image attach button
              GestureDetector(
                onTap: busy ? null : () { HapticFeedback.lightImpact(); _pickImage(); },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color:        bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.image_outlined,
                    size:  20,
                    color: busy
                        ? cs.onSurface.withValues(alpha: 0.25)
                        : cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller:    _textCtrl,
                  enabled:       !busy,
                  maxLines:      4,
                  minLines:      1,
                  textInputAction: TextInputAction.send,
                  onSubmitted:   (_) => _send(),
                  style: _m(size: 14, weight: FontWeight.w500,
                      color: cs.onSurface),
                  decoration: InputDecoration(
                    hintText: _isAskMode
                        ? 'Ask "Is this real?"…'
                        : 'Share what you know or think…',
                    hintStyle:      _m(size: 13, weight: FontWeight.w500,
                        color: cs.onSurface.withValues(alpha: 0.35)),
                    filled:         true,
                    fillColor:      bgColor,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide:   BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                            color: _isAskMode ? _kAccent : _kReplyColor,
                            width: 2)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              GestureDetector(
                onTap: busy ? null : _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: busy
                        ? (_isAskMode ? const Color(0xFF86EFAC) : const Color(0xFF93C5FD))
                        : (_isAskMode ? _kAccent : _kReplyColor),
                    shape: BoxShape.circle,
                    boxShadow: busy
                        ? []
                        : [
                            BoxShadow(
                              color: (_isAskMode ? _kAccent : _kReplyColor)
                                  .withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset:     const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Center(
                    child: busy
                        ? SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  _moderating ? Colors.orange : Colors.white),
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          // Moderation hint
          if (_moderating)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Checking image for safety…',
                style: _m(size: 11, weight: FontWeight.w500,
                    color: const Color(0xFFF59E0B)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeToggle(bool disabled) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color:        bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _modeTab('Ask a Question', true,  disabled),
          _modeTab('Post a Reply',   false, disabled),
        ],
      ),
    );
  }

  Widget _modeTab(String label, bool isAsk, bool disabled) {
    final cs = Theme.of(context).colorScheme;
    final selected = _isAskMode == isAsk;
    final color    = isAsk ? _kAccent : _kReplyColor;
    return Expanded(
      child: GestureDetector(
        onTap: disabled ? null : () { HapticFeedback.selectionClick(); setState(() => _isAskMode = isAsk); },
        child: AnimatedContainer(
          duration:     const Duration(milliseconds: 180),
          margin:       const EdgeInsets.all(3),
          decoration:   BoxDecoration(
            color:        selected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: _m(
              size:   12,
              weight: FontWeight.w700,
              color:  selected ? Colors.white : cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _pendingImageBytes!,
              height:  90,
              fit:     BoxFit.cover,
            ),
          ),
          GestureDetector(
            onTap: _clearImage,
            child: Container(
              margin:     const EdgeInsets.all(4),
              width:  22, height: 22,
              decoration: BoxDecoration(
                color:       Colors.black.withValues(alpha: 0.55),
                shape:       BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MESSAGE BUBBLE
// ─────────────────────────────────────────────────────────────────────────────
class _MessageBubble extends StatefulWidget {
  const _MessageBubble({required this.message, required this.currentUserId});
  final CommunityMessage message;
  final String? currentUserId;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with TickerProviderStateMixin {
  static const _allEmojis = ['👍', '👎', '❤️', '😮', '😂', '😢', '🔥', '🤔'];
  bool _pickerOpen = false;

  final List<_FloatingEmojiEntry> _floatingEmojis = [];

  void _spawnFloatingEmoji(String emoji) {
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    final entry = _FloatingEmojiEntry(emoji: emoji, ctrl: ctrl);
    setState(() => _floatingEmojis.add(entry));
    ctrl.forward().then((_) {
      if (mounted) setState(() => _floatingEmojis.remove(entry));
      ctrl.dispose();
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildLinks(List<Map<String, String>> links, Color accentColor) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: links.map((link) {
        final title  = link['title']  ?? '';
        final source = link['source'] ?? '';
        final url    = link['url']    ?? '';
        if (url.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: GestureDetector(
            onTap: () => _launchUrl(url),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color:        accentColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: accentColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.open_in_new_rounded, size: 13, color: accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (source.isNotEmpty)
                          Text(source,
                              style: _m(size: 10, weight: FontWeight.w700,
                                  color: accentColor)),
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _m(size: 11, weight: FontWeight.w500,
                                color: cs.onSurface, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _tap(String emoji) async {
    final uid = widget.currentUserId;
    if (uid == null) return;
    setState(() => _pickerOpen = false);
    _spawnFloatingEmoji(emoji);
    try {
      await CommunityService.toggleReaction(widget.message.id, emoji, uid);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: widget.message.isQuestion ? _buildQuestion() : _buildResponder(),
        ),
        for (final entry in _floatingEmojis)
          _FloatingEmojiWidget(entry: entry),
      ],
    );
  }

  // Questions go on the RIGHT (green bubble, like the old "user" messages)
  Widget _buildQuestion() {
    final cs = Theme.of(context).colorScheme;
    final bytes = widget.message.imageBytes;
    // The placeholder text set when user sends image-only — no need to show it
    // alongside the image itself.
    final isImageOnly = bytes != null &&
        (widget.message.text.isEmpty ||
         widget.message.text == '📷 Image shared for analysis');
    final showText = widget.message.text.isNotEmpty && !isImageOnly;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Anonymous',
                  style: _m(size: 10, weight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: 0.55))),
              const SizedBox(height: 4),
              Container(
                // Tighter padding when image is present so it fills edge-to-edge
                padding: EdgeInsets.only(
                  left:   bytes != null ? 8  : 14,
                  right:  bytes != null ? 8  : 14,
                  top:    bytes != null ? 8  : 10,
                  bottom: 10,
                ),
                decoration: BoxDecoration(
                  color: _kAccent,
                  borderRadius: const BorderRadius.only(
                    topLeft:     Radius.circular(18),
                    topRight:    Radius.circular(18),
                    bottomLeft:  Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:      _kAccent.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset:     const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          bytes,
                          width:   220,
                          fit:     BoxFit.cover,
                        ),
                      ),
                      if (showText) const SizedBox(height: 8),
                    ],
                    if (showText)
                      Text(widget.message.text,
                          style: _m(size: 13, weight: FontWeight.w500,
                              color: Colors.white, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Center(child: Text('👤', style: TextStyle(fontSize: 14))),
        ),
      ],
    );
  }

  // AI and Community replies go on the LEFT
  Widget _buildResponder() {
    final cs = Theme.of(context).colorScheme;
    final color   = _typeColor(widget.message.type);
    final bytes   = widget.message.imageBytes;
    final myEmoji = widget.currentUserId != null
        ? widget.message.userReactions[widget.currentUserId!]
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(widget.message.authorIcon,
                style: const TextStyle(fontSize: 15)),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.message.authorLabel,
                  style: _m(size: 10, weight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft:     Radius.circular(4),
                    topRight:    Radius.circular(18),
                    bottomLeft:  Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border:     Border.all(color: color.withValues(alpha: 0.2)),
                  boxShadow:  [
                    BoxShadow(
                      color:      Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset:     const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(bytes, width: 220, fit: BoxFit.cover),
                      ),
                      if (widget.message.text.isNotEmpty) const SizedBox(height: 8),
                    ],
                    if (widget.message.text.isNotEmpty)
                      Text(widget.message.text,
                          style: _m(size: 13, weight: FontWeight.w500,
                              color: cs.onSurface, height: 1.55)),
                  ],
                ),
              ),
              // ── Article links (AI messages only) ──────────────────────────
              if (widget.message.type == MessageType.ai &&
                  widget.message.links.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildLinks(widget.message.links, color),
              ],
              const SizedBox(height: 6),
              // ── Reaction row ───────────────────────────────────────────────
              Row(
                children: [
                  // Existing reaction pills — Flexible prevents Wrap from overflowing
                  Flexible(
                    child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: widget.message.reactions.entries.map((e) {
                      final isMe = myEmoji == e.key;
                      return GestureDetector(
                        onTap: () => _tap(e.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isMe
                                ? color.withValues(alpha: 0.15)
                                : cs.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isMe
                                  ? color
                                  : cs.outlineVariant,
                              width: isMe ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(e.key,
                                  style: const TextStyle(fontSize: 13)),
                              const SizedBox(width: 3),
                              Text('${e.value}',
                                  style: _m(
                                    size:   11,
                                    weight: FontWeight.w700,
                                    color:  isMe ? color : cs.onSurface.withValues(alpha: 0.55),
                                  )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),   // Wrap
                  ),   // Flexible
                  const SizedBox(width: 4),
                  // ＋ button to open/close picker
                  if (widget.currentUserId != null)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _pickerOpen = !_pickerOpen);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: _pickerOpen
                              ? color.withValues(alpha: 0.15)
                              : cs.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _pickerOpen ? color : cs.outlineVariant,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            _pickerOpen ? Icons.close : Icons.add,
                            size:  14,
                            color: _pickerOpen ? color : cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // ── Emoji picker ───────────────────────────────────────────────
              if (_pickerOpen) ...[
                const SizedBox(height: 6),
                Container(
                  // Fill parent width so emojis are distributed evenly.
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color:        cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border:       Border.all(color: cs.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset:     const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _allEmojis.map((emoji) {
                      final isActive = myEmoji == emoji;
                      return GestureDetector(
                        onTap: () => _tap(emoji),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: isActive
                                ? color.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 17)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TYPING INDICATOR
// ─────────────────────────────────────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: _kAiColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('🔍', style: TextStyle(fontSize: 15))),
          ),
          const SizedBox(width: 8),
          Container(
            padding:     const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration:  BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(4),
                topRight:    Radius.circular(18),
                bottomLeft:  Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: _kAiColor.withValues(alpha: 0.2)),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder:   (context2, child2) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t       = ((_ctrl.value - i / 3) % 1.0 + 1.0) % 1.0;
                  final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.25, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(
                          color: _kAiColor, shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FLOATING EMOJI REACTION
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingEmojiEntry {
  _FloatingEmojiEntry({required this.emoji, required this.ctrl})
      : xOffset = (math.Random().nextDouble() - 0.5) * 56;
  final String emoji;
  final AnimationController ctrl;
  final double xOffset;
}

class _FloatingEmojiWidget extends StatelessWidget {
  const _FloatingEmojiWidget({required this.entry});
  final _FloatingEmojiEntry entry;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: entry.ctrl,
      builder: (_, _) {
        final t     = entry.ctrl.value;
        final rise  = Curves.easeOut.transform(t);
        final fade  = 1.0 - Curves.easeIn.transform(t > 0.4 ? (t - 0.4) / 0.6 : 0.0);
        final scale = 1.0 + Curves.elasticOut.transform(t.clamp(0.0, 0.5)) * 0.4;
        return Positioned(
          bottom: 28 + rise * 110,
          left:   0,
          right:  0,
          child: Center(
            child: Transform.translate(
              offset: Offset(entry.xOffset, 0),
              child: Opacity(
                opacity: fade.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  child: Text(entry.emoji,
                      style: const TextStyle(fontSize: 28)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
