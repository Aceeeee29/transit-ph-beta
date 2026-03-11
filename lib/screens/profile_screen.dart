import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'settings_screen.dart';
import '../services/gamification_service.dart';
import '../models/user.dart' as gamification_user;
import '../widgets/profile/profile_colors.dart';
import '../widgets/profile/achievements_tab.dart';
import '../widgets/profile/badges_tab.dart';
import '../widgets/profile/contributions_tab.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  gamification_user.User? user;
  final _editNameController = TextEditingController();
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final loadedUser = await GamificationService.loadUser();
    if (!mounted) return;
    setState(() {
      user = loadedUser;
    });
    _editNameController.text = user?.name ?? 'N/A';
  }

  @override
  void dispose() {
    _editNameController.dispose();
    super.dispose();
  }

  void _showEditNameDialog() {
    showDialog(
      context: context,
      builder: (context) => _EditNameDialog(
        controller: _editNameController,
        user: user,
        onSaved: () => setState(() {}),
      ),
    );
  }

  void _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      await firebase_auth.FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        backgroundColor: ProfileColors.bg,
        body: Center(
          child: CircularProgressIndicator(
            color: ProfileColors.accent,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final initials = user!.name.isNotEmpty ? user!.name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: ProfileColors.bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _ProfileHeaderCard(
            user: user!,
            initials: initials,
            isLoggingOut: _isLoggingOut,
            onEditName: _showEditNameDialog,
            onLogout: _logout,
          ),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  _buildTabBar(),
                  Container(height: 1, color: ProfileColors.border),
                  Expanded(
                    child: TabBarView(
                      children: [
                        AchievementsTab(userAchievements: user!.achievements),
                        const BadgesTab(),
                        ContributionsTab(userEmail: user!.email),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: ProfileColors.surface,
      foregroundColor: ProfileColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: ProfileColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: ProfileColors.accent,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Profile',
            style: TextStyle(
              color: ProfileColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      actions: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsScreen(
                userName: user!.name,
                userEmail: user!.email,
              ),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ProfileColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ProfileColors.border),
            ),
            child: const Icon(
              Icons.settings_outlined,
              color: ProfileColors.textSecondary,
              size: 18,
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: ProfileColors.border),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: ProfileColors.surface,
      child: const TabBar(
        labelColor: ProfileColors.accent,
        unselectedLabelColor: ProfileColors.textSecondary,
        indicatorColor: ProfileColors.accent,
        indicatorWeight: 2.5,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: [
          Tab(text: 'Achievements'),
          Tab(text: 'Badges'),
          Tab(text: 'Contributions'),
        ],
      ),
    );
  }
}

// ─── Profile header card ─────────────────────────────────────────────────────

class _ProfileHeaderCard extends StatelessWidget {
  final gamification_user.User user;
  final String initials;
  final bool isLoggingOut;
  final VoidCallback onEditName;
  final VoidCallback onLogout;

  static const _green = Color(0xFF3EC97A);

  const _ProfileHeaderCard({
    required this.user,
    required this.initials,
    required this.isLoggingOut,
    required this.onEditName,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ProfileColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          _avatar(),
          const SizedBox(height: 14),
          Text(
            user.name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: ProfileColors.textPrimary,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            user.email,
            style: const TextStyle(fontSize: 13, color: ProfileColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
          if (_hasTagData()) ...[
            const SizedBox(height: 12),
            _pills(),
          ],
          const SizedBox(height: 20),
          _statsRow(),
          const SizedBox(height: 16),
          _logoutButton(),
        ],
      ),
    );
  }

  bool _hasTagData() =>
      (user.userCategory?.isNotEmpty ?? false) ||
      user.mostActiveRegion != null ||
      user.streakDays > 0;

  Widget _avatar() {
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: ProfileColors.accent.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: onEditName,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: ProfileColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: ProfileColors.border, width: 2),
              ),
              child: const Icon(Icons.edit, size: 13, color: ProfileColors.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pills() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (user.userCategory?.isNotEmpty ?? false)
          _pill(
            label: user.userCategory!,
            icon: Icons.category_outlined,
            color: ProfileColors.accent,
          ),
        if (user.mostActiveRegion != null)
          _pill(
            label: 'Active: ${user.mostActiveRegion}',
            icon: Icons.location_on_outlined,
            color: _green,
          ),
        if (user.streakDays > 0)
          _pill(
            label: '🔥 ${user.streakDays} day streak',
            color: const Color(0xFFE89A3C),
          ),
      ],
    );
  }

  Widget _statsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: ProfileColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ProfileColors.border),
      ),
      child: Row(
        children: [
          _statItem(
            value: '${user.routesContributed}',
            label: 'Contributed',
            icon: Icons.alt_route,
            color: ProfileColors.accent,
          ),
          Container(width: 1, height: 48, color: ProfileColors.border),
          _statItem(
            value: '${user.totalDistance.toStringAsFixed(1)} km',
            label: 'Distance',
            icon: Icons.straighten,
            color: _green,
          ),
          Container(width: 1, height: 48, color: ProfileColors.border),
          _statItem(
            value: '${user.co2Saved.toStringAsFixed(1)} kg',
            label: 'CO₂ Saved',
            icon: Icons.eco_outlined,
            color: const Color(0xFF3EC9D6),
          ),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return GestureDetector(
      onTap: isLoggingOut ? null : onLogout,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: ProfileColors.danger.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ProfileColors.danger.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoggingOut)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: ProfileColors.danger,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(Icons.logout_rounded, color: ProfileColors.danger, size: 17),
            const SizedBox(width: 8),
            Text(
              isLoggingOut ? 'Logging out...' : 'Log Out',
              style: const TextStyle(
                color: ProfileColors.danger,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill({required String label, IconData? icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: ProfileColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: ProfileColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Edit name dialog ─────────────────────────────────────────────────────────

class _EditNameDialog extends StatelessWidget {
  final TextEditingController controller;
  final gamification_user.User? user;
  final VoidCallback onSaved;

  const _EditNameDialog({
    required this.controller,
    required this.user,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: ProfileColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ProfileColors.border),
          boxShadow: [
            BoxShadow(
              color: ProfileColors.accent.withOpacity(0.08),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            _textField(),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      decoration: BoxDecoration(
        color: ProfileColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(bottom: BorderSide(color: ProfileColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: ProfileColors.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.edit_outlined,
              color: ProfileColors.accent,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Edit Profile Name',
            style: TextStyle(
              color: ProfileColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: ProfileColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ProfileColors.border),
        ),
        child: TextField(
          controller: controller,
          style: const TextStyle(color: ProfileColors.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: ProfileColors.textSecondary),
            prefixIcon: Icon(
              Icons.person_outline,
              color: ProfileColors.accent,
              size: 18,
            ),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 13, horizontal: 4),
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: ProfileColors.surface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: ProfileColors.border),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: ProfileColors.textSecondary,
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
                if (user != null) {
                  user!.name = controller.text.trim().isEmpty
                      ? 'N/A'
                      : controller.text.trim();
                  await GamificationService.saveUser(user!);
                  onSaved();
                }
                if (context.mounted) Navigator.of(context).pop();
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
                      color: ProfileColors.accent.withOpacity(0.3),
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
    );
  }
}
