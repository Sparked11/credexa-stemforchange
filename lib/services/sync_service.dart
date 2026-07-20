import 'package:cloud_firestore/cloud_firestore.dart';

import 'profile_service.dart';
import 'user_progress_service.dart';

/// Reconciles local (SharedPreferences) state with the cloud (Firestore
/// `users/{uid}` doc) whenever the signed-in account actually changes —
/// on cold-start session restore, sign-in, or switching accounts on the
/// same device. Never runs after every local mutation (that's [ProfileService]
/// and [UserProgressService]'s own `pushToCloud` fire-and-forget calls).
class SyncService {
  SyncService._();

  /// Permanently removes the user's synced document (called during account
  /// deletion). Best-effort — a network failure never blocks the auth-account
  /// deletion that follows.
  static Future<void> deleteUserDoc(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .delete()
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  static Future<void> reconcile(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));

      final remoteProfile = doc.data()?['profile'] as Map<String, dynamic>?;
      if (remoteProfile != null) {
        await ProfileService.applyRemote(remoteProfile);
      } else {
        await ProfileService.pushToCloud();
      }

      final remoteProgress = doc.data()?['progress'] as Map<String, dynamic>?;
      if (remoteProgress != null) {
        await UserProgressService.applyRemote(remoteProgress);
      } else {
        await UserProgressService.pushToCloud();
      }
    } catch (_) {
      // Offline or slow network — local data (already loaded) stays in effect.
    }
  }
}
