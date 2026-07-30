import 'package:flutter/material.dart';

/// Terms of Service + Privacy Policy, shown from the Profile page and required
/// for App Store review (UGC apps must present terms; a matching hosted URL
/// goes in App Store Connect).
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  static const _effectiveDate = 'July 29, 2026';
  static const _contactEmail  = 'support@credexa.app';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Terms & Privacy',
            style: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        children: [
          _title('Terms of Service'),
          _meta('Effective date: $_effectiveDate'),
          const SizedBox(height: 16),

          _h('1. Acceptance of Terms'),
          _p('By downloading, accessing, or using Credexa ("the App"), you agree '
              'to these Terms of Service and the Privacy Policy below. If you do '
              'not agree, please do not use the App.'),

          _h('2. Eligibility'),
          _p('Credexa is intended for users aged 13 and older. By using the App, '
              'you confirm that you are at least 13 years old. If you are under '
              'the age of majority where you live, please review these terms with '
              'a parent or guardian.'),

          _h('3. What Credexa Does'),
          _p('Credexa is a media-literacy tool that helps you analyze news, social '
              'media posts, and other content for credibility, bias, and '
              'misinformation using artificial intelligence. It also offers '
              'educational quests, a community space, and related features.'),

          _h('4. AI-Generated Content'),
          _p('Credexa uses automated AI systems to generate fact-checks, bias '
              'analyses, and explanations. This information is provided for '
              'educational purposes only and may be incomplete, inaccurate, or out '
              'of date. It is not professional, legal, medical, or financial '
              'advice. Always verify important information with trusted primary '
              'sources and use your own judgment.'),

          _h('5. Community Guidelines & Conduct'),
          _p('When posting in the Community Hub or submitting content, you agree '
              'not to post anything unlawful, hateful, harassing, threatening, '
              'sexually explicit, violent, defamatory, or otherwise objectionable. '
              'You are solely responsible for the content you submit. Credexa has '
              'zero tolerance for objectionable content or abusive behavior: we use '
              'automated filtering plus a report-and-block system, and we may '
              'remove content and restrict or terminate accounts that violate '
              'these terms.'),

          _h('6. Your Content'),
          _p('You keep ownership of the content you submit, but you grant Credexa '
              'a non-exclusive, worldwide, royalty-free license to store, display, '
              'and process that content in order to operate and improve the App.'),

          _h('7. Intellectual Property'),
          _p('The App, its design, and its original content (excluding '
              'user-submitted content) belong to Credexa and are protected by '
              'applicable laws.'),

          _h('8. Termination'),
          _p('We may suspend or end your access to the App at any time if you '
              'violate these terms or misuse the service.'),

          _h('9. Disclaimers & Limitation of Liability'),
          _p('The App is provided "as is" without warranties of any kind. To the '
              'fullest extent permitted by law, Credexa is not liable for any '
              'damages arising from your use of, or reliance on, the App or its '
              'AI-generated content.'),

          _h('10. Changes to These Terms'),
          _p('We may update these Terms from time to time. Continuing to use the '
              'App after changes take effect means you accept the revised Terms.'),

          _h('11. Contact'),
          _p('Questions about these Terms? Contact us at $_contactEmail.'),

          const SizedBox(height: 32),
          Divider(color: cs.onSurface.withValues(alpha: 0.12)),
          const SizedBox(height: 24),

          _title('Privacy Policy'),
          _meta('Effective date: $_effectiveDate'),
          const SizedBox(height: 16),

          _h('1. Information We Collect'),
          _p('• Account information: when you sign in (via email, Google, or '
              'Apple), we collect your name and email address to create and manage '
              'your account.\n'
              '• Usage & progress data: your activity, stats, streaks, maturity '
              'level, and accuracy history.\n'
              '• Content you submit: text, links, and images you provide for '
              'fact-checking, de-biasing, or posting in the Community Hub.'),

          _h('2. Camera, Face Data & the TrueDepth API'),
          _p('Trust Lens uses your device camera to read on-screen text and to '
              'locate faces so it can flag possible synthetic or manipulated '
              'imagery. When you switch Trust Lens to the front camera on a '
              'device with Face ID hardware, the App starts an ARKit face-tracking '
              'session, which uses Apple\'s TrueDepth API to supply the camera '
              'feed.\n'
              '• We do not collect, record, or use face geometry, depth maps, '
              'facial expression data, or any faceprint. The App never reads '
              'ARKit\'s face mesh or blend-shape values, and we do not perform '
              'face recognition or identification.\n'
              '• Face detection produces only anonymous on-screen rectangles '
              '(the position and size of a detected face). These rectangles are '
              'used solely to draw the live overlay and are discarded frame by '
              'frame.\n'
              '• All camera and face processing happens entirely on your device. '
              'Camera frames, face rectangles, and face data are never uploaded '
              'to our servers, never stored on the device or in the cloud, never '
              'retained after the Trust Lens screen closes, and never shared '
              'with or sold to any third party — including for advertising, '
              'marketing, or third-party analytics.\n'
              '• Because no face data is stored or transmitted, there is nothing '
              'to retain or delete; it exists only in memory while Trust Lens is '
              'open and is released when you leave the screen.\n'
              '• Photos you deliberately choose to submit for AI analysis are '
              'handled under Sections 1 and 4, not under this Section.'),

          _h('3. How We Use Your Information'),
          _p('We use your information to provide and improve the App\'s features, '
              'personalize your experience, sync your progress across devices, '
              'operate the community, and maintain safety through content '
              'moderation.'),

          _h('4. Third-Party Services'),
          _p('Credexa relies on trusted third parties to function:\n'
              '• Google Firebase (Authentication and Cloud Firestore) for sign-in '
              'and data storage.\n'
              '• AI providers (accessed via OpenRouter) to analyze content you '
              'submit for fact-checking and bias detection.\n'
              '• Public news sources used for verification.\n'
              'Content you submit for analysis may be transmitted to these '
              'providers to generate your results.'),

          _h('5. Data Storage & Security'),
          _p('Your data is stored securely using Google Firebase. We take '
              'reasonable measures to protect it, but no method of transmission or '
              'storage is completely secure.'),

          _h('6. Children\'s Privacy'),
          _p('Credexa is intended for users 13 and older. We do not knowingly '
              'collect personal information from children under 13. If you believe '
              'a child under 13 has provided us information, contact us and we will '
              'delete it.'),

          _h('7. Your Choices & Rights'),
          _p('You can review your data in the app and sign out at any time. You '
              'can permanently delete your account and associated data directly '
              'in the app from Profile → Delete Account.'),

          _h('8. Data Sharing'),
          _p('We do not sell your personal information. We share it only with the '
              'service providers described above, or when required by law.'),

          _h('9. Changes to This Policy'),
          _p('We may update this Privacy Policy periodically. Material changes will '
              'be reflected by updating the effective date above.'),

          _h('10. Contact'),
          _p('For privacy questions or data requests, contact $_contactEmail.'),
        ],
      ),
    );
  }

  // ── Text builders (theme-aware via Builder for colorScheme access) ──────────
  Widget _title(String text) => Builder(builder: (context) {
        return Text(text,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ));
      });

  Widget _meta(String text) => Builder(builder: (context) {
        return Text(text,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ));
      });

  Widget _h(String text) => Builder(builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(text,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              )),
        );
      });

  Widget _p(String text) => Builder(builder: (context) {
        return Text(text,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
            ));
      });
}
