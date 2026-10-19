import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cached_network_image/cached_network_image.dart';

import '../models/feedback.dart' as feedback_model;
import '../screens/legal_documents_screen.dart';
import '../screens/onboarding_screen.dart';
import '../services/tutorial_service.dart';
import '../widgets/tutorial_overlay.dart';
import '../repositories/route_cache_repository.dart';
import '../services/media_service.dart';
import '../services/moderation_service.dart';
import '../services/map_style_service.dart';
import '../services/settings_service.dart';
import '../services/gamification_service.dart';
import '../widgets/translate_chathead.dart';
import '../widgets/translated_text.dart';
import '../theme/app_colors.dart';
part 'settings_screen_dialogs.dart';

class SettingsScreen extends StatefulWidget {
  final String userName;
  final String userEmail;
  final String? userPhotoUrl;

  const SettingsScreen({
    super.key,
    required this.userName,
    required this.userEmail,
    this.userPhotoUrl,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool routeApprovalUpdates = false;
  bool newDiscussions = false;
  bool _isSubmittingFeedback = false;
  bool _isLoadingPreferences = true;
  bool _isSavingPreferences = false;
  bool _isClearingRouteCache = false;
  bool _isLoggingOut = false;
  bool _isUploadingPhoto = false;

  String language = 'English';
  String distanceUnit = 'Miles';

  bool showEmailInProfile = false;
  late String _displayName;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _displayName = widget.userName;
    _photoUrl = widget.userPhotoUrl;
    _loadPreferences();
  }

  void _setPhotoUrl(String? value) {
    setState(() {
      _photoUrl = value;
    });
  }

  void _setUploadingPhoto(bool value) {
    setState(() {
      _isUploadingPhoto = value;
    });
  }

  Future<void> _showEditProfileDialog() async {
    await this._showEditProfileDialogSection();
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await SettingsService.loadPreferences();
      if (!mounted) return;

      setState(() {
        routeApprovalUpdates =
            preferences['routeApprovalUpdates'] as bool? ?? false;
        newDiscussions = preferences['newDiscussions'] as bool? ?? false;
        distanceUnit = preferences['distanceUnit'] as String? ?? 'Miles';
        language = preferences['language'] as String? ?? 'English';
        showEmailInProfile =
            preferences['showEmailInProfile'] as bool? ?? false;
        _isLoadingPreferences = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPreferences = false;
      });
    }
  }

  Future<void> _savePreferences() async {
    setState(() {
      _isSavingPreferences = true;
    });

    await SettingsService.savePreferences({
      'routeApprovalUpdates': routeApprovalUpdates,
      'newDiscussions': newDiscussions,
      'distanceUnit': distanceUnit,
      'language': language,
      'showEmailInProfile': showEmailInProfile,
    });

    if (!mounted) return;
    setState(() {
      _isSavingPreferences = false;
    });
  }

  void _updateBooleanPreference({
    required void Function(bool value) updater,
    required bool value,
  }) {
    setState(() {
      updater(value);
    });
    _savePreferences();
  }

  void _updateDistanceUnit(String value) {
    setState(() {
      distanceUnit = value;
    });
    _savePreferences();
  }

  void _updateLanguage(String value) {
    setState(() {
      language = value;
    });
    _savePreferences();
  }

  Future<void> _clearGeneratedRouteCache() async {
    await this._clearGeneratedRouteCacheSection();
  }

  void _setRouteCacheClearing(bool value) {
    setState(() {
      _isClearingRouteCache = value;
    });
  }

