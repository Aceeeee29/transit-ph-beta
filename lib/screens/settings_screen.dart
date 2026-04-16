import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../models/feedback.dart' as feedback_model;
import '../screens/legal_documents_screen.dart';
import '../services/moderation_service.dart';
import '../services/settings_service.dart';
import '../services/gamification_service.dart';

class SettingsScreen extends StatefulWidget {
  final String userName;
  final String userEmail;

  const SettingsScreen({
    super.key,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool routeApprovalUpdates = false;
  bool newDiscussions = false;
  bool weeklyDigest = false;
  bool _isSubmittingFeedback = false;
  bool _isLoadingPreferences = true;
  bool _isSavingPreferences = false;

  String language = 'English';
  String distanceUnit = 'Miles';

  bool showEmailInProfile = false;
  late String _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = widget.userName;
    _loadPreferences();
  }

  Future<void> _showEditProfileDialog() async {
    final controller = TextEditingController(text: _displayName);

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => Dialog(
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
                            color: _accentSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.edit_outlined,
                            color: _accent,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Edit Profile Name',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
                        controller: controller,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          labelStyle: TextStyle(color: _textSecondary),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: _accent,
                            size: 18,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 13,
                            horizontal: 4,
                          ),
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
                            onTap: () => Navigator.of(dialogContext).pop(),
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: _border),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w600,
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
                              final updatedName = controller.text.trim();
                              if (updatedName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Name cannot be empty.'),
                                  ),
                                );
                                return;
                              }

                              try {
                                final user = await GamificationService.loadUser();
                                user.name = updatedName;
                                await GamificationService.saveUser(user);

                                final authUser =
                                    firebase_auth.FirebaseAuth.instance.currentUser;
                                if (authUser != null) {
                                  await authUser.updateDisplayName(updatedName);
                                }

                                if (!mounted) return;
                                setState(() {
                                  _displayName = updatedName;
                                });

                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Profile updated successfully.'),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to update profile: $e'),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
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
                              child: const Text(
                                'Save',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
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

  Future<void> _loadPreferences() async {
    try {
      final preferences = await SettingsService.loadPreferences();
      if (!mounted) return;

      setState(() {
        routeApprovalUpdates =
            preferences['routeApprovalUpdates'] as bool? ?? false;
        newDiscussions = preferences['newDiscussions'] as bool? ?? false;
        weeklyDigest = preferences['weeklyDigest'] as bool? ?? false;
        distanceUnit = preferences['distanceUnit'] as String? ?? 'Miles';
        showEmailInProfile = preferences['showEmailInProfile'] as bool? ?? false;
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
      'weeklyDigest': weeklyDigest,
      'distanceUnit': distanceUnit,
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

  // ─── Color tokens 
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
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
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: _textSecondary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c,
                  ),
                ),
                const Spacer(),
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
          title: const Text(
            'Settings',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
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
            child: const Icon(
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
            const Text(
              'Settings',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
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
            const Text(
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
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _displayName.isNotEmpty
                                ? _displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.userEmail,
                              style: const TextStyle(
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
                              fontWeight: FontWeight.w700,
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
                  subtitle: 'Be notified on your posts in community discussions',
                  value: newDiscussions,
                  onChanged:
                      (val) => _updateBooleanPreference(
                        updater: (value) => newDiscussions = value,
                        value: val,
                      ),
                ),
                _toggleRow(
                  title: 'Weekly Digest',
                  subtitle: 'Summary of community activity',
                  value: weeklyDigest,
                  onChanged:
                      (val) => _updateBooleanPreference(
                        updater: (value) => weeklyDigest = value,
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
                    if (val != null) setState(() => language = val);
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
                  isLast: true,
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
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Saving settings...',
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ),
              ),

            // ─── About 
            _section(
              title: 'About',
              icon: Icons.info_outline_rounded,
              children: [
                _infoRow(label: 'Version', value: '0.1.16'),
                _infoRow(label: 'Last Updated', value: 'April 2026'),
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
                  label: 'Contact Support',
                  icon: Icons.support_agent_outlined,
                  onTap: () {
                    // TODO: Open Contact Support
                  },
                ),
                _actionRow(
                  label: 'Post Feedback',
                  icon: Icons.rate_review_outlined,
                  onTap: () => _showFeedbackDialog(context),
                  isLast: true,
                  color: const Color(0xFF9B7FE8),
                ),
              ],
            ),
            const SizedBox(height: 32),
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
                        const Text(
                          'Post Feedback',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
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
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w600,
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
                                    Color(0xFF4A7CE0),
                                    Color(0xFF6A9EFF),
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
                              child: const Text(
                                'Submit Feedback',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
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
