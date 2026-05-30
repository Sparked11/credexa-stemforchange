import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:shared_preferences/shared_preferences.dart';

// ── Badge model (public so auth_service.dart and profile_page.dart can use it) ─

class BadgeInfo {
  const BadgeInfo({
    required this.emoji,
    required this.title,
    required this.desc,
    this.checks   = 0,
    this.debiases = 0,
    this.posts    = 0,
    this.quests   = 0,
  });
  final String emoji;
  final String title;
  final String desc;
  final int checks;
  final int debiases;
  final int posts;
  final int quests;

  bool isEarned(int c, int d, int p, [int q = 0]) =>
      c >= checks && d >= debiases && p >= posts && q >= quests;

  String get requirement {
    final parts = <String>[];
    if (checks   > 0) parts.add('$checks fact-check${checks   == 1 ? '' : 's'}');
    if (debiases > 0) parts.add('$debiases de-bias${debiases == 1 ? '' : 'es'}');
    if (posts    > 0) parts.add('$posts post${posts    == 1 ? '' : 's'}');
    if (quests   > 0) parts.add('$quests quest${quests   == 1 ? '' : 's'}');
    return parts.isEmpty ? 'Joined Credexa' : parts.join(' + ');
  }
}

const kBadges = [
  BadgeInfo(emoji: '🌟', title: 'Welcome!',
      desc: 'You joined Credexa'),
  BadgeInfo(emoji: '🔍', title: 'Fact Finder',
      desc: 'First fact-check completed', checks: 1),
  BadgeInfo(emoji: '🏆', title: 'Truth Seeker',
      desc: 'Completed 5 fact-checks', checks: 5),
  BadgeInfo(emoji: '🎯', title: 'Myth Buster',
      desc: 'Completed 20 fact-checks', checks: 20),
  BadgeInfo(emoji: '🌿', title: 'Bias Aware',
      desc: 'First de-bias completed', debiases: 1),
  BadgeInfo(emoji: '🧠', title: 'Critical Thinker',
      desc: 'Completed 5 de-biases', debiases: 5),
  BadgeInfo(emoji: '💬', title: 'Community Voice',
      desc: 'First community post', posts: 1),
  BadgeInfo(emoji: '🌐', title: 'Hub Regular',
      desc: 'Made 5 community posts', posts: 5),
  BadgeInfo(emoji: '🧭', title: 'Quest Starter',
      desc: 'Completed first quest', quests: 1),
  BadgeInfo(emoji: '⚔️', title: 'Quest Master',
      desc: 'Completed 10 quests', quests: 10),
  BadgeInfo(emoji: '🦁', title: 'Credexa Champion',
      desc: '10 checks + 5 de-biases + 3 posts',
      checks: 10, debiases: 5, posts: 3),
];

// ── Profile data snapshot ─────────────────────────────────────────────────────

class ProfileData {
  const ProfileData({
    this.photoBase64,
    this.checks   = 0,
    this.debiases = 0,
    this.posts    = 0,
    this.quests   = 0,
    this.xp       = 0,
  });
  final String? photoBase64;
  final int checks;
  final int debiases;
  final int posts;
  final int quests;
  final int xp;

  ProfileData copyWith({
    String? photoBase64,
    int? checks,
    int? debiases,
    int? posts,
    int? quests,
    int? xp,
    bool clearPhoto = false,
  }) =>
      ProfileData(
        photoBase64: clearPhoto ? null : (photoBase64 ?? this.photoBase64),
        checks:      checks   ?? this.checks,
        debiases:    debiases ?? this.debiases,
        posts:       posts    ?? this.posts,
        quests:      quests   ?? this.quests,
        xp:          xp       ?? this.xp,
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class ProfileService {
  ProfileService._();

  // Reactive profile state — listen to rebuild UI without Firestore.
  static final data     = ValueNotifier<ProfileData>(const ProfileData());
  // Highest earned badge emoji — used by ProfileIcon overlay.
  static final topBadge = ValueNotifier<String>('🌟');

  // Set once in main() so every ProfileIcon navigates to ProfilePage
  // without any circular import.
  static void Function(BuildContext context)? openProfile;

  static String get _uid =>
      fb.FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  static String _key(String field) => '${_uid}_$field';

  // Load all profile data from SharedPreferences.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final d = ProfileData(
      photoBase64: prefs.getString(_key('photo')),
      checks:      prefs.getInt(_key('checks'))   ?? 0,
      debiases:    prefs.getInt(_key('debiases')) ?? 0,
      posts:       prefs.getInt(_key('posts'))    ?? 0,
      quests:      prefs.getInt(_key('quests'))   ?? 0,
      xp:          prefs.getInt(_key('xp'))       ?? 0,
    );
    data.value = d;
    _refreshTopBadge(d);
  }

  // Save profile photo (base64) locally.
  static Future<void> setPhoto(String base64) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key('photo'), base64);
    final next = data.value.copyWith(photoBase64: base64);
    data.value = next;
    _refreshTopBadge(next);
  }

  // Increment a usage counter and persist.
  static Future<void> _increment(String field) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_key(field)) ?? 0;
    await prefs.setInt(_key(field), current + 1);
    await load();
  }

  static Future<void> incrementCheck()     => _increment('checks');
  static Future<void> incrementDebias()    => _increment('debiases');
  static Future<void> incrementCommunity() => _increment('posts');
  static Future<void> incrementQuests()    => _increment('quests');

  static Future<void> addXp(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_key('xp')) ?? 0;
    await prefs.setInt(_key('xp'), current + amount);
    await load();
  }

  static void _refreshTopBadge(ProfileData d) {
    // Walk backwards so we pick the most prestigious earned badge.
    for (final b in kBadges.reversed) {
      if (b.isEarned(d.checks, d.debiases, d.posts, d.quests)) {
        topBadge.value = b.emoji;
        return;
      }
    }
    topBadge.value = '🌟'; // Welcome badge — always earned.
  }
}
