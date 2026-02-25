import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'settings_screen.dart';
import 'contribute_screen.dart';
import '../services/gamification_service.dart';
import '../services/route_service.dart';
import '../services/route_metrics_service.dart';
import '../models/user.dart' as gamification_user;
import '../models/achievement.dart';
import '../models/badge.dart' as badge_model;
import '../models/route.dart' as route_model;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  gamification_user.User? user;
  final List<Contribution> contributions = const [];

  final TextEditingController _editNameController = TextEditingController();
  bool _isLoggingOut = false;

  // ─── Color tokens ────────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);
  static const _green = Color(0xFF3EC97A);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    user = await GamificationService.loadUser();
    setState(() {});
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
      builder: (context) {
        return Dialog(
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
                      controller: _editNameController,
                      style: const TextStyle(color: _textPrimary, fontSize: 14),
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
                            if (user != null) {
                              user!.name =
                                  _editNameController.text.trim().isEmpty
                                      ? 'N/A'
                                      : _editNameController.text.trim();
                              await GamificationService.saveUser(user!);
                              setState(() {});
                            }
                            Navigator.of(context).pop();
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
        );
      },
    );
  }

  void _logout() async {
    if (_isLoggingOut) return; // Prevent multiple calls

    setState(() => _isLoggingOut = true);

    try {
      await firebase_auth.FirebaseAuth.instance.signOut();
      // AuthGate will handle navigation to login
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }
  }

  // ─── Rarity color ─────────────────────────────────────────────────────────
  Color _getRarityColor(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'common':
        return _textSecondary;
      case 'rare':
        return _accent;
      case 'epic':
        return const Color(0xFF9B7FE8);
      case 'legendary':
        return const Color(0xFFE89A3C);
      default:
        return _textSecondary;
    }
  }

  int _getAchievementProgress(Achievement achievement) {
    return achievement.progress;
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
        ),
      );
    }

    final initials = user!.name.isNotEmpty ? user!.name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: _bg,
      // ─── AppBar ────────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
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
                Icons.person_outline_rounded,
                color: _accent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Profile',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => SettingsScreen(
                        userName: user!.name,
                        userEmail: user!.email,
                      ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: const Icon(
                Icons.settings_outlined,
                color: _textSecondary,
                size: 18,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),

      body: Column(
        children: [
          // ─── Profile header card ──────────────────────────────────────────
          Container(
            color: _surface,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              children: [
                // Avatar + edit
                Stack(
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
                            color: _accent.withOpacity(0.35),
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
                        onTap: _showEditNameDialog,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: _border, width: 2),
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 13,
                            color: _accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Name
                Text(
                  user!.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                    letterSpacing: -0.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  user!.email,
                  style: const TextStyle(fontSize: 13, color: _textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),

                // Category + streak pills
                if ((user!.userCategory != null &&
                        user!.userCategory!.isNotEmpty) ||
                    user!.mostActiveRegion != null ||
                    user!.streakDays > 0) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (user!.userCategory != null &&
                          user!.userCategory!.isNotEmpty)
                        _pill(
                          label: user!.userCategory!,
                          icon: Icons.category_outlined,
                          color: _accent,
                        ),
                      if (user!.mostActiveRegion != null)
                        _pill(
                          label: 'Active: ${user!.mostActiveRegion}',
                          icon: Icons.location_on_outlined,
                          color: _green,
                        ),
                      if (user!.streakDays > 0)
                        _pill(
                          label: '🔥 ${user!.streakDays} day streak',
                          color: const Color(0xFFE89A3C),
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // ─── Stats row ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      _statItem(
                        value: '${user!.routesContributed}',
                        label: 'Contributed',
                        icon: Icons.alt_route,
                        color: _accent,
                      ),
                      _divider(),
                      _statItem(
                        value: '${user!.totalDistance.toStringAsFixed(1)} km',
                        label: 'Distance',
                        icon: Icons.straighten,
                        color: _green,
                      ),
                      _divider(),
                      _statItem(
                        value: '${user!.co2Saved.toStringAsFixed(1)} kg',
                        label: 'CO₂ Saved',
                        icon: Icons.eco_outlined,
                        color: const Color(0xFF3EC9D6),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Logout button ──────────────────────────────────────────
                GestureDetector(
                  onTap: _isLoggingOut ? null : _logout,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _danger.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _danger.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isLoggingOut)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: _danger,
                              strokeWidth: 2,
                            ),
                          )
                        else
                          const Icon(
                            Icons.logout_rounded,
                            color: _danger,
                            size: 17,
                          ),
                        const SizedBox(width: 8),
                        Text(
                          _isLoggingOut ? 'Logging out...' : 'Log Out',
                          style: const TextStyle(
                            color: _danger,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── Tab section ───────────────────────────────────────────────────
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  Container(
                    color: _surface,
                    child: TabBar(
                      labelColor: _accent,
                      unselectedLabelColor: _textSecondary,
                      indicatorColor: _accent,
                      indicatorWeight: 2.5,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      tabs: const [
                        Tab(text: 'Achievements'),
                        Tab(text: 'Badges'),
                        Tab(text: 'Contributions'),
                      ],
                    ),
                  ),
                  Container(height: 1, color: _border),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildAchievementsTab(),
                        _buildBadgesTab(),
                        _buildContributionsTab(),
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

  // ─── Pill helper ────────────────────────────────────────────────────────────
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

  // ─── Stat item helper ────────────────────────────────────────────────────────
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
              color: _textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 48, color: _border);
  }

  // ─── Achievements tab ────────────────────────────────────────────────────────
  Widget _buildAchievementsTab() {
    return FutureBuilder<List<Achievement>>(
      future: GamificationService.loadAchievements(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
          );
        }
        final achievements = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: achievements.length,
          itemBuilder: (context, index) {
            final achievement = achievements[index];
            final isUnlocked = user!.achievements.contains(achievement.id);
            final progress = _getAchievementProgress(achievement);
            final rarityColor = _getRarityColor(achievement.rarity);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUnlocked ? _green.withOpacity(0.3) : _border,
                  width: isUnlocked ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color:
                                isUnlocked
                                    ? _green.withOpacity(0.1)
                                    : _surfaceAlt,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color:
                                  isUnlocked
                                      ? _green.withOpacity(0.3)
                                      : _border,
                            ),
                          ),
                          child: Center(
                            child: Opacity(
                              opacity: isUnlocked ? 1.0 : 0.35,
                              child: Text(
                                achievement.icon,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    achievement.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color:
                                          isUnlocked
                                              ? _textPrimary
                                              : _textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: rarityColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      achievement.rarity,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: rarityColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                achievement.description,
                                style: const TextStyle(
                                  color: _textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color:
                                isUnlocked
                                    ? _green.withOpacity(0.1)
                                    : _surfaceAlt,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isUnlocked
                                ? Icons.check_circle_rounded
                                : Icons.lock_outline_rounded,
                            color: isUnlocked ? _green : _textSecondary,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                    if (achievement.maxProgress > 1) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress / achievement.maxProgress,
                          backgroundColor: _surfaceAlt,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isUnlocked ? _green : rarityColor,
                          ),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$progress / ${achievement.maxProgress}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isUnlocked ? _green : _textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Badges tab ───────────────────────────────────────────────────────────────
  Widget _buildBadgesTab() {
    return FutureBuilder<List<badge_model.Badge>>(
      future: GamificationService.loadBadges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
          );
        }
        final badges = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: badges.length,
          itemBuilder: (context, index) {
            final badge = badges[index];
            final isUnlocked = badge.isUnlocked;
            final earnedDate = badge.earnedAt?.toDate();
            final formattedDate =
                earnedDate != null
                    ? '${earnedDate.month}/${earnedDate.day}/${earnedDate.year}'
                    : null;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUnlocked ? _accent.withOpacity(0.3) : _border,
                  width: isUnlocked ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isUnlocked ? _accentSoft : _surfaceAlt,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color:
                              isUnlocked ? _accent.withOpacity(0.25) : _border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          badge.icon,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            badge.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isUnlocked ? _textPrimary : _textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            badge.description,
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (isUnlocked && formattedDate != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 11,
                                  color: _accent,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Earned $formattedDate',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isUnlocked ? _accentSoft : _surfaceAlt,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isUnlocked
                            ? Icons.verified_rounded
                            : Icons.lock_outline_rounded,
                        color: isUnlocked ? _accent : _textSecondary,
                        size: 15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Contributions tab ────────────────────────────────────────────────────────
  Widget _buildContributionsTab() {
    return FutureBuilder<List<route_model.Route>>(
      future: RouteService.getRoutesByUser(user!.email),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 32,
                    color: _danger,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Error loading contributions',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  '${snapshot.error}',
                  style: const TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ],
            ),
          );
        }

        final routes = snapshot.data ?? [];

        if (routes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.alt_route,
                    size: 36,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No contributions yet',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Start contributing routes to the community!',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: routes.length,
          itemBuilder: (context, index) {
            final route = routes[index];
            return RouteContributionCard(route: route, userEmail: user!.email);
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Supporting models & widgets
// ════════════════════════════════════════════════════════════════════

enum ContributionStatus { pending, approved, rejected }

class Contribution {
  final String title;
  final String description;
  final ContributionStatus status;

  const Contribution({
    required this.title,
    required this.description,
    required this.status,
  });
}

class RouteContributionCard extends StatelessWidget {
  final route_model.Route route;
  final String userEmail;

  // ─── Color tokens (duplicated for StatelessWidget access) ─────────────────
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  const RouteContributionCard({
    super.key,
    required this.route,
    required this.userEmail,
  });

  double _calculateAverageRating() {
    final total = route.upvotes + route.downvotes;
    if (total == 0) return 0.0;
    return (route.upvotes - route.downvotes) / (total + 1);
  }

  @override
  Widget build(BuildContext context) {
    final distance = RouteMetricsService.calculateRouteDistance(
      route.pathPoints,
    );
    final avgRating = _calculateAverageRating();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ──────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.alt_route, color: _accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.shortDescription,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.radio_button_checked,
                            size: 11,
                            color: _accent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              route.startLocation,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 11,
                            color: _accent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              route.endLocation,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => ContributeScreen(
                              onRouteSubmitted: (updatedRoute) async {
                                try {
                                  await RouteService.updateRoute(updatedRoute);
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Route updated!'),
                                    ),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed to update route: $e',
                                      ),
                                    ),
                                  );
                                }
                              },
                              routeToEdit: route,
                              contributorId: userEmail,
                            ),
                      ),
                    );
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: _border),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            Divider(color: _border, height: 1),
            const SizedBox(height: 12),

            // ─── Metrics grid ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  _metricCell('👥', '${route.views}', 'Views'),
                  _vDivider(),
                  _metricCell('⭐', avgRating.toStringAsFixed(1), 'Rating'),
                  _vDivider(),
                  _metricCell('👍', '${route.upvotes}', 'Upvotes'),
                  _vDivider(),
                  _metricCell('👎', '${route.downvotes}', 'Downvotes'),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ─── Distance + ETA pills ────────────────────────────────
            Row(
              children: [
                _infoPill(
                  icon: Icons.straighten,
                  label: '${distance.toStringAsFixed(1)} km',
                ),
                const SizedBox(width: 8),
                _infoPill(
                  icon: Icons.schedule_outlined,
                  label: route.eta ?? 'N/A',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCell(String emoji, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(width: 1, height: 36, color: _border);
  }

  Widget _infoPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: _textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ContributionCard extends StatelessWidget {
  final Contribution contribution;

  const ContributionCard({super.key, required this.contribution});

  static const _surface = Color(0xFFFFFFFF);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  Color _statusColor() {
    switch (contribution.status) {
      case ContributionStatus.pending:
        return const Color(0xFFE89A3C);
      case ContributionStatus.approved:
        return const Color(0xFF3EC97A);
      case ContributionStatus.rejected:
        return const Color(0xFFE05C6A);
    }
  }

  String _statusText() {
    switch (contribution.status) {
      case ContributionStatus.pending:
        return 'Pending';
      case ContributionStatus.approved:
        return 'Approved';
      case ContributionStatus.rejected:
        return 'Rejected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contribution.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    contribution.description,
                    style: const TextStyle(fontSize: 13, color: _textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                _statusText(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
