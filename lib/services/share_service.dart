import 'package:flutter/services.dart';

class ShareService {
  static const _channel = MethodChannel('credexa/share');

  static Future<Map<String, dynamic>?> getSharedContent() async {
    try {
      final result = await _channel.invokeMethod<Object?>('getSharedContent');
      if (result == null) return null;
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSharedContent() async {
    try {
      await _channel.invokeMethod<void>('clearSharedContent');
    } catch (_) {}
  }
}
