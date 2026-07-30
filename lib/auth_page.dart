import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ignore: unnecessary_import
import 'auth_service.dart';

const _kPrimary    = Color(0xFF1E293B);
const _kSecondary  = Color(0xFF64748B);
const _kAccent     = Color(0xFF22C55E);
const _kBackground = Color(0xFFF1F5F9);

TextStyle _m({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = _kPrimary,
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
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  late final AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _slideCtrl.forward();
  }

  @override
  void dispose() {
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
    });
    _slideCtrl
      ..reset()
      ..forward();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      if (_isLogin) {
        if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
          throw 'Please enter your email and password.';
        }
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
        await AuthService.createAccount(
            _nameCtrl.text.trim(), _emailCtrl.text.trim(), _passCtrl.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.signInWithGoogle();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _appleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.signInWithApple();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not complete Sign in with Apple. Please try again, or use '
            'Google or email to continue.');
      }
      debugPrint('Apple sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
      backgroundColor: _kBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Branding ────────────────────────────────────────────────
              Image.asset('assets/logomain.png', height: 62, fit: BoxFit.contain),
              const SizedBox(height: 12),
              Text(
                'Your media literacy companion',
                style: _m(size: 13, weight: FontWeight.w600, color: _kSecondary),
              ),
              const SizedBox(height: 32),

              // ── Form card ────────────────────────────────────────────────
              SlideTransition(
                position: _slideAnim,
                child: FadeTransition(
                  opacity: _slideCtrl,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 28,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLogin ? 'Welcome back 👋' : 'Create account',
                          style: _m(size: 24, weight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isLogin
                              ? 'Sign in to continue fighting misinformation.'
                              : 'Join thousands of critical thinkers today.',
                          style: _m(
                              size: 13,
                              weight: FontWeight.w500,
                              color: _kSecondary),
                        ),
                        const SizedBox(height: 24),

                        // Name field (signup only)
                        if (!_isLogin) ...[
                          _Field(
                            ctrl: _nameCtrl,
                            label: 'Full Name',
                            hint: 'Your name',
                            icon: Icons.person_outline_rounded,
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Email
                        _Field(
                          ctrl: _emailCtrl,
                          label: 'Email',
                          hint: 'you@example.com',
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 14),

                        // Password
                        _Field(
                          ctrl: _passCtrl,
                          label: 'Password',
                          hint: '••••••••',
                          icon: Icons.lock_outline_rounded,
                          obscure: _obscurePass,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePass
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18,
                              color: _kSecondary,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePass = !_obscurePass),
                          ),
                        ),

                        // Confirm password (signup) / Forgot password (login)
                        if (!_isLogin) ...[
                          const SizedBox(height: 14),
                          _Field(
                            ctrl: _confirmCtrl,
                            label: 'Confirm Password',
                            hint: '••••••••',
                            icon: Icons.lock_outline_rounded,
                            obscure: _obscureConfirm,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18,
                                color: _kSecondary,
                              ),
                              onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text('Forgot password?',
                                style: _m(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    color: _kAccent)),
                          ),
                        ],

                        // Error message
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF5F5),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Text(_error!,
                                style: _m(
                                    size: 12,
                                    weight: FontWeight.w600,
                                    color: const Color(0xFFDC2626))),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Primary CTA
                        _PrimaryButton(
                          label: _isLogin ? 'Sign In' : 'Create Account',
                          loading: _loading,
                          onTap: _loading ? null : _submit,
                        ),
                        const SizedBox(height: 20),

                        // Divider
                        Row(
                          children: [
                            const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('or continue with',
                                  style: _m(
                                      size: 11,
                                      weight: FontWeight.w600,
                                      color: const Color(0xFFCBD5E1))),
                            ),
                            const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Google button
                        _SocialButton(
                          onTap: _loading ? null : _googleSignIn,
                          loading: _loading,
                          label: 'Continue with Google',
                          icon: _GoogleIcon(),
                          bg: Colors.white,
                          textColor: _kPrimary,
                          border: const Color(0xFFE2E8F0),
                        ),
                        const SizedBox(height: 10),

                        // Apple button
                        _SocialButton(
                          onTap: _loading ? null : _appleSignIn,
                          loading: _loading,
                          label: 'Continue with Apple',
                          icon: const Icon(Icons.apple_rounded,
                              size: 20, color: Colors.white),
                          bg: _kPrimary,
                          textColor: Colors.white,
                          border: _kPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Toggle ───────────────────────────────────────────────────
              GestureDetector(
                onTap: () { HapticFeedback.lightImpact(); _toggle(); },
                child: RichText(
                  text: TextSpan(
                    style: _m(size: 13, weight: FontWeight.w500, color: _kSecondary),
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
              const SizedBox(height: 20),

              // ── SDG badge ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '🌐  Aligned with UN SDG Goal 16',
                  style: _m(
                      size: 11,
                      weight: FontWeight.w700,
                      color: _kAccent),
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: _m(size: 12, weight: FontWeight.w700, color: _kSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: _m(size: 14, weight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: _m(
                size: 14,
                weight: FontWeight.w500,
                color: const Color(0xFFCBD5E1)),
            prefixIcon:
                Icon(icon, size: 18, color: const Color(0xFFCBD5E1)),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: _kBackground,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: _kAccent, width: 2)),
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
    return GestureDetector(
      onTap: onTap == null ? null : () { HapticFeedback.mediumImpact(); onTap!(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: loading
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: loading ? const Color(0xFF86EFAC) : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: loading
              ? []
              : [
                  BoxShadow(
                      color: _kAccent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ],
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white)),
                ),
              )
            : Text(label,
                textAlign: TextAlign.center,
                style: _m(
                    size: 15,
                    weight: FontWeight.w800,
                    color: Colors.white)),
      ),
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
    return GestureDetector(
      onTap: onTap == null ? null : () { HapticFeedback.mediumImpact(); onTap!(); },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(textColor)),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(label,
                      style: _m(
                          size: 14,
                          weight: FontWeight.w700,
                          color: textColor)),
                ],
              ),
      ),
    );
  }
}

// ── Google "G" icon ───────────────────────────────────────────────────────────
class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    // Draw the coloured arcs approximating the Google "G"
    final colors = [
      const Color(0xFF4285F4), // blue
      const Color(0xFF34A853), // green
      const Color(0xFFFBBC05), // yellow
      const Color(0xFFEA4335), // red
    ];
    const sweeps = [1.4, 1.57, 0.79, 2.09]; // radians per segment (approx)
    double start = -0.2;
    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 1),
        start,
        sweeps[i],
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.butt,
      );
      start += sweeps[i];
    }
    // Horizontal bar of the G
    canvas.drawRect(
      Rect.fromLTRB(c.dx - 0.5, c.dy - 1.5, c.dx + r - 2, c.dy + 1.5),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
