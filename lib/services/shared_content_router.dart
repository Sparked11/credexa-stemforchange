import 'package:flutter/foundation.dart';

/// Central routing point for content that arrives from the iOS Share Extension.
/// _MainAppState reads from ShareService, shows a routing dialog, then sets
/// one of these notifiers. Each destination page listens and consumes the value.
class SharedContentRouter {
  static final forFactcheck = ValueNotifier<Map<String, dynamic>?>(null);
  static final forDebias    = ValueNotifier<Map<String, dynamic>?>(null);
}
