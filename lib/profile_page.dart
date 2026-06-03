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
    final user        = AuthService.currentUser;
    // Firebase Auth always has creationTime for signed-in users.
    final joinedAt    =
        fb.FirebaseAuth.instance.currentUser?.metadata.creationTime;
    final joinDateStr = joinedAt != null ? _formatDate(joinedAt) : '—';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
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
                      _buildHeader(user, data.photoBase64),
                ),
              ),
              SliverToBoxAdapter(
                  child: _buildStats(data.checks, data.debiases, data.posts)),
              SliverToBoxAdapter(child: const _SurveySection()),
              SliverToBoxAdapter(child: const _ProgressReportSection()),
              SliverToBoxAdapter(
                  child: _buildBadges(
                      data.checks, data.debiases, data.posts, data.quests)),
              SliverToBoxAdapter(
                  child: _buildAccount(user, joinDateStr)),
              SliverToBoxAdapter(child: _buildSignOut(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          );
        },
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader(AuthUser? user, String? photoBase64) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
          begin:  Alignment.topCenter,
          end:    Alignment.bottomCenter,
        ),
      ),
      child: Column(
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
                            errorBuilder: (_, _, _) =>
                                _initialsAvatar(user),
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
                          : const Icon(
                              Icons.camera_alt_rounded,
                              size:  15,
                              color: Colors.white,
                            ),
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
              fontFamily:  'Montserrat',
              fontSize:    20,
              fontWeight:  FontWeight.w900,
              color:       Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: const TextStyle(
              fontFamily:  'Montserrat',
              fontSize:    12,
              fontWeight:  FontWeight.w500,
              color:       Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

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

  Widget _buildStats(int checks, int debiases, int posts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          _statCard('🔍', checks,   'Fact Checks'),
          const SizedBox(width: 12),
          _statCard('🌿', debiases, 'De-Biases'),
          const SizedBox(width: 12),
          _statCard('💬', posts,    'Posts'),
        ],
      ),
    );
  }

  Widget _statCard(String icon, int count, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color:        Colors.white,
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
                style: const TextStyle(
                  fontFamily:  'Montserrat',
                  fontSize:    24,
                  fontWeight:  FontWeight.w900,
                  color:       Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: _mp(size: 10, weight: FontWeight.w600,
                    color: const Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  // ── Badges ───────────────────────────────────────────────────────────────────

  Widget _buildBadges(int checks, int debiases, int posts, int quests) {
    final earned =
        kBadges.where((b) => b.isEarned(checks, debiases, posts, quests)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding:     const EdgeInsets.all(18),
        decoration:  BoxDecoration(
          color:        Colors.white,
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
                    style: _mp(size: 15, weight: FontWeight.w900)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
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

  Widget _buildAccount(AuthUser? user, String joinDateStr) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding:    const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color:        Colors.white,
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
                style: _mp(size: 15, weight: FontWeight.w900)),
            const SizedBox(height: 14),
            _accountRow(Icons.email_outlined, 'Email',
                user?.email ?? '—'),
            _accountRow(Icons.calendar_today_outlined,
                'Member since', joinDateStr),
            _accountRow(
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

  Widget _accountRow(IconData icon, String label, String value,
      {bool last = false}) {
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
                  color:        const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18,
                    color: const Color(0xFF64748B)),
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
                          color:  const Color(0xFF94A3B8),
                        )),
                    const SizedBox(height: 2),
                    Text(value,
                        style: _mp(
                          size:   13,
                          weight: FontWeight.w600,
                          color:  const Color(0xFF1E293B),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!last)
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
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
    return GestureDetector(
      onLongPress: () => _showDetail(context),
      child: AnimatedContainer(
        duration:    const Duration(milliseconds: 300),
        padding:     const EdgeInsets.all(10),
        decoration:  BoxDecoration(
          color:        earned
              ? const Color(0xFFEFFDF4)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: earned
                ? const Color(0xFF22C55E)
                : const Color(0xFFE2E8F0),
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
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFCBD5E1),
              ),
              textAlign: TextAlign.center,
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
            if (!earned) ...[
              const SizedBox(height: 3),
              Text(
                badge.requirement,
                style: const TextStyle(
                  fontFamily:  'Montserrat',
                  fontSize:    7.5,
                  fontWeight:  FontWeight.w500,
                  color:       Color(0xFFCBD5E1),
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
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
                style: const TextStyle(
                  fontFamily:  'Montserrat',
                  fontSize:    17,
                  fontWeight:  FontWeight.w900,
                  color:       Color(0xFF1E293B),
                )),
            const SizedBox(height: 6),
            Text(badge.desc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily:  'Montserrat',
                  fontSize:    13,
                  fontWeight:  FontWeight.w500,
                  color:       Color(0xFF64748B),
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
class _SurveySection extends StatefulWidget {
  const _SurveySection();
  @override
  State<_SurveySection> createState() => _SurveySectionState();
}

class _SurveySectionState extends State<_SurveySection> {
  int          _count    = 0;
  int          _positive = 0;
  List<String> _comments = [];
  bool         _loading  = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final count    = await UserProgressService.getSurveyCount();
    final positive = await UserProgressService.getSurveyPositive();
    final comments = await UserProgressService.getSurveyComments();
    if (mounted) {
      setState(() {
        _count    = count;
        _positive = positive;
        _comments = comments;
        _loading  = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_count == 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Row(
            children: [
              Text('📊', style: TextStyle(fontSize: 22)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Session feedback appears here after every 5 fact-checks.',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pct = (_positive / _count * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('📊', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('Session Feedback',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                  )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFFF5),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text('$pct% helpful',
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF16A34A),
                    )),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Based on $_count session${_count == 1 ? '' : 's'}  •  '
                '$_positive rated helpful',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                )),
            if (_comments.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Recent comments',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  )),
              const SizedBox(height: 8),
              ..._comments.take(3).map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text('"$c"',
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1E293B),
                            height: 1.4,
                          )),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROGRESS REPORT SECTION  — card + share button
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressReportSection extends StatefulWidget {
  const _ProgressReportSection();
  @override
  State<_ProgressReportSection> createState() => _ProgressReportSectionState();
}

class _ProgressReportSectionState extends State<_ProgressReportSection> {
  final _repaintKey = GlobalKey();
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
    final messenger = ScaffoldMessenger.of(context);
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

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'My Credexa Media Literacy Report 🧠\n'
            'Building critical thinking — one fact-check at a time.',
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
    const h   = 1000.0;
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
    final pct      = s.predictionsTotal == 0
        ? '--'
        : '${(s.predictionAccuracy * 100).round()}%';

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
      builder: (_, s, __) => Padding(
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
//  PROGRESS REPORT CARD — the shareable image widget
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressReportCard extends StatelessWidget {
  const _ProgressReportCard({
    required this.stats,
    required this.quote,
  });
  final UserProgressStats stats;
  final String quote;

  @override
  Widget build(BuildContext context) {
    final lvl      = stats.level;
    final progress = lvl.progress(stats.maturityPoints);
    final pct      = stats.predictionsTotal == 0
        ? '--'
        : '${(stats.predictionAccuracy * 100).round()}%';

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
          // ── Header ──
          Row(
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
              const Text('🕊️', style: TextStyle(fontSize: 20)),
            ],
          ),
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
          const SizedBox(height: 18),

          // ── Quote ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: const Color(0xFF4ADE80), width: 3),
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
