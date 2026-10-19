import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum LegalDocumentType { privacyPolicy, termsAndConditions }

class LegalDocumentsScreen extends StatelessWidget {
  final LegalDocumentType type;

  const LegalDocumentsScreen({super.key, required this.type});

  static Color get _bg => AppColors.bg;
  static Color get _surface => AppColors.surface;
  static Color get _surfaceAlt => AppColors.surfaceAlt;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;

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
          style: TextStyle(
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
                style: TextStyle(
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
              'Last updated: October 19, 2026. This policy explains what '
              'TransitPH collects, why, who else handles it, and your '
              'choices. TransitPH is run by the TransitPH team and follows '
              'the Philippine Data Privacy Act of 2012 (Republic Act No. '
              '10173).',
          sections: const [
            _DocumentSection(
              heading: '1. Information We Collect',
              paragraphs: [
                'Account: your email address, display name, profile photo if you add one, and an account ID. Sign-in is handled by Firebase Authentication (including Google sign-in if you use it).',
                'Profile and settings: your rider category (for example Student or Employee), your fare discount setting, and app preferences such as appearance, distance unit and language.',
                'What you share: routes you draw (the line, steps, vehicles, fares, hours and stops), edits and corrections to routes, reports about routes and roads, votes and route feedback, posts, comments, photos and videos you upload, and feedback you send.',
                'Location: your device\'s location while the app is open, to show you on the map, find routes from where you are, and show the weather. While you follow a route, the app keeps using your location in the background, with an ongoing notification, until you stop, arrive, or it pauses after 30 minutes without movement.',
                'Searches: places you search and routes you open, used to suggest routes. Recent searches are also kept on your device.',
                'Rides that leave the route: when a vehicle goes a different way than the route you follow, that path stays on your device. It is only shared if you choose to send it as a route correction.',
                'Device and app information: app version, settings, and error details used to fix problems.',
              ],
            ),
            _DocumentSection(
              heading: '2. How We Use Information',
              paragraphs: [
                'To find and show routes, fares and travel times, and to guide you while you follow a route (including alerts such as "Get off soon" and arrival).',
                'To run community features: reviewing submitted routes before they are published, posts, comments, reports, notifications and achievements.',
                'To keep accounts and the community safe, and to enforce these rules.',
                'To fix problems and improve TransitPH.',
                'We do not sell your personal information, and TransitPH shows no ads.',
              ],
            ),
            _DocumentSection(
              heading: '3. Services That Handle Your Data',
              paragraphs: [
                'Google Firebase stores accounts, routes, posts, reports and settings, and sends notifications.',
                'Cloudinary stores the photos and videos you upload.',
                'Supabase holds public transit data (stops and lines). The points you search from and to are sent to it to find nearby stops.',
                'Map and routing services built on OpenStreetMap data (OpenFreeMap, OSRM, the FOSSGIS routing servers, OpenRouteService and Nominatim) receive map areas and the start, end and drawn points needed to show maps, draw lines along roads and find places.',
                'Open-Meteo receives your approximate location to show the weather. Your phone\'s own location service turns coordinates into place names.',
                'Translation runs on your device; the text is not sent anywhere.',
                'Each service gets only what it needs to do its part.',
              ],
            ),
            _DocumentSection(
              heading: '4. What Other Users See',
              paragraphs: [
                'Your display name and photo appear with the posts, comments and routes you share.',
                'Routes you contribute become visible to everyone once approved. Moderators can see reports and the routes waiting for review.',
                'Your location is never shown to other users.',
              ],
            ),
            _DocumentSection(
              heading: '5. How Long We Keep It',
              paragraphs: [
                'We keep your account data while your account is active, and longer only when needed for safety, moderation or legal reasons.',
                'Routes you contributed may stay available after you leave, because other riders rely on them; you can ask for your name to be removed from them.',
                'Some records may stay in backups for a short time before they are deleted.',
              ],
            ),
            _DocumentSection(
              heading: '6. Your Choices and Rights',
              paragraphs: [
                'You can turn off location access in your phone settings, and stop following a route at any time. Features that need your location will then be limited.',
                'Under the Data Privacy Act you have the right to be informed, to access your data, to object, to have it corrected or erased, to data portability, and to file a complaint with the National Privacy Commission.',
                'To make a request, use Settings → Post Feedback. We may need to confirm the request comes from you.',
              ],
            ),
            _DocumentSection(
              heading: '7. Security',
              paragraphs: [
                'Data is sent over encrypted connections and stored with access rules that limit who can read it. No system is perfectly secure, so please keep your password private.',
              ],
            ),
            _DocumentSection(
              heading: '8. Children\'s Privacy',
              paragraphs: [
                'TransitPH is not intended for children under 13. If you believe a child gave us personal data, tell us through Settings → Post Feedback so we can remove it.',
              ],
            ),
            _DocumentSection(
              heading: '9. Changes to This Policy',
              paragraphs: [
                'We may update this policy as TransitPH changes. The date above shows the latest version, and when the changes are important the app asks you to accept the policy again.',
              ],
            ),
          ],
        );
      case LegalDocumentType.termsAndConditions:
        return _DocumentContent(
          title: 'Terms and Conditions',
          summary:
              'Last updated: October 19, 2026. These terms cover your use of '
              'TransitPH, a free community commuting app run by the TransitPH '
              'team, including route search, following routes, and sharing '
              'routes and posts.',
          sections: const [
            _DocumentSection(
              heading: '1. Accepting These Terms',
              paragraphs: [
                'By creating an account or using TransitPH, you agree to these Terms and the Privacy Policy. If you do not agree, please do not use the app.',
                'TransitPH is in beta: features may change, and some may not work perfectly yet.',
              ],
            ),
            _DocumentSection(
              heading: '2. Your Account',
              paragraphs: [
                'Keep your login details private; you are responsible for what happens under your account.',
                'Use your real information and do not pretend to be someone else.',
              ],
            ),
            _DocumentSection(
              heading: '3. Routes, Fares and Travel Times',
              paragraphs: [
                'Routes come from public transit data, OpenStreetMap and other riders. Generated routes, fares and travel times are estimates and may be incomplete, out of date or wrong.',
                'Always check the vehicle\'s signboard and the fare with the driver or conductor. Fare discounts depend on the vehicle and on showing a valid ID.',
                'Live guidance while following a route depends on your phone\'s GPS and signal. Alerts such as "Get off soon" may come late or not at all, so keep an eye on where you are.',
              ],
            ),
            _DocumentSection(
              heading: '4. Staying Safe',
              paragraphs: [
                'Pay attention to your surroundings, especially when walking or crossing roads. Do not look at your phone when it is unsafe.',
                'Follow traffic rules, official advisories and instructions from transport staff and authorities.',
              ],
            ),
            _DocumentSection(
              heading: '5. Routes and Content You Share',
              paragraphs: [
                'Only share routes, reports, posts and photos that are accurate as far as you know and that you have the right to share.',
                'You keep ownership of what you share. You allow TransitPH to store, show, translate and adjust it (for example, moderators correcting a line or fare), and to combine your routes with others when building trips for riders.',
                'New routes and edits are reviewed by moderators before they appear for everyone. We may decline, change or remove content that is inaccurate or breaks these Terms.',
              ],
            ),
            _DocumentSection(
              heading: '6. Things You Must Not Do',
              paragraphs: [
                'Post content that is illegal, abusive, hateful, harassing, misleading or someone else\'s without permission.',
                'Submit fake routes, false reports or votes meant to mislead other riders.',
                'Try to break into accounts or systems, copy data in bulk, or disrupt the app.',
              ],
            ),
            _DocumentSection(
              heading: '7. Map Data and Other Services',
              paragraphs: [
                'Maps and some routes use OpenStreetMap data © OpenStreetMap contributors, available under the Open Database License. Tap the ⓘ on a map to see the credits.',
                'Some features rely on outside services (for example maps, routing and weather). We are not responsible for their availability or accuracy.',
              ],
            ),
            _DocumentSection(
              heading: '8. Limitation of Liability',
              paragraphs: [
                'TransitPH is provided "as is", without any promise that it will always work or be error-free.',
                'To the fullest extent the law allows, the TransitPH team is not liable for missed trips, delays, fares paid, or any indirect or consequential loss from using the app.',
              ],
            ),
            _DocumentSection(
              heading: '9. Suspension and Ending Your Use',
              paragraphs: [
                'We may restrict or suspend accounts that break these Terms, for a time or permanently.',
                'You can stop using TransitPH at any time and ask for your account to be deleted through Settings → Post Feedback.',
              ],
            ),
            _DocumentSection(
              heading: '10. Changes and Governing Law',
              paragraphs: [
                'We may update these Terms. When the changes are important, the app asks you to accept them again.',
                'These Terms are governed by the laws of the Philippines.',
                'Questions? Reach us through Settings → Post Feedback.',
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

  static Color get _surface => AppColors.surface;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;

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
            style: TextStyle(
              color: _textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final paragraph in section.paragraphs) ...[
            Text(
              '• $paragraph',
              style: TextStyle(
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
