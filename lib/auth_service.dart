import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'services/profile_service.dart';

// ── User model ────────────────────────────────────────────────────────────────
class AuthUser {
  const AuthUser({required this.name, required this.email});
  final String name;
  final String email;

  String get initials =>
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'U';
}

// ── Auth service ───────────────────────────────────────────────────────────────
class AuthService {
  AuthService._();

  static final _state = ValueNotifier<AuthUser?>(null);

  static ValueListenable<AuthUser?> get authState => _state;
  static AuthUser? get currentUser => _state.value;
  static bool get isLoggedIn => _state.value != null;

  // Listen to Firebase auth state changes so sign-out / token expiry is picked up
  static void init() {
    fb.FirebaseAuth.instance.authStateChanges().listen((fbUser) {
      if (fbUser == null) {
        _state.value = null;
      } else {
        _state.value = AuthUser(
          name: fbUser.displayName ?? _nameFromEmail(fbUser.email ?? ''),
          email: fbUser.email ?? '',
        );
        ProfileService.load(); // hydrate profile icon + stats immediately on login
      }
    });
  }

  static Future<void> signInWithEmail(String email, String password) async {
    final cred = await fb.FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email.trim(), password: password);
    _state.value = AuthUser(
      name: cred.user!.displayName ?? _nameFromEmail(email),
      email: cred.user!.email!,
    );
  }

  static Future<void> createAccount(
      String name, String email, String password) async {
    final cred = await fb.FirebaseAuth.instance
        .createUserWithEmailAndPassword(
            email: email.trim(), password: password);
    await cred.user!.updateDisplayName(name.trim());
    _state.value = AuthUser(name: name.trim(), email: cred.user!.email!);
  }

  static Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      // Web: use Firebase popup flow
      final provider = fb.GoogleAuthProvider();
      final cred =
          await fb.FirebaseAuth.instance.signInWithPopup(provider);
      _state.value = AuthUser(
        name: cred.user!.displayName ?? 'User',
        email: cred.user!.email!,
      );
    } else {
      // Native: use google_sign_in package
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // user cancelled
      final googleAuth = await googleUser.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final cred =
          await fb.FirebaseAuth.instance.signInWithCredential(credential);
      _state.value = AuthUser(
        name: cred.user!.displayName ?? 'User',
        email: cred.user!.email!,
      );
    }
  }

  static Future<void> signInWithApple() async {
    if (kIsWeb) {
      // Web: use Firebase OAuth popup
      final provider = fb.OAuthProvider('apple.com')
        ..addScope('email')
        ..addScope('name');
      final cred =
          await fb.FirebaseAuth.instance.signInWithPopup(provider);
      _state.value = AuthUser(
        name: cred.user!.displayName ?? 'Apple User',
        email: cred.user!.email ?? '',
      );
    } else {
      // Native iOS/macOS: use sign_in_with_apple package
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = fb.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final cred =
          await fb.FirebaseAuth.instance.signInWithCredential(oauthCredential);
      _state.value = AuthUser(
        name: cred.user!.displayName ?? 'Apple User',
        email: cred.user!.email ?? '',
      );
    }
  }

  static Future<void> signOut() async {
    await fb.FirebaseAuth.instance.signOut();
    _state.value = null;
  }

  static String _nameFromEmail(String email) {
    if (email.isEmpty) return 'User';
    final local = email.split('@').first;
    return local[0].toUpperCase() + local.substring(1);
  }
}

// ── Profile icon (drop-in widget for every navbar) ────────────────────────────
class ProfileIcon extends StatelessWidget {
  const ProfileIcon({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthService.authState,
      builder: (_, user, _) => ValueListenableBuilder<ProfileData>(
        valueListenable: ProfileService.data,
        builder: (_, profileData, _) {
          // Decode stored photo once per build.
          final photoBytes = profileData.photoBase64 != null
              ? base64Decode(profileData.photoBase64!)
              : null;

          // Highest earned badge.
          String badge = '🌟';
          for (final b in kBadges.reversed) {
            if (b.isEarned(profileData.checks, profileData.debiases,
                profileData.posts, profileData.quests)) {
              badge = b.emoji;
              break;
            }
          }

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (onTap != null) {
                onTap!();
              } else if (ProfileService.openProfile != null) {
                ProfileService.openProfile!(context);
              } else {
                _showProfileSheet(context, user);
              }
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: photoBytes != null
                        ? Image.memory(photoBytes,
                            width: 38, height: 38, fit: BoxFit.cover)
                        : Center(
                            child: Text(
                              user?.initials ?? 'U',
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                ),
                // Badge overlay — bottom-left corner of the avatar
                Positioned(
                  left:   -2,
                  bottom: -2,
                  child: Container(
                    width:  18,
                    height: 18,
                    decoration: BoxDecoration(
                      color:  Colors.white,
                      shape:  BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color:      Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset:     const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(badge,
                          style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Profile bottom sheet ──────────────────────────────────────────────────────
void _showProfileSheet(BuildContext context, AuthUser? user) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ProfileSheet(user: user),
  );
}

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet({required this.user});
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          // Avatar
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                user?.initials ?? 'U',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            user?.name ?? 'User',
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 28),
          // SDG badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Text(
              '🌐  UN SDG Goal 16 Member',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),
          // Sign out
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              AuthService.signOut();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded,
                      size: 18, color: Color(0xFFEF4444)),
                  SizedBox(width: 8),
                  Text(
                    'Sign Out',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEF4444),
                    ),
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
