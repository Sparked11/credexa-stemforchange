import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connectivity_service.dart';
import '../theme/app_tokens.dart';

/// Floating pill that appears when the connection drops and confirms when it
/// returns. Place it in a Stack above the bottom navigation.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

enum _BannerMode { hidden, offline, restored }

class _OfflineBannerState extends State<OfflineBanner> {
  _BannerMode _mode = _BannerMode.hidden;
  Timer? _hideTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    ConnectivityService.online.addListener(_onChange);
  }

  @override
  void dispose() {
    ConnectivityService.online.removeListener(_onChange);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onChange() {
    final online = ConnectivityService.online.value;
    _hideTimer?.cancel();
    if (!online) {
      setState(() => _mode = _BannerMode.offline);
      HapticFeedback.lightImpact();
    } else if (_mode == _BannerMode.offline) {
      setState(() => _mode = _BannerMode.restored);
      HapticFeedback.selectionClick();
      _hideTimer = Timer(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _mode = _BannerMode.hidden);
      });
    }
  }

  Future<void> _retry() async {
    if (_checking) return;
    HapticFeedback.lightImpact();
    setState(() => _checking = true);
    await ConnectivityService.check();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final show = _mode != _BannerMode.hidden;
    final offline = _mode == _BannerMode.offline;
    final color = offline ? AppColors.amber : AppColors.green;

    return IgnorePointer(
      ignoring: !show,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        offset: show ? Offset.zero : const Offset(0, 1.6),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: show ? 1 : 0,
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: offline ? _retry : null,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                              color: color.withValues(alpha: 0.55)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _checking
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.2, color: color))
                                : Icon(
                                    offline
                                        ? Icons.wifi_off_rounded
                                        : Icons.wifi_rounded,
                                    color: color,
                                    size: 20),
                            const SizedBox(width: 10),
                            Text(
                              offline
                                  ? 'No internet connection'
                                  : 'Back online',
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            if (offline) ...[
                              const SizedBox(width: 10),
                              Text(
                                'Tap to retry',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
