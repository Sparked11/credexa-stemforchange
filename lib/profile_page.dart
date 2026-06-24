import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'auth_service.dart';
import 'services/profile_service.dart';
import 'services/user_progress_service.dart';

// ── Banner themes ─────────────────────────────────────────────────────────────

class _BannerOption {
  _BannerOption({required this.id, required this.label, this.photoUrl, List<Color>? gradient})
      : gradient = gradient ?? const [Color(0xFF1E293B), Color(0xFF334155)];
  final int id;
  final String label;
  final String? photoUrl;
  final List<Color> gradient;
}

final _kBannerOptions = <_BannerOption>[
  _BannerOption(id: 0, label: 'Default'),
  _BannerOption(id: 1, label: 'Mountains',    photoUrl: 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?auto=format&fit=crop&w=800&q=70'),
  _BannerOption(id: 2, label: 'Aurora',       photoUrl: 'https://images.unsplash.com/photo-1531366936337-7c912a4589a7?auto=format&fit=crop&w=800&q=70'),
  _BannerOption(id: 3, label: 'Beach',        photoUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=800&q=70'),
  _BannerOption(id: 4, label: 'Forest',       photoUrl: 'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=800&q=70'),
  _BannerOption(id: 5, label: 'Blossoms',     photoUrl: 'https://images.unsplash.com/photo-1502082553048-f009c37129b9?auto=format&fit=crop&w=800&q=70'),
  _BannerOption(id: 6, label: 'Starry Night', photoUrl: 'https://images.unsplash.com/photo-1519681393784-d120267933ba?auto=format&fit=crop&w=800&q=70'),
  _BannerOption(id: 7, label: 'Coastal Glow', photoUrl: 'https://images.unsplash.com/photo-1470770903676-69b98201ea1c?auto=format&fit=crop&w=800&q=70'),
];

// ── Typography helper ─────────────────────────────────────────────────────────
TextStyle _mp({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = const Color(0xFF1E293B),
  double? height,
}) =>
    TextStyle(
      fontFamily: 'Montserrat',
      fontSize:   size,
      fontWeight: weight,
      color:      color,
      height:     height,
    );

// ─────────────────────────────────────────────────────────────────────────────
//  PROFILE PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    ProfileService.load();
  }

  // ── Photo change ─────────────────────────────────────────────────────────────

  Future<void> _changePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source:       ImageSource.gallery,
      imageQuality: 60,
      maxWidth:     300,
      maxHeight:    300,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 250 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Image too large — please pick a smaller one.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _uploadingPhoto = true);
    try {
      await ProfileService.setPhoto(base64Encode(bytes));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save photo. Try again.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Banner change ────────────────────────────────────────────────────────────

  void _changeBanner() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BannerPickerSheet(
        currentId: ProfileService.data.value.bannerThemeId,
        onSelect: (id) async {
          await ProfileService.setBannerTheme(id);
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String _formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final user        = AuthService.currentUser;
    // Firebase Auth always has creationTime for signed-in users.
    final joinedAt    =
        fb.FirebaseAuth.instance.currentUser?.metadata.creationTime;
    final joinDateStr = joinedAt != null ? _formatDate(joinedAt) : '—';

    return Scaffold(
      backgroundColor: bgColor,
      body: ValueListenableBuilder<ProfileData>(
        valueListenable: ProfileService.data,
        builder: (context, data, _) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight:  260,
                pinned:          true,
                backgroundColor: const Color(0xFF1E293B),
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size:  20,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text(
                  'Profile',
                  style: TextStyle(
                    fontFamily:  'Montserrat',
                    fontSize:    17,
                    fontWeight:  FontWeight.w800,
                    color:       Colors.white,
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background:
                      _buildHeader(user, data.photoBase64, data.bannerThemeId),
                ),
              ),
              SliverToBoxAdapter(
                  child: _buildStats(context, data.checks, data.debiases, data.posts)),
              SliverToBoxAdapter(child: const _ProgressReportSection()),
              SliverToBoxAdapter(
                  child: _buildBadges(
                      context, data.checks, data.debiases, data.posts, data.quests)),
              SliverToBoxAdapter(
                  child: _buildAccount(context, user, joinDateStr)),
              SliverToBoxAdapter(child: _buildSignOut(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          );
        },
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader(AuthUser? user, String? photoBase64, int bannerThemeId) {
    final theme = _kBannerOptions.firstWhere(
      (t) => t.id == bannerThemeId,
      orElse: () => _kBannerOptions.first,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background: photo or gradient ──
        if (theme.photoUrl != null)
          Image.network(
            theme.photoUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, e, s) => _gradientBox(theme.gradient),
          )
        else
          _gradientBox(theme.gradient),

        // ── Dark vignette for text legibility ──
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x22000000), Color(0xBB000000)],
              begin: Alignment.topCenter,
              end:   Alignment.bottomCenter,
            ),
          ),
        ),

        // ── Profile content ──
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GestureDetector(
              onTap: _changePhoto,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width:  96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                        begin:  Alignment.topLeft,
                        end:    Alignment.bottomRight,
                      ),
                    ),
                    child: ClipOval(
                      child: photoBase64 != null
                          ? Image.memory(
                              base64Decode(photoBase64),
                              fit:    BoxFit.cover,
                              width:  96,
                              height: 96,
                              errorBuilder: (_, _, _) => _initialsAvatar(user),
                            )
                          : _initialsAvatar(user),
                    ),
                  ),
                  Positioned(
                    right:  0,
                    bottom: 0,
                    child: Container(
                      width:  30,
                      height: 30,
                      decoration: BoxDecoration(
                        color:  const Color(0xFF22C55E),
                        shape:  BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: _uploadingPhoto
                            ? const Padding(
                                padding: EdgeInsets.all(7),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.camera_alt_rounded,
                                size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              user?.name ?? 'User',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize:   20,
                fontWeight: FontWeight.w900,
                color:      Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user?.email ?? '',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize:   12,
                fontWeight: FontWeight.w500,
                color:      Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),

        // ── Edit-banner pill (top-right, below the app-bar buttons) ──
        Positioned(
          top:   56,
          right: 12,
          child: GestureDetector(
            onTap: _changeBanner,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:        Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25), width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wallpaper_rounded, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text('Edit Banner',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize:   9,
                        fontWeight: FontWeight.w700,
                        color:      Colors.white,
                      )),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _gradientBox(List<Color> colors) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
          ),
        ),
      );

  Widget _initialsAvatar(AuthUser? user) => Center(
        child: Text(
          user?.initials ?? 'U',
          style: const TextStyle(
            fontFamily:  'Montserrat',
            fontSize:    36,
            fontWeight:  FontWeight.w900,
            color:       Colors.white,
          ),
        ),
      );

  // ── Stats ────────────────────────────────────────────────────────────────────

  Widget _buildStats(BuildContext context, int checks, int debiases, int posts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          _statCard(context, '🔍', checks,   'Fact Checks'),
          const SizedBox(width: 12),
          _statCard(context, '🌿', debiases, 'De-Biases'),
          const SizedBox(width: 12),
          _statCard(context, '💬', posts,    'Posts'),
        ],
      ),
    );
  }

  Widget _statCard(BuildContext context, String icon, int count, String label) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color:        cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(
                fontFamily:  'Montserrat',
                fontSize:    24,
                fontWeight:  FontWeight.w900,
                color:       cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: _mp(size: 10, weight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.55)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Badges ───────────────────────────────────────────────────────────────────

  Widget _buildBadges(BuildContext context, int checks, int debiases, int posts, int quests) {
    final cs = Theme.of(context).colorScheme;
    final earned =
        kBadges.where((b) => b.isEarned(checks, debiases, posts, quests)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding:     const EdgeInsets.all(18),
        decoration:  BoxDecoration(
          color:        cs.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Badges',
                    style: _mp(size: 15, weight: FontWeight.w900,
                        color: cs.onSurface)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    '$earned / ${kBadges.length} earned',
                    style: _mp(
                      size:   11,
                      weight: FontWeight.w700,
                      color:  const Color(0xFF1D4ED8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap:        true,
              physics:           const NeverScrollableScrollPhysics(),
              crossAxisCount:    3,
              crossAxisSpacing:  10,
              mainAxisSpacing:   10,
              // Extra vertical room prevents the 1.7px bottom overflow.
              childAspectRatio:  0.78,
              children: kBadges.map((badge) {
                final isEarned =
                    badge.isEarned(checks, debiases, posts, quests);
                return _BadgeTile(badge: badge, earned: isEarned);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Account ──────────────────────────────────────────────────────────────────

  Widget _buildAccount(BuildContext context, AuthUser? user, String joinDateStr) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding:    const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color:        cs.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account',
                style: _mp(size: 15, weight: FontWeight.w900,
                    color: cs.onSurface)),
            const SizedBox(height: 14),
            _accountRow(context, Icons.email_outlined, 'Email',
                user?.email ?? '—'),
            _accountRow(context, Icons.calendar_today_outlined,
                'Member since', joinDateStr),
            _accountRow(
              context,
              Icons.shield_outlined,
              'Mission',
              'UN SDG Goal 16 — Peace, Justice & Strong Institutions',
              last: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountRow(BuildContext context, IconData icon, String label, String value,
      {bool last = false}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width:  36,
                height: 36,
                decoration: BoxDecoration(
                  color:        Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18,
                    color: cs.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: _mp(
                          size:   10,
                          weight: FontWeight.w700,
                          color:  cs.onSurface.withValues(alpha: 0.45),
                        )),
                    const SizedBox(height: 2),
                    Text(value,
                        style: _mp(
                          size:   13,
                          weight: FontWeight.w600,
                          color:  cs.onSurface,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!last)
          Divider(height: 1, color: cs.outlineVariant),
      ],
    );
  }

  // ── Sign out ─────────────────────────────────────────────────────────────────

  Widget _buildSignOut(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pop();
          AuthService.signOut();
        },
        child: Container(
          width:   double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color:        const Color(0xFFFFF5F5),
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(color: const Color(0xFFFECACA)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, size: 18,
                  color: Color(0xFFEF4444)),
              SizedBox(width: 8),
              Text(
                'Sign Out',
                style: TextStyle(
                  fontFamily:  'Montserrat',
                  fontSize:    14,
                  fontWeight:  FontWeight.w700,
                  color:       Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BADGE TILE
// ─────────────────────────────────────────────────────────────────────────────

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.earned});
  final BadgeInfo badge;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: () => _showDetail(context),
      child: AnimatedContainer(
        duration:    const Duration(milliseconds: 300),
        padding:     const EdgeInsets.all(10),
        decoration:  BoxDecoration(
          color:        earned
              ? const Color(0xFFEFFDF4)
              : cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: earned
                ? const Color(0xFF22C55E)
                : cs.outlineVariant,
            width: earned ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: earned ? 1.0 : 0.25,
              child: Text(badge.emoji,
                  style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(height: 6),
            Text(
              badge.title,
              style: TextStyle(
                fontFamily:  'Montserrat',
                fontSize:    9,
                fontWeight:  FontWeight.w800,
                color: earned
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
            if (!earned) ...[
              const SizedBox(height: 3),
              Text(
                badge.requirement,
                style: TextStyle(
                  fontFamily:  'Montserrat',
                  fontSize:    7.5,
                  fontWeight:  FontWeight.w500,
                  color:       cs.onSurface.withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
                maxLines:  2,
                overflow:  TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        backgroundColor: cs.surface,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: earned ? 1.0 : 0.35,
              child: Text(badge.emoji,
                  style: const TextStyle(fontSize: 48)),
            ),
            const SizedBox(height: 12),
            Text(badge.title,
                style: TextStyle(
                  fontFamily:  'Montserrat',
                  fontSize:    17,
                  fontWeight:  FontWeight.w900,
                  color:       cs.onSurface,
                )),
            const SizedBox(height: 6),
            Text(badge.desc,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily:  'Montserrat',
                  fontSize:    13,
                  fontWeight:  FontWeight.w500,
                  color:       cs.onSurface.withValues(alpha: 0.55),
                )),
            const SizedBox(height: 12),
            if (!earned)
              Container(
                padding:    const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:        const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(20),
                  border:       Border.all(
                      color: const Color(0xFFFED7AA)),
                ),
                child: Text(
                  'Requires: ${badge.requirement}',
                  style: const TextStyle(
                    fontFamily:  'Montserrat',
                    fontSize:    11,
                    fontWeight:  FontWeight.w700,
                    color:       Color(0xFFEA580C),
                  ),
                ),
              )
            else
              Container(
                padding:    const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:        const Color(0xFFEFFDF4),
                  borderRadius: BorderRadius.circular(20),
                  border:       Border.all(
                      color: const Color(0xFF86EFAC)),
                ),
                child: const Text(
                  '✓ Earned',
                  style: TextStyle(
                    fontFamily:  'Montserrat',
                    fontSize:    11,
                    fontWeight:  FontWeight.w700,
                    color:       Color(0xFF16A34A),
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
//  SURVEY SUMMARY SECTION
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  PROGRESS REPORT SECTION  — card + share button
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressReportSection extends StatefulWidget {
  const _ProgressReportSection();
  @override
  State<_ProgressReportSection> createState() => _ProgressReportSectionState();
}

class _ProgressReportSectionState extends State<_ProgressReportSection> {
  final _repaintKey    = GlobalKey();
  final _shareButtonKey = GlobalKey();
  bool _sharing = false;

  static const _quotes = [
    'Critical thinking is not a gift — it is a skill that can be built.',
    'In a world of noise, the ability to find truth is a superpower.',
    'The first step in fighting misinformation is knowing how to question it.',
    'Media literacy is the new literacy.',
    'Every fact-check you run is a vote for truth.',
    'Skepticism, applied wisely, is an act of care — for yourself and others.',
    'An informed citizen is the foundation of a just society.',
  ];

  String get _quote => _quotes[DateTime.now().weekday % _quotes.length];

  Future<void> _shareReport() async {
    setState(() => _sharing = true);
    final messenger   = ScaffoldMessenger.of(context);
    final screenSize  = MediaQuery.of(context).size;
    // Capture values before any await.
    final stats = UserProgressService.stats.value;
    final quote = _quote;
    try {
      // Draw the card using PictureRecorder — no widget tree, no GPU culling.
      final image    = await _drawReportImage(stats, quote);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw Exception('PNG encoding returned null');

      final bytes = byteData.buffer.asUint8List();
      final dir   = await getTemporaryDirectory();
      final file  = File('${dir.path}/credexa_report.png');
      await file.writeAsBytes(bytes);

      final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromCenter(
              center: Offset(
                screenSize.width / 2,
                screenSize.height - 80,
              ),
              width: 200,
              height: 50,
            );

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'My Credexa Media Literacy Report 🧠\n'
            'Building critical thinking — one fact-check at a time.',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            e.toString().toLowerCase().contains('cancel')
                ? 'Share cancelled.'
                : 'Error: ${e.toString()}',
          ),
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Renders the report card using [ui.PictureRecorder] — bypasses the widget
  /// tree entirely, so it works regardless of scroll position or GPU culling.
  static Future<ui.Image> _drawReportImage(
      UserProgressStats s, String quote) async {
    const w   = 750.0;
    const h   = 1200.0;   // taller to fit the graph section
    const pad = 50.0;
    const bw  = w - 2 * pad;

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);

    // Background gradient
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h), const Radius.circular(40)),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h),
            [const Color(0xFF0F172A), const Color(0xFF1E293B)]),
    );

    // Text helper — system font only (custom fonts are not available to
    // TextPainter outside the widget tree on iOS).
    double draw(String text, double x, double y, {
      double maxW = bw,
      double fs   = 26,
      FontWeight fw = FontWeight.normal,
      Color color   = Colors.white,
      double lh     = 1.3,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fs, fontWeight: fw, color: color,
            height: lh, decoration: TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxW);
      tp.paint(canvas, Offset(x, y));
      return tp.height;
    }

    final lvl      = s.level;
    final progress = lvl.progress(s.maturityPoints).clamp(0.0, 1.0);
    final pct = '${(s.predictionAccuracy * 100).round()}%';

    double y = pad;

    // Brand
    y += draw('CREDEXA  ·  MEDIA LITERACY REPORT',
        pad, y, fs: 18, fw: FontWeight.bold,
        color: const Color(0xFF22C55E)) + 32;

    // Level
    y += draw('${lvl.emoji}  ${lvl.title}',
        pad, y, fs: 42, fw: FontWeight.bold) + 10;
    y += draw('MEDIA MATURITY',
        pad, y, fs: 15, fw: FontWeight.bold,
        color: const Color(0xFF4ADE80)) + 22;

    // Progress bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(pad, y, bw, 10), const Radius.circular(5)),
      Paint()..color = Colors.white.withValues(alpha: 0.15),
    );
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(pad, y, bw * progress, 10), const Radius.circular(5)),
        Paint()..color = const Color(0xFF4ADE80),
      );
    }
    y += 42;

    // Stats
    final cols = [
      ('${s.predictionsTotal}', 'Checks'),
      (pct, 'Accuracy'),
      ('${s.questsAnswered}', 'Quests'),
      ('${s.maturityPoints}', 'Points'),
    ];
    final colW   = bw / cols.length;
    final statsY = y;
    for (int i = 0; i < cols.length; i++) {
      final cx = pad + colW * i;
      draw(cols[i].$1, cx, statsY,      maxW: colW, fs: 30, fw: FontWeight.bold);
      draw(cols[i].$2, cx, statsY + 44, maxW: colW, fs: 17,
          color: const Color(0xFF64748B));
      if (i < cols.length - 1) {
        canvas.drawLine(
          Offset(pad + colW * (i + 1), statsY - 4),
          Offset(pad + colW * (i + 1), statsY + 72),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.1)
            ..strokeWidth = 1.5,
        );
      }
    }
    y = statsY + 96;

    // ── Accuracy-over-time graph ──────────────────────────────────────────────
    const graphH = 160.0;

    // Section header
    y += draw('ACCURACY OVER TIME',
        pad, y, fs: 15, fw: FontWeight.bold,
        color: const Color(0xFF4ADE80)) + 14;

    final hist = s.accuracyHistory;
    if (hist.length < 2) {
      // Placeholder text
      y += draw('Make predictions on claims to track your growth.',
          pad, y, fs: 18, color: const Color(0xFF475569)) + 20;
    } else {
      // Graph background
      final gx   = pad;
      final gy   = y;
      final gw   = bw;
      const padL = 52.0;
      const padR = 8.0;
      const padT = 8.0;
      const padB = 26.0;
      final chartW = gw - padL - padR;
      final chartH = graphH;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(gx, gy, gw, graphH + padB),
            const Radius.circular(16)),
        Paint()..color = Colors.white.withValues(alpha: 0.06),
      );

      // Grid lines + Y labels
      final gridPaint = Paint()
        ..color      = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 1;

      for (int g = 0; g <= 4; g++) {
        final lineY  = gy + padT + chartH * (1 - g / 4);
        final label  = '${g * 25}%';
        canvas.drawLine(
            Offset(gx + padL, lineY),
            Offset(gx + padL + chartW, lineY),
            gridPaint);
        draw(label, gx, lineY - 12, maxW: padL - 6, fs: 15,
            color: const Color(0xFF475569));
      }

      Offset pt(int i) {
        final n = hist.length;
        final x = gx + padL + (n < 2 ? chartW / 2 : i / (n - 1) * chartW);
        final yy = gy + padT + chartH * (1 - hist[i].clamp(0.0, 1.0));
        return Offset(x, yy);
      }

      final n = hist.length;

      // Fill
      final fill = Path()
        ..moveTo(pt(0).dx, gy + padT + chartH)
        ..lineTo(pt(0).dx, pt(0).dy);
      for (int i = 1; i < n; i++) { fill.lineTo(pt(i).dx, pt(i).dy); }
      fill
        ..lineTo(pt(n - 1).dx, gy + padT + chartH)
        ..close();
      canvas.drawPath(fill,
          Paint()
            ..color = const Color(0xFF38BDF8).withValues(alpha: 0.14)
            ..style = PaintingStyle.fill);

      // Line
      final line = Path()..moveTo(pt(0).dx, pt(0).dy);
      for (int i = 1; i < n; i++) { line.lineTo(pt(i).dx, pt(i).dy); }
      canvas.drawPath(line,
          Paint()
            ..color      = const Color(0xFF38BDF8)
            ..strokeWidth = 2.5
            ..style      = PaintingStyle.stroke
            ..strokeCap  = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);

      // Dots
      for (int i = 0; i < n; i++) {
        canvas.drawCircle(pt(i), 5,
            Paint()..color = const Color(0xFF38BDF8));
        canvas.drawCircle(pt(i), 3,
            Paint()..color = Colors.white);
      }

      // X-axis labels: first, middle, last
      void xLabel(int idx) {
        final o = pt(idx);
        draw('${idx + 1}', o.dx - 10, gy + padT + chartH + 6,
            maxW: 30, fs: 14, color: const Color(0xFF475569));
      }
      xLabel(0);
      if (n > 2) xLabel(n ~/ 2);
      xLabel(n - 1);

      y += graphH + padB + 20;
    }

    // Quote
    canvas.drawRect(
        Rect.fromLTWH(pad, y, 5, 100), Paint()..color = const Color(0xFF4ADE80));
    draw('"$quote"', pad + 18, y,
        maxW: bw - 22, fs: 22, color: const Color(0xFF94A3B8), lh: 1.65);
    y += 116;

    // Footer
    draw('Generated by Credexa  ·  UN SDG Goal 16',
        pad, y, fs: 17, color: const Color(0xFF475569));

    return recorder.endRecording().toImage(w.toInt(), h.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProgressStats>(
      valueListenable: UserProgressService.stats,
      builder: (context, s, child) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Report card (captured by RepaintBoundary) ──
            RepaintBoundary(
              key: _repaintKey,
              child: _ProgressReportCard(stats: s, quote: _quote),
            ),
            const SizedBox(height: 12),
            // ── Share button ──
            GestureDetector(
              key: _shareButtonKey,
              onTap: _sharing ? null : _shareReport,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: _sharing
                      ? const Color(0xFF64748B)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _sharing
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          )
                        ],
                ),
                child: _sharing
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white)),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.ios_share_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Share My Report',
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
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROGRESS REPORT CARD — the shareable image widget (collapsible)
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressReportCard extends StatefulWidget {
  const _ProgressReportCard({required this.stats, required this.quote});
  final UserProgressStats stats;
  final String quote;
  @override
  State<_ProgressReportCard> createState() => _ProgressReportCardState();
}

class _ProgressReportCardState extends State<_ProgressReportCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final stats    = widget.stats;
    final quote    = widget.quote;
    final lvl      = stats.level;
    final progress = lvl.progress(stats.maturityPoints);
    final pct      = '${(stats.predictionAccuracy * 100).round()}%';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (tap to collapse) ──
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text('CREDEXA · MEDIA LITERACY',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF22C55E),
                        letterSpacing: 1.0,
                      )),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeInOutCubic,
                  child: const Icon(Icons.keyboard_arrow_up_rounded,
                      color: Color(0xFF4ADE80), size: 20),
                ),
                const SizedBox(width: 6),
                const Text('🕊️', style: TextStyle(fontSize: 20)),
              ],
            ),
          ),

          // ── Collapsible body ──
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 18),

                      // ── Level ──
                      Row(
                        children: [
                          Text(lvl.emoji,
                              style: const TextStyle(fontSize: 36)),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('MEDIA MATURITY LEVEL',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4ADE80),
                                    letterSpacing: 1.1,
                                  )),
                              Text(lvl.title,
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  )),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Progress bar ──
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF4ADE80)),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Stats ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            _rStat('🔍', '${stats.predictionsTotal}', 'Checks'),
                            _rDivider(),
                            _rStat('🎯', pct, 'Accuracy'),
                            _rDivider(),
                            _rStat('📚', '${stats.questsAnswered}', 'Quests'),
                            _rDivider(),
                            _rStat('⭐', '${stats.maturityPoints}', 'Points'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Accuracy over time graph ──
                      _AccuracyGraphCard(
                          history: stats.accuracyHistory),
                      const SizedBox(height: 18),

                      // ── Quote ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                                color: Color(0xFF4ADE80), width: 3),
                          ),
                        ),
                        child: Text(
                          '"$quote"',
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF94A3B8),
                            height: 1.6,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Footer ──
                      const Text(
                        'Generated by Credexa · UN SDG Goal 16  🕊️',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _rStat(String emoji, String value, String label) => Expanded(
        child: Column(
          children: [
            Text(emoji,
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                )),
            Text(label,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                )),
          ],
        ),
      );

  Widget _rDivider() => Container(
        width: 1,
        height: 32,
        color: Colors.white.withValues(alpha: 0.1),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  BANNER PICKER SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _BannerPickerSheet extends StatefulWidget {
  const _BannerPickerSheet({required this.currentId, required this.onSelect});
  final int currentId;
  final void Function(int) onSelect;
  @override
  State<_BannerPickerSheet> createState() => _BannerPickerSheetState();
}

class _BannerPickerSheetState extends State<_BannerPickerSheet> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentId;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ──
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Choose Banner',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize:   16,
                fontWeight: FontWeight.w800,
                color:      Colors.white,
              )),
          const SizedBox(height: 4),
          Text('Tap a scene to preview it, then press Apply.',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize:   12,
                fontWeight: FontWeight.w500,
                color:      Colors.white.withValues(alpha: 0.5),
              )),
          const SizedBox(height: 16),

          // ── Thumbnail grid ──
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:   4,
              crossAxisSpacing: 10,
              mainAxisSpacing:  10,
              childAspectRatio: 1.6,
            ),
            itemCount: _kBannerOptions.length,
            itemBuilder: (_, i) {
              final opt      = _kBannerOptions[i];
              final selected = _selected == opt.id;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selected = opt.id);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF4ADE80)
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // thumbnail background
                        if (opt.photoUrl != null)
                          Image.network(opt.photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, e, s) =>
                                  Container(color: const Color(0xFF334155)))
                        else
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: opt.gradient,
                                begin: Alignment.topLeft,
                                end:   Alignment.bottomRight,
                              ),
                            ),
                          ),
                        // selected overlay + tick
                        if (selected)
                          Container(
                            alignment: Alignment.center,
                            color: Colors.black.withValues(alpha: 0.3),
                            child: const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF4ADE80), size: 20),
                          ),
                        // label
                        Positioned(
                          bottom: 3,
                          left:   3,
                          right:  3,
                          child: Text(opt.label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize:   7,
                                fontWeight: FontWeight.w700,
                                color:      Colors.white,
                                shadows:    [Shadow(blurRadius: 6)],
                              )),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Apply button ──
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.onSelect(_selected);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color:        const Color(0xFF4ADE80),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('Apply Theme',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize:   14,
                    fontWeight: FontWeight.w800,
                    color:      Colors.white,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ACCURACY OVER TIME  —  animated line graph
// ─────────────────────────────────────────────────────────────────────────────

class _AccuracyGraphCard extends StatefulWidget {
  const _AccuracyGraphCard({required this.history});
  final List<double> history;
  @override
  State<_AccuracyGraphCard> createState() => _AccuracyGraphCardState();
}

class _AccuracyGraphCardState extends State<_AccuracyGraphCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
    // Small delay so the card-open animation finishes first.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void didUpdateWidget(_AccuracyGraphCard old) {
    super.didUpdateWidget(old);
    if (old.history.length != widget.history.length) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color:        Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              const Text('📈', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 7),
              const Text('ACCURACY OVER TIME',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize:   8,
                    fontWeight: FontWeight.w800,
                    color:      Color(0xFF4ADE80),
                    letterSpacing: 1.1,
                  )),
              const Spacer(),
              if (history.length >= 2)
                Text(
                  '${history.length} predictions',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize:   8,
                    fontWeight: FontWeight.w600,
                    color:      Colors.white.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Graph or placeholder ──
          if (history.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  'Make predictions on claims to track your growth here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize:   11,
                    fontWeight: FontWeight.w500,
                    color:      Colors.white.withValues(alpha: 0.3),
                    height:     1.5,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 110,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, child) => CustomPaint(
                  painter: _AccuracyLinePainter(
                    history:  history,
                    progress: _anim.value,
                  ),
                  size: const Size(double.infinity, 110),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccuracyLinePainter extends CustomPainter {
  const _AccuracyLinePainter({
    required this.history,
    required this.progress,
  });
  final List<double> history;
  final double progress;

  // ── helpers ──────────────────────────────────────────────────────────────

  static void _drawLabel(
    Canvas canvas,
    String text,
    double x,
    double y, {
    double fontSize  = 9,
    Color color      = const Color(0xFF64748B),
    TextAlign align  = TextAlign.left,
    double maxW      = 60,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize:   fontSize,
          color:      color,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
          height:     1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign:     align,
    )..layout(maxWidth: maxW);
    tp.paint(canvas, Offset(x - (align == TextAlign.right ? tp.width : 0), y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const padL  = 36.0;
    const padR  = 6.0;
    const padT  = 6.0;
    const padB  = 20.0;
    final chartW = size.width  - padL - padR;
    final chartH = size.height - padT - padB;
    final n      = history.length;

    // ── Grid lines & Y labels ──
    final gridPaint = Paint()
      ..color      = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;

    for (int g = 0; g <= 4; g++) {
      final gy    = padT + chartH * (1 - g / 4);
      final label = '${(g * 25).toString()}%';
      canvas.drawLine(Offset(padL, gy), Offset(padL + chartW, gy), gridPaint);
      _drawLabel(canvas, label, padL - 4, gy - 5,
          align: TextAlign.right, maxW: 30);
    }

    // ── Compute visible points up to animation progress ──
    final animEnd  = ((n - 1) * progress).clamp(0.0, (n - 1).toDouble());
    final fullPts  = animEnd.floor() + 1;

    Offset pt(int i) {
      final x = padL + (n < 2 ? chartW / 2 : i / (n - 1) * chartW);
      final y = padT + chartH * (1 - history[i].clamp(0.0, 1.0));
      return Offset(x, y);
    }

    List<Offset> visible = List.generate(
        fullPts.clamp(0, n), (i) => pt(i));

    // Interpolate the leading edge
    if (animEnd < n - 1 && fullPts < n) {
      final frac = animEnd - animEnd.floor();
      final a    = pt(fullPts - 1);
      final b    = pt(fullPts);
      visible.add(Offset(a.dx + (b.dx - a.dx) * frac,
                         a.dy + (b.dy - a.dy) * frac));
    }

    if (visible.length < 2) return;

    // ── Fill under the line ──
    final fill = Path()
      ..moveTo(visible.first.dx, padT + chartH)
      ..lineTo(visible.first.dx, visible.first.dy);
    for (int i = 1; i < visible.length; i++) {
      fill.lineTo(visible[i].dx, visible[i].dy);
    }
    fill
      ..lineTo(visible.last.dx, padT + chartH)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.13)
        ..style = PaintingStyle.fill,
    );

    // ── Line ──
    final linePath = Path()
      ..moveTo(visible.first.dx, visible.first.dy);
    for (int i = 1; i < visible.length; i++) {
      linePath.lineTo(visible[i].dx, visible[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color      = const Color(0xFF38BDF8)
        ..strokeWidth = 2.0
        ..style      = PaintingStyle.stroke
        ..strokeCap  = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── Dots for completed data points ──
    for (int i = 0; i < visible.length - 1; i++) {
      canvas.drawCircle(visible[i], 3.5,
          Paint()..color = const Color(0xFF38BDF8));
      canvas.drawCircle(visible[i], 2.0,
          Paint()..color = Colors.white);
    }

    // ── Animated leading dot ──
    final lead = visible.last;
    canvas.drawCircle(lead, 5.5,
        Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.25));
    canvas.drawCircle(lead, 3.5,
        Paint()..color = const Color(0xFF38BDF8));
    canvas.drawCircle(lead, 2.0,
        Paint()..color = Colors.white);

    // ── X-axis: first, middle, last labels ──
    void xLabel(int idx) {
      final o = pt(idx);
      _drawLabel(canvas, '${idx + 1}', o.dx - 5, padT + chartH + 5,
          fontSize: 8);
    }
    xLabel(0);
    if (n > 2) xLabel(n ~/ 2);
    xLabel(n - 1);
  }

  @override
  bool shouldRepaint(_AccuracyLinePainter old) =>
      old.progress != progress || old.history.length != history.length;
}
