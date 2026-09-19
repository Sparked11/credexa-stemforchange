import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart'; // ignore: unnecessary_import
import 'auth_service.dart';
import 'services/connectivity_service.dart';
import 'theme/app_tokens.dart';
import 'widgets/app_widgets.dart';
import 'legal_page.dart';
import 'widgets/glass_button.dart';

const _kAccent = AppColors.green;

TextStyle _m({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = Colors.white,
  double? height,
  double spacing = 0,
}) =>
    TextStyle(
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing,
    );

// ─────────────────────────────────────────────────────────────────────────────
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with TickerProviderStateMixin {
  bool _isLogin = true;
  bool _termsAccepted = false;
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _termsError = false;
  late final AnimationController _shakeCtrl;
  late final AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _slideCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isLogin = !_isLogin;
      _error = null;
      _termsError = false;
    });
    _slideCtrl
      ..reset()
      ..forward();
  }

  Future<void> _submit() async {
    if (!_requireTermsAccepted()) return;
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      if (_isLogin) {
        if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
          throw 'Please enter your email and password.';
        }
        if (!await ConnectivityService.check()) throw kOfflineMessage;
        await AuthService.signInWithEmail(
            _emailCtrl.text.trim(), _passCtrl.text);
      } else {
        if (_nameCtrl.text.trim().isEmpty) throw 'Please enter your name.';
        if (_emailCtrl.text.trim().isEmpty) throw 'Please enter your email.';
        if (_passCtrl.text.length < 6) {
          throw 'Password must be at least 6 characters.';
        }
        if (_passCtrl.text != _confirmCtrl.text) {
          throw 'Passwords do not match.';
        }
        if (!await ConnectivityService.check()) throw kOfflineMessage;
        await AuthService.createAccount(
            _nameCtrl.text.trim(), _emailCtrl.text.trim(), _passCtrl.text);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = isOfflineError(e) ? kOfflineMessage : e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    if (!_requireTermsAccepted()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await ConnectivityService.check()) throw kOfflineMessage;
      await AuthService.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        setState(() => _error = isOfflineError(e) ? kOfflineMessage : e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Every sign-in path must pass this gate. Returns false (and surfaces the
  /// reason) when the user has not accepted the terms.
  bool _requireTermsAccepted() {
    if (_termsAccepted) return true;
    setState(() {
      _termsError = true;
      _error = null;
    });
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
    return false;
  }

  Widget _termsCheckbox() {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (_, child) {
        final dx = math.sin(_shakeCtrl.value * math.pi * 6) *
            8 *
            (1 - _shakeCtrl.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _termsError
                  ? AppColors.red.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _termsError ? AppColors.red : Colors.transparent),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _termsAccepted,
                    activeColor: _kAccent,
                    checkColor: Colors.white,
                    side: BorderSide(
                        color: _termsError
                            ? AppColors.red
                            : Colors.white.withValues(alpha: 0.6),
                        width: 1.6),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() {
                      _termsAccepted = v ?? false;
                      if (_termsAccepted) _termsError = false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: _m(
                          size: 12,
                          weight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.45),
                      children: [
                        const TextSpan(text: 'I agree to the '),
                        TextSpan(
                          text: 'Terms of Service & Privacy Policy',
                          style: _m(
                              size: 12,
                              weight: FontWeight.w800,
                              color: _kAccent),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const LegalPage()),
                              );
                            },
                        ),
                        const TextSpan(
                            text:
                                ', and understand that Credexa has zero tolerance for '
                                'objectionable content or abusive users.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_termsError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 14, color: Color(0xFFFCA5A5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Please accept the Terms and Privacy Policy to continue.',
                      style: _m(
                          size: 12,
                          weight: FontWeight.w600,
                          color: const Color(0xFFFCA5A5)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _appleSignIn() async {
    if (!_requireTermsAccepted()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await ConnectivityService.check()) throw kOfflineMessage;
      await AuthService.signInWithApple();
    } catch (e) {
      if (mounted) {
        setState(() => _error = (e == kOfflineMessage || isOfflineError(e))
            ? kOfflineMessage
            : 'Could not complete Sign in with Apple. Please try again, or use '
                'Google or email to continue.');
      }
      debugPrint('Apple sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _visToggle(bool obscured, VoidCallback onTap) => IconButton(
        icon: Icon(
          obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: AppColors.slate400,
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.slate900,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset('assets/logomain.png',
                          height: 62, fit: BoxFit.contain),
                      const SizedBox(height: 12),
                      Text(
                        'Your media literacy companion',
                        style: _m(
                            size: 13,
                            weight: FontWeight.w600,
                            color: AppColors.slate400),
                      ),
                      const SizedBox(height: 28),
                      SlideTransition(
                        position: _slideAnim,
                        child: FadeTransition(
                          opacity: _slideCtrl,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 28,
                                    offset: const Offset(0, 10)),
                              ],
                            ),
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                        _isLogin
                                            ? Icons.waving_hand_rounded
                                            : Icons.person_add_alt_1_rounded,
                                        color: AppColors.amber,
                                        size: 26),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        _isLogin
                                            ? 'Welcome back'
                                            : 'Create account',
                                        style: _m(
                                            size: 24, weight: FontWeight.w900),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _isLogin
                                      ? 'Sign in to continue fighting misinformation.'
                                      : 'Join thousands of critical thinkers today.',
                                  style: _m(
                                      size: 13,
                                      weight: FontWeight.w500,
                                      color: AppColors.slate400),
                                ),
                                const SizedBox(height: 22),
                                if (!_isLogin) ...[
                                  _Field(
                                    ctrl: _nameCtrl,
                                    label: 'Full Name',
                                    hint: 'Your name',
                                    icon: Icons.person_outline_rounded,
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                _Field(
                                  ctrl: _emailCtrl,
                                  label: 'Email',
                                  hint: 'you@example.com',
                                  icon: Icons.mail_outline_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 14),
                                _Field(
                                  ctrl: _passCtrl,
                                  label: 'Password',
                                  hint: 'Enter password',
                                  icon: Icons.lock_outline_rounded,
                                  obscure: _obscurePass,
                                  suffixIcon: _visToggle(
                                      _obscurePass,
                                      () => setState(
                                          () => _obscurePass = !_obscurePass)),
                                ),
                                if (!_isLogin) ...[
                                  const SizedBox(height: 14),
                                  _Field(
                                    ctrl: _confirmCtrl,
                                    label: 'Confirm Password',
                                    hint: 'Re-enter password',
                                    icon: Icons.lock_outline_rounded,
                                    obscure: _obscureConfirm,
                                    suffixIcon: _visToggle(
                                        _obscureConfirm,
                                        () => setState(() =>
                                            _obscureConfirm =
                                                !_obscureConfirm)),
                                  ),
                                ],
                                if (_error != null) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AppColors.red
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: AppColors.red
                                              .withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.error_outline_rounded,
                                            size: 16,
                                            color: Color(0xFFFCA5A5)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(_error!,
                                              style: _m(
                                                  size: 12,
                                                  weight: FontWeight.w600,
                                                  color: const Color(
                                                      0xFFFCA5A5))),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),

                                // EULA gate — App Store Guideline 1.2 requires
                                // users to agree to terms before registering or
                                // signing in.
                                _termsCheckbox(),
                                const SizedBox(height: 14),

                                _PrimaryButton(
                                  label: _isLogin ? 'Sign In' : 'Create Account',
                                  loading: _loading,
                                  onTap: _loading ? null : _submit,
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                        child: Divider(
                                            color: Colors.white
                                                .withValues(alpha: 0.2))),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text('or continue with',
                                          style: _m(
                                              size: 12,
                                              weight: FontWeight.w600,
                                              color: AppColors.slate400)),
                                    ),
                                    Expanded(
                                        child: Divider(
                                            color: Colors.white
                                                .withValues(alpha: 0.2))),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _SocialButton(
                                  onTap: _loading ? null : _googleSignIn,
                                  loading: _loading,
                                  label: 'Continue with Google',
                                  icon: const _GoogleIcon(),
                                  bg: Colors.white,
                                  textColor: AppColors.slate800,
                                  border: Colors.white,
                                ),
                                const SizedBox(height: 10),
                                _SocialButton(
                                  onTap: _loading ? null : _appleSignIn,
                                  loading: _loading,
                                  label: 'Continue with Apple',
                                  icon: const Icon(Icons.apple_rounded,
                                      size: 22, color: Colors.white),
                                  bg: Colors.black,
                                  textColor: Colors.white,
                                  border: Colors.white.withValues(alpha: 0.35),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _toggle();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: _m(
                                size: 13,
                                weight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85)),
                            children: [
                              TextSpan(
                                  text: _isLogin
                                      ? "Don't have an account? "
                                      : 'Already have an account? '),
                              TextSpan(
                                text: _isLogin ? 'Sign Up' : 'Sign In',
                                style: _m(
                                    size: 13,
                                    weight: FontWeight.w800,
                                    color: _kAccent),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: _kAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.public_rounded,
                                size: 14, color: _kAccent),
                            const SizedBox(width: 6),
                            Text('Aligned with UN SDG Goal 16',
                                style: _m(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: _kAccent)),
                          ],
                        ),
                      ),
                    ],
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

// ── Text field ────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
  });
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;

  OutlineInputBorder _border(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: _m(
                size: 12,
                weight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.85))),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboardType,
          cursorColor: _kAccent,
          style: _m(size: 14, weight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: _m(
                size: 14, weight: FontWeight.w500, color: AppColors.slate400),
            prefixIcon: Icon(icon, size: 20, color: AppColors.slate400),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: _border(Colors.white.withValues(alpha: 0.28), 1),
            enabledBorder: _border(Colors.white.withValues(alpha: 0.28), 1),
            focusedBorder: _border(_kAccent, 2),
          ),
        ),
      ],
    );
  }
}

// ── Primary button ────────────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: label,
      loading: loading,
      onTap: onTap,
      onDark: true,
      height: 54,
      radius: 14,
      fontSize: 15,
      haptic: GlassHaptic.medium,
    );
  }
}

// ── Social button ─────────────────────────────────────────────────────────────
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.onTap,
    required this.loading,
    required this.label,
    required this.icon,
    required this.bg,
    required this.textColor,
    required this.border,
  });
  final VoidCallback? onTap;
  final bool loading;
  final String label;
  final Widget icon;
  final Color bg, textColor, border;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      filled: false,
      onDark: true,
      onTap: onTap,
      loading: loading,
      height: 52,
      radius: 14,
      haptic: GlassHaptic.medium,
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 10),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _m(
                          size: 14,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
    );
  }
}

// ── Google "G" mark (no asset available) ─────────────────────────────────────
class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text('G',
          style: _m(
              size: 14,
              weight: FontWeight.w900,
              color: const Color(0xFF4285F4),
              height: 1.1)),
    );
  }
}