  void _setDisplayName(String value) {
    setState(() {
      _displayName = value;
    });
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      await firebase_auth.FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  // ─── Color tokens
  static Color get _bg => AppColors.bg;
  static Color get _surface => AppColors.surface;
  static Color get _surfaceAlt => AppColors.surfaceAlt;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _accentSoft => AppColors.accentSoft;
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;

  // ─── Section card wrapper
  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: _accent, size: 15),
                ),
                const SizedBox(width: 10),
                TranslatedText(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          ...children,
        ],
      ),
    );
  }

  // ─── Toggle row
  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    TranslatedText(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: _accent,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: _border,
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(color: _border, height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  static const _mapLookLabels = {
    MapLook.classic: 'Classic',
    MapLook.clean: 'Clean',
  };
  static const _appearanceLabels = {
    Appearance.light: 'Light',
    Appearance.dark: 'Dark',
    Appearance.auto: 'Auto',
    Appearance.system: 'Follow phone',
  };

  // ─── Dropdown row
  Widget _dropdownRow<T>({
    required String title,
    required String subtitle,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    TranslatedText(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: _textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<T>(
                    value: value,
                    isDense: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _accent,
                      size: 18,
                    ),
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    dropdownColor: _surface,
                    borderRadius: BorderRadius.circular(12),
                    items:
                        items
                            .map(
                              (item) => DropdownMenuItem<T>(
                                value: item,
                                child: Text('$item'),
                              ),
                            )
                            .toList(),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(color: _border, height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  // ─── Info row
  Widget _infoRow({
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: TranslatedText(
                  label,
                  style: TextStyle(fontSize: 14, color: _textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(color: _border, height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  // ─── Ghost action button
  Widget _actionRow({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isLast = false,
    Color? color,
  }) {
    final c = color ?? _accent;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: c),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TranslatedText(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: _textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(color: _border, height: 1, indent: 16, endIndent: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPreferences) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _surface,
          foregroundColor: _textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: Text(
            'Settings',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      // ─── AppBar
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 15,
              color: _textSecondary,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.settings_outlined,
                color: _accent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            TranslatedText(
              'Settings',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
              ),
            ),
          ],
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
            // ─── Page title
            TranslatedText(
              'Customize your experience',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
            const SizedBox(height: 20),

            // ─── Account
            _section(
              title: 'Account',
              icon: Icons.person_outline_rounded,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap:
                            _isUploadingPhoto
                                ? null
                                : () => _changeProfilePhotoSection(),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0B8FD6),
                                    Color(0xFF2BB5F0),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child:
                                  _isUploadingPhoto
                                      ? const Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                      : (_photoUrl != null &&
                                          _photoUrl!.isNotEmpty)
                                      ? CachedNetworkImage(
                                        imageUrl: _photoUrl!,
                                        fit: BoxFit.cover,
                                        width: 46,
                                        height: 46,
                                        errorWidget:
                                            (_, __, ___) => Center(
                                              child: Text(
                                                _displayName.isNotEmpty
                                                    ? _displayName[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                      )
                                      : Center(
                                        child: Text(
                                          _displayName.isNotEmpty
                                              ? _displayName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: _accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _surface, width: 2),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.userEmail,
                              style: TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _showEditProfileDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _accentSoft,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _accent.withOpacity(0.25),
                            ),
                          ),
                          child: const Text(
                            'Edit Profile',
                            style: TextStyle(
                              color: _accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── Notifications
            _section(
              title: 'Notifications',
              icon: Icons.notifications_outlined,
              children: [
                _toggleRow(
                  title: 'Route Approval Updates',
                  subtitle:
                      'Get notified when your routes are approved/rejected',
                  value: routeApprovalUpdates,
                  onChanged:
                      (val) => _updateBooleanPreference(
                        updater: (value) => routeApprovalUpdates = value,
                        value: val,
                      ),
                ),
                _toggleRow(
                  title: 'New Discussions',
                  subtitle:
                      'Be notified on your posts in community discussions',
                  value: newDiscussions,
                  onChanged:
                      (val) => _updateBooleanPreference(
                        updater: (value) => newDiscussions = value,
                        value: val,
                      ),
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── Preferences
            _section(
              title: 'Preferences',
              icon: Icons.tune_rounded,
              children: [
                _dropdownRow<String>(
                  title: 'Language',
                  subtitle: 'Choose your preferred language',
                  value: language,
                  items: ['English', 'Filipino', 'Spanish'],
                  onChanged: (val) {
                    if (val != null) _updateLanguage(val);
                  },
                ),
                _dropdownRow<String>(
                  title: 'Distance Unit',
                  subtitle: 'How to display distances',
                  value: distanceUnit,
                  items: ['Miles', 'Kilometers'],
                  onChanged: (val) {
                    if (val != null) _updateDistanceUnit(val);
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: TranslateChatHead.enabled,
                  builder:
                      (context, enabled, _) => _toggleRow(
                        title: 'Translate Bubble',
                        subtitle:
                            'Show the floating button for quick translations',
                        value: enabled,
                        onChanged: TranslateChatHead.setEnabled,
                      ),
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    MapStyleService.instance.look,
                    MapStyleService.instance.appearance,
                  ]),
                  builder: (context, _) {
                    final styles = MapStyleService.instance;
                    return Column(
                      children: [
                        _dropdownRow<String>(
                          title: 'Map Style',
                          subtitle:
                              'Clean is calm and minimal; Classic is colorful',
                          value: _mapLookLabels[styles.look.value]!,
                          items: _mapLookLabels.values.toList(),
                          onChanged: (label) {
                            final look =
                                _mapLookLabels.entries
                                    .where((e) => e.value == label)
                                    .firstOrNull
                                    ?.key;
                            if (look != null) styles.setLook(look);
                          },
                        ),
                        _dropdownRow<String>(
                          title: 'Appearance',
                          subtitle: 'Auto is dark from 6 PM to 6 AM',
                          value: _appearanceLabels[styles.appearance.value]!,
                          items: _appearanceLabels.values.toList(),
                          onChanged: (label) {
                            final appearance =
                                _appearanceLabels.entries
                                    .where((e) => e.value == label)
                                    .firstOrNull
                                    ?.key;
                            if (appearance != null) {
                              styles.setAppearance(appearance);
                            }
                          },
                          isLast: true,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── Privacy
            _section(
              title: 'Privacy',
              icon: Icons.shield_outlined,
              children: [
                _toggleRow(
                  title: 'Show Email in Profile',
                  subtitle: 'Allow others to see your email address',
                  value: showEmailInProfile,
                  onChanged:
                      (val) => _updateBooleanPreference(
                        updater: (value) => showEmailInProfile = value,
                        value: val,
                      ),
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_isSavingPreferences)
              Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TranslatedText(
                    'Saving settings...',
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ),
              ),

            _section(
              title: 'Storage',
              icon: Icons.storage_rounded,
              children: [
                _actionRow(
                  label:
                      _isClearingRouteCache
                          ? 'Clearing auto-generated route cache...'
                          : 'Clear auto-generated route cache',
                  icon: Icons.delete_sweep_outlined,
                  onTap:
                      _isClearingRouteCache ? () {} : _clearGeneratedRouteCache,
                  isLast: true,
                  color: const Color(0xFFD14343),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── About
            _section(
              title: 'About',
              icon: Icons.info_outline_rounded,
              children: [
                // From the installed app, so it can't go stale.
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder:
                      (context, snapshot) => _infoRow(
                        label: 'Version',
                        value: snapshot.data?.version ?? '…',
                      ),
                ),
                _infoRow(label: 'Last Updated', value: 'October 2026'),
                Divider(color: _border, height: 1),
                _actionRow(
                  label: 'Privacy Policy',
                  icon: Icons.lock_outline_rounded,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => const LegalDocumentsScreen(
                              type: LegalDocumentType.privacyPolicy,
                            ),
                      ),
                    );
                  },
                ),
                _actionRow(
                  label: 'Terms of Service',
                  icon: Icons.description_outlined,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => const LegalDocumentsScreen(
                              type: LegalDocumentType.termsAndConditions,
                            ),
                      ),
                    );
                  },
                ),
                _actionRow(
                  label: 'Post Feedback',
                  icon: Icons.rate_review_outlined,
                  onTap: () => _showFeedbackDialog(context),
                  isLast: !kDebugMode,
                  color: const Color(0xFF9B7FE8),
                ),
                // Debug builds only: see the first-launch cards again.
                if (kDebugMode) ...[
                  _actionRow(
                    label: 'Replay intro (debug)',
                    icon: Icons.slideshow_rounded,
                    onTap: _replayIntro,
                  ),
                  _actionRow(
                    label: 'Replay contribute tutorial (debug)',
                    icon: Icons.school_outlined,
                    onTap: _replayTutorial,
                    isLast: true,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ─── Log out
            _logoutButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _replayIntro() {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(user: user, replay: true),
      ),
    );
  }

  void _replayTutorial() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder:
            (context, _, _) => Stack(
              children: [
                TutorialOverlay(
                  steps: TutorialService.getContributeTutorialSteps(),
                  onComplete: () => Navigator.of(context).pop(),
                ),
              ],
            ),
      ),
    );
  }

  Widget _logoutButton() {
    const danger = Color(0xFFD14343);
    return GestureDetector(
      onTap: _isLoggingOut ? null : _logout,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: danger.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: danger.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoggingOut)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: danger, strokeWidth: 2),
              )
            else
              const Icon(Icons.logout_rounded, color: danger, size: 18),
            const SizedBox(width: 8),
            TranslatedText(
              _isLoggingOut ? 'Logging out...' : 'Log Out',
              style: const TextStyle(
                color: danger,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFeedbackDialog(BuildContext context) {
    final TextEditingController feedbackController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(bottom: BorderSide(color: _border)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF9B7FE8).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.rate_review_outlined,
                            color: Color(0xFF9B7FE8),
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        TranslatedText(
                          'Post Feedback',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: TextField(
                        controller: feedbackController,
                        maxLines: 5,
                        style: TextStyle(color: _textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Enter your feedback here...',
                          hintStyle: TextStyle(
                            color: _textSecondary,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: _border),
                              ),
                              alignment: Alignment.center,
                              child: TranslatedText(
                                'Cancel',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () async {
                              if (_isSubmittingFeedback) return;
                              final content = feedbackController.text.trim();
                              if (content.isEmpty) return;

                              setState(() => _isSubmittingFeedback = true);
                              try {
                                final feedback = feedback_model.Feedback(
                                  id:
                                      DateTime.now().millisecondsSinceEpoch
                                          .toString(),
                                  userId: widget.userEmail,
                                  type: feedback_model.FeedbackType.feedback,
                                  content: content,
                                  targetType:
                                      feedback_model.FeedbackTargetType.general,
                                  timestamp: DateTime.now(),
                                );
                                await ModerationService.addFeedback(feedback);
                                if (!mounted) return;
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Feedback submitted'),
                                  ),
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _isSubmittingFeedback = false);
                                }
                              }
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0B8FD6),
                                    Color(0xFF2BB5F0),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: [
                                  BoxShadow(
                                    color: _accent.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const TranslatedText(
                                'Submit Feedback',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
