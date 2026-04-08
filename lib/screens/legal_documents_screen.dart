import 'package:flutter/material.dart';

enum LegalDocumentType { privacyPolicy, termsAndConditions }

class LegalDocumentsScreen extends StatelessWidget {
  final LegalDocumentType type;

  const LegalDocumentsScreen({super.key, required this.type});

  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  @override
  Widget build(BuildContext context) {
    final content = _contentFor(type);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          content.title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Text(
                content.summary,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final section in content.sections) ...[
              _LegalSectionCard(section: section),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  _DocumentContent _contentFor(LegalDocumentType value) {
    switch (value) {
      case LegalDocumentType.privacyPolicy:
        return _DocumentContent(
          title: 'Privacy Policy',
          summary:
              'Last updated: April 8, 2026. This policy explains what TransitPH Beta collects, how data is used, and your choices in the app.',
          sections: const [
            _DocumentSection(
              heading: '1. Information We Collect',
              paragraphs: [
                'Account details: email address, display name, and account identifier from Firebase Authentication.',
                'Profile and activity data: profile settings, route contributions, reports, trust feedback, comments, discussions, and general feedback you submit.',
                'Location data: current GPS location and selected origin/destination locations when you use route search and map features.',
                'Device and app usage data: app version, selected preferences, and operational diagnostics used for reliability and abuse prevention.',
              ],
            ),
            _DocumentSection(
              heading: '2. How We Use Information',
              paragraphs: [
                'Provide transit routing, location-aware navigation, and map experiences.',
                'Operate community features such as posts, comments, moderation, route quality feedback, and announcements.',
                'Secure accounts, prevent abuse, and enforce community standards.',
                'Improve performance and quality of app features through product analysis and debugging.',
              ],
            ),
            _DocumentSection(
              heading: '3. Data Sharing',
              paragraphs: [
                'We use service providers (such as Firebase and mapping/location providers) to host, process, and deliver app functionality.',
                'Public community content you create may be visible to other users depending on your selected posting options.',
                'We may disclose data when required by law, to protect safety, or to prevent fraud and platform abuse.',
              ],
            ),
            _DocumentSection(
              heading: '4. Data Retention',
              paragraphs: [
                'We keep account and operational data while your account is active and as needed for security, moderation, legal, and audit purposes.',
                'Some records may remain in backups or logs for a limited period before deletion cycles complete.',
              ],
            ),
            _DocumentSection(
              heading: '5. Your Choices and Rights',
              paragraphs: [
                'You can control optional settings in the app (for example profile visibility and notifications).',
                'You can deny location permission, but location-dependent features may be limited.',
                'You can request account-related support, including correction or deletion requests, subject to legal and safety obligations.',
              ],
            ),
            _DocumentSection(
              heading: '6. Children\'s Privacy',
              paragraphs: [
                'TransitPH Beta is not intended for children under 13. If you believe a child provided personal data, contact support so we can investigate and remove it where appropriate.',
              ],
            ),
            _DocumentSection(
              heading: '7. Policy Changes',
              paragraphs: [
                'We may update this Privacy Policy as features evolve. Material changes will be reflected by updating the date above and, when needed, through in-app notice.',
              ],
            ),
          ],
        );
      case LegalDocumentType.termsAndConditions:
        return _DocumentContent(
          title: 'Terms and Conditions',
          summary:
              'Last updated: April 8, 2026. These terms govern your use of TransitPH Beta, including routing and community features.',
          sections: const [
            _DocumentSection(
              heading: '1. Acceptance of Terms',
              paragraphs: [
                'By creating an account or using TransitPH Beta, you agree to these Terms and our Privacy Policy.',
                'If you do not agree, do not use the app.',
              ],
            ),
            _DocumentSection(
              heading: '2. Account Responsibilities',
              paragraphs: [
                'You are responsible for safeguarding your account credentials and for activity under your account.',
                'Provide accurate profile information and do not impersonate others.',
              ],
            ),
            _DocumentSection(
              heading: '3. Acceptable Use',
              paragraphs: [
                'Do not post unlawful, abusive, harassing, misleading, or infringing content.',
                'Do not attempt unauthorized access, reverse engineering, scraping abuse, or actions that disrupt app services.',
                'Do not submit false route reports or manipulative feedback intended to harm other users or data quality.',
              ],
            ),
            _DocumentSection(
              heading: '4. Community Content and Moderation',
              paragraphs: [
                'You retain rights in your submitted content, and you grant TransitPH Beta a license to host, display, and process that content to operate the service.',
                'We may review, restrict, or remove content and accounts that violate these Terms or community safety rules.',
              ],
            ),
            _DocumentSection(
              heading: '5. Transit Data and Safety Disclaimer',
              paragraphs: [
                'Routes, ETAs, and transport information are provided on a best-effort basis and may be incomplete, delayed, or inaccurate.',
                'Always use your own judgment and follow local laws, official advisories, and safety rules while traveling.',
              ],
            ),
            _DocumentSection(
              heading: '6. Service Availability',
              paragraphs: [
                'Features may change, be suspended, or be discontinued at any time, including beta-only functionality.',
                'We are not liable for losses resulting from temporary outages, third-party provider downtime, or device incompatibility.',
              ],
            ),
            _DocumentSection(
              heading: '7. Limitation of Liability',
              paragraphs: [
                'To the fullest extent permitted by law, TransitPH Beta is provided "as is" without warranties of uninterrupted or error-free operation.',
                'TransitPH Beta and its operators are not liable for indirect, incidental, special, consequential, or punitive damages arising from app use.',
              ],
            ),
            _DocumentSection(
              heading: '8. Termination',
              paragraphs: [
                'We may suspend or terminate access for violations, abuse, fraud risk, legal compliance, or platform security concerns.',
                'You may stop using the app at any time.',
              ],
            ),
            _DocumentSection(
              heading: '9. Changes to Terms',
              paragraphs: [
                'We may revise these Terms as the service evolves. Continued use after updates means you accept the revised Terms.',
              ],
            ),
          ],
        );
    }
  }
}

class _LegalSectionCard extends StatelessWidget {
  final _DocumentSection section;

  const _LegalSectionCard({required this.section});

  static const _surface = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.heading,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final paragraph in section.paragraphs) ...[
            Text(
              '• $paragraph',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _DocumentContent {
  final String title;
  final String summary;
  final List<_DocumentSection> sections;

  const _DocumentContent({
    required this.title,
    required this.summary,
    required this.sections,
  });
}

class _DocumentSection {
  final String heading;
  final List<String> paragraphs;

  const _DocumentSection({required this.heading, required this.paragraphs});
}