import 'package:flutter/material.dart';
import 'theme/app_tokens.dart';
import 'widgets/app_widgets.dart';

// ── Typography helper (matches the rest of the app) ──────────────────────────
TextStyle _m({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = AppColors.slate800,
  double? height,
  double spacing = 0,
}) =>
    TextStyle(
      fontFamily:    'Montserrat',
      fontSize:      size,
      fontWeight:    weight,
      color:         color,
      height:        height,
      letterSpacing: spacing,
    );

BoxDecoration _cardDeco(ColorScheme cs) => BoxDecoration(
      color:        cs.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border:       Border.all(color: cs.outlineVariant),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4)),
      ],
    );

// ─────────────────────────────────────────────────────────────────────────────
//  COMMUNITY SAFETY PAGE
//  Shown from the info button in the Community Hub header. It explains, in
//  plain language, the precautions in place for user-generated content (App
//  Store Guideline 1.2) and where each control lives in the app.
// ─────────────────────────────────────────────────────────────────────────────
class CommunitySafetyPage extends StatelessWidget {
  const CommunitySafetyPage({super.key});

  static const _kSupportEmail = 'credexa.support@gmail.com';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Community safety',
            style: _m(size: 16, weight: FontWeight.w900, color: cs.onSurface)),
        centerTitle: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Community Hub is for respectful, fact-checking conversation. '
            'Here is how we keep it safe, what is not allowed, and the tools '
            'you can use at any time.',
            style: _m(size: 14, weight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.7), height: 1.6),
          ),
          const SizedBox(height: 20),

          _section(
            cs,
            icon: Icons.touch_app_rounded,
            color: AppColors.sky,
            title: 'Your tools, on every post',
            children: [
              _bullet(cs, 'Report', 'Tap Report under any post from another '
                  'user. It is hidden for you straight away and sent for review.'),
              _bullet(cs, 'Block user', 'Open the same Report menu and choose '
                  'Block this user to hide everything they post on your device.'),
              _bullet(cs, 'Delete', 'Tap Delete under your own post to remove it '
                  'from the feed for everyone, immediately.'),
            ],
          ),
          const SizedBox(height: 14),

          _section(
            cs,
            icon: Icons.shield_outlined,
            color: AppColors.green,
            title: 'Checked before it is posted',
            children: [
              _bullet(cs, 'Language filter', 'Every text post is checked against '
                  'a filter for abusive and offensive language. Posts that fail '
                  'the check are not published.'),
              _bullet(cs, 'Image safety check', 'Every image is checked by an AI '
                  'safety review before it can be shared. Explicit, violent or '
                  'otherwise inappropriate images are blocked.'),
            ],
          ),
          const SizedBox(height: 14),

          _section(
            cs,
            icon: Icons.visibility_off_rounded,
            color: AppColors.amber,
            title: 'What happens when a post is reported',
            children: [
              _bullet(cs, 'Hidden quickly', 'A post reported by two different '
                  'people is hidden from everyone while it is reviewed.'),
              _bullet(cs, 'Reviewed within 24 hours', 'Our team reviews reports '
                  'and removes content that breaks these rules.'),
              _bullet(cs, 'Repeat offenders', 'Accounts that repeatedly break '
                  'the rules are restricted from posting. Anyone restricted '
                  'by mistake can write to us to appeal.'),
            ],
          ),
          const SizedBox(height: 14),

          _section(
            cs,
            icon: Icons.block_rounded,
            color: AppColors.red,
            title: 'What is not allowed',
            children: [
              _plain(cs, 'Harassment, bullying, threats or hate toward any person '
                  'or group.'),
              _plain(cs, 'Sexual, explicit or graphically violent content.'),
              _plain(cs, 'Spam, scams, or advertising.'),
              _plain(cs, 'Sharing private information about someone else, such as '
                  'their address, phone number or photos without consent.'),
              _plain(cs, 'Presenting a claim you know is false as fact.'),
            ],
          ),
          const SizedBox(height: 14),

          _section(
            cs,
            icon: Icons.lock_outline_rounded,
            color: AppColors.indigo,
            title: 'Anonymous, not private',
            children: [
              _plain(cs, 'Posts are shown anonymously, so please do not include '
                  'personal details about yourself or others in a post.'),
            ],
          ),
          const SizedBox(height: 20),

          // Contact card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDeco(cs),
            child: Row(
              children: [
                const IconBadge(
                    icon: Icons.mail_outline_rounded,
                    color: AppColors.indigo,
                    size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Questions or concerns?',
                          style: _m(size: 14, weight: FontWeight.w800,
                              color: cs.onSurface)),
                      const SizedBox(height: 4),
                      Text(_kSupportEmail,
                          style: _m(size: 13, weight: FontWeight.w600,
                              color: AppColors.indigo)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    ColorScheme cs, {
    required IconData icon,
    required Color color,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: color, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: _m(size: 14, weight: FontWeight.w800,
                        color: cs.onSurface)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _bullet(ColorScheme cs, String label, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: _m(size: 13, weight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(body,
              style: _m(size: 13, weight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.7), height: 1.55)),
        ],
      ),
    );
  }

  Widget _plain(ColorScheme cs, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(body,
                style: _m(size: 13, weight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.75), height: 1.55)),
          ),
        ],
      ),
    );
  }
}
