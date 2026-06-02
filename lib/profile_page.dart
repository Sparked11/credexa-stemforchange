import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
              SliverToBoxAdapter(child: const _MaturitySection()),
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
//  MATURITY SECTION — inserted between stats and badges on the profile page
// ─────────────────────────────────────────────────────────────────────────────
class _MaturitySection extends StatelessWidget {
  const _MaturitySection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProgressStats>(
      valueListenable: UserProgressService.stats,
      builder: (_, s, __) {
        final lvl      = s.level;
        final progress = lvl.progress(s.maturityPoints);
        final nextIdx  = kMaturityLevels.indexOf(lvl) + 1;
        final nextLvl  =
            nextIdx < kMaturityLevels.length ? kMaturityLevels[nextIdx] : null;
        final pct = s.predictionsTotal == 0
            ? '--'
            : '${(s.predictionAccuracy * 100).round()}%';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(lvl.emoji, style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MEDIA MATURITY',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFBBF7D0),
                                letterSpacing: 1.2,
                              )),
                          Text(lvl.title,
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              )),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text('${s.maturityPoints} pts',
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF4ADE80)),
                  ),
                ),
                const SizedBox(height: 6),
                if (nextLvl != null)
                  Text(
                    '${lvl.pointsToNext(s.maturityPoints)} pts to ${nextLvl.title}',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _mStat('🎯', 'Accuracy', pct),
                    _mDivider(),
                    _mStat('📚', 'Quests', '${s.questsAnswered}'),
                    _mDivider(),
                    _mStat('🔍', 'Predictions', '${s.predictionsTotal}'),
                    _mDivider(),
                    _mStat('✅', 'Correct', '${s.predictionsCorrect}'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mStat(String emoji, String label, String value) => Expanded(
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 3),
            Text(value,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                )),
            Text(label,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.65),
                )),
          ],
        ),
      );

  Widget _mDivider() => Container(
        width: 1,
        height: 36,
        color: Colors.white.withValues(alpha: 0.2),
      );
}
