import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// True if [error] looks like a lost or missing internet connection.
bool isOfflineError(Object? error) {
  if (error is SocketException) return true;
  final raw = (error ?? '').toString().toLowerCase();
  return raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network is unreachable') ||
      raw.contains('no internet') ||
      raw.contains('network-request-failed') ||
      raw.contains('connection failed') ||
      raw.contains('connection closed') ||
      raw.contains('connection reset') ||
      raw.contains('clientexception') && raw.contains('connection');
}

/// Lightweight reachability monitor (no plugin): probes DNS periodically and
/// whenever the app returns to the foreground.
class ConnectivityService {
  ConnectivityService._();

  static final ValueNotifier<bool> online = ValueNotifier<bool>(true);
  static Timer? _timer;
  static bool _probing = false;

  static void start() {
    if (kIsWeb || _timer != null) return;
    _probe();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _probe());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Probes right now and returns the result.
  static Future<bool> check() async {
    if (kIsWeb) return true;
    await _probe();
    return online.value;
  }

  static Future<void> _probe() async {
    if (_probing) return;
    _probing = true;
    try {
      final r = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 3));
      online.value = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      online.value = false;
    } finally {
      _probing = false;
    }
  }
}
