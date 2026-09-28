import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'settings_screen.dart';
import '../services/gamification_service.dart';
import '../services/settings_service.dart';
import '../services/route_metrics_service.dart';
import '../models/user.dart' as gamification_user;
import '../widgets/profile/profile_colors.dart';
import '../widgets/profile/achievements_tab.dart';
import '../widgets/profile/badges_tab.dart';
import '../widgets/profile/contributions_tab.dart';
import '../widgets/translated_text.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  gamification_user.User? user;
  bool _showEmailInProfile = false;
  String _distanceUnit = 'Miles';

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadPreferences();
  }

  Future<void> _loadUser() async {
    final loadedUser = await GamificationService.loadUser();
    if (!mounted) return;
    setState(() {
      user = loadedUser;
    });
  }

  Future<void> _loadPreferences() async {
    final preferences = await SettingsService.loadPreferences();
    if (!mounted) return;
    setState(() {
      _showEmailInProfile = preferences['showEmailInProfile'] as bool? ?? false;
      _distanceUnit = preferences['distanceUnit'] as String? ?? 'Miles';
    });
  }

  @override
  void dispose() {
    super.dispose();
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
      body: DefaultTabController(
        length: 3,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: _ProfileHeaderCard(
                  user: user!,
                  initials: initials,
                  showEmailInProfile: _showEmailInProfile,
                  distanceDisplay: RouteMetricsService.formatDistanceForUnit(
                    user!.totalDistance,
                    distanceUnit: _distanceUnit,
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _ProfileTabBarDelegate(_buildTabBar()),
              ),
            ];
          },
          body: TabBarView(
            children: [
              AchievementsTab(userAchievements: user!.achievements),
              const BadgesTab(),
              ContributionsTab(
                userEmail: user!.email,
                distanceUnit: _distanceUnit,
              ),
            ],
          ),
        ),
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
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => SettingsScreen(
                      userName: user!.name,
                      userEmail: user!.email,
                      userPhotoUrl: user!.photoUrl,
                    ),
              ),
            );
            if (!mounted) return;
            await _loadUser();
            await _loadPreferences();
          },
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
      decoration: const BoxDecoration(
        color: ProfileColors.surface,
        border: Border(bottom: BorderSide(color: ProfileColors.border)),
      ),
      child: const TabBar(
        labelColor: ProfileColors.accent,
        unselectedLabelColor: ProfileColors.textSecondary,
        indicatorColor: ProfileColors.accent,
        indicatorWeight: 2.5,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        tabs: [
          Tab(child: TranslatedText('Achievements')),
          Tab(child: TranslatedText('Badges')),
          Tab(child: TranslatedText('Contributions')),
        ],
      ),
    );
  }
}

// ─── Pinned tab bar sliver delegate ──────────────────────────────────────────

class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget tabBar;

  _ProfileTabBarDelegate(this.tabBar);

  @override
  double get minExtent => kTextTabBarHeight + 1;

  @override
  double get maxExtent => kTextTabBarHeight + 1;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return tabBar;
  }

  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar;
  }
}

// ─── Profile header card ─────────────────────────────────────────────────────

class _ProfileHeaderCard extends StatelessWidget {
  final gamification_user.User user;
  final String initials;
  final bool showEmailInProfile;
  final String distanceDisplay;

  static const _green = Color(0xFF3EC97A);

  const _ProfileHeaderCard({
    required this.user,
    required this.initials,
    required this.showEmailInProfile,
    required this.distanceDisplay,
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
            showEmailInProfile ? user.email : 'Email hidden',
            style: const TextStyle(
              fontSize: 13,
              color: ProfileColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (_hasTagData()) ...[const SizedBox(height: 12), _pills()],
          const SizedBox(height: 20),
          _statsRow(),
        ],
      ),
    );
  }

  bool _hasTagData() =>
      user.userTags.isNotEmpty ||
      (user.userCategory?.isNotEmpty ?? false) ||
      user.mostActiveRegion != null ||
      user.streakDays > 0;

  Widget _avatar() {
    return Container(
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
      child: ClipOval(
        child:
            (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                ? CachedNetworkImage(
                  imageUrl: user.photoUrl!,
                  fit: BoxFit.cover,
                  width: 80,
                  height: 80,
                  errorWidget: (_, __, ___) => _initialsFallback(),
                )
                : _initialsFallback(),
      ),
    );
  }

  Widget _initialsFallback() {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _pills() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        ...user.userTags.map(
          (tag) => _pill(
            label: tag,
            icon: Icons.sell_outlined,
            color: ProfileColors.accent,
          ),
        ),
        if ((user.userCategory?.isNotEmpty ?? false) &&
            !user.userTags.contains(user.userCategory))
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
            value: distanceDisplay,
            label: 'Distance',
            icon: Icons.straighten,
            color: _green,
          ),
        ],
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
            style: const TextStyle(
              fontSize: 11,
              color: ProfileColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
