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
        return AlertDialog(
          title: const Text('Edit Profile Name'),
          content: TextField(
            controller: _editNameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
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
              child: const Text('Save'),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
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
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              child: Text(
                user!.name.isNotEmpty ? user!.name[0] : '',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    user!.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _showEditNameDialog,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              user!.email,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (user!.userCategory != null &&
                user!.userCategory!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  user!.userCategory!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(
                      '${user!.routesContributed}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('Contributed'),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '${user!.totalDistance.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('Distance'),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '${user!.co2Saved.toStringAsFixed(1)} kg',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('CO₂ Saved'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (user!.mostActiveRegion != null || user!.streakDays > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (user!.mostActiveRegion != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        'Most Active: ${user!.mostActiveRegion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (user!.streakDays > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        '🔥 ${user!.streakDays} day streak',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoggingOut ? null : _logout,
              icon:
                  _isLoggingOut
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                      : const Icon(Icons.logout, color: Colors.white),
              label: Text(
                _isLoggingOut ? 'Logging out...' : 'Logout',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, // button color
                foregroundColor: Colors.white, // splash/hover color
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Achievements'),
                        Tab(text: 'Badges'),
                        Tab(text: 'Contributions'),
                      ],
                    ),
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
      ),
    );
  }

  Widget _buildAchievementsTab() {
    return FutureBuilder<List<Achievement>>(
      future: GamificationService.loadAchievements(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final achievements = snapshot.data!;
        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: achievements.length,
                itemBuilder: (context, index) {
                  final achievement = achievements[index];
                  final isUnlocked = user!.achievements.contains(
                    achievement.id,
                  );
                  final progress = _getAchievementProgress(achievement);

                  return Card(
                    color:
                        isUnlocked
                            ? Colors.green.shade50
                            : Colors.grey.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                achievement.icon,
                                style: const TextStyle(fontSize: 30),
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
                                            fontWeight: FontWeight.bold,
                                            color:
                                                isUnlocked
                                                    ? Colors.green
                                                    : Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getRarityColor(
                                              achievement.rarity,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            achievement.rarity,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      achievement.description,
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isUnlocked)
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              else
                                const Icon(Icons.lock, color: Colors.grey),
                            ],
                          ),
                          if (achievement.maxProgress > 1) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: progress / achievement.maxProgress,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isUnlocked
                                    ? Colors.green
                                    : _getRarityColor(achievement.rarity),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$progress / ${achievement.maxProgress}',
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    isUnlocked
                                        ? Colors.green
                                        : Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  int _getAchievementProgress(Achievement achievement) {
    return achievement.progress;
  }

  Color _getRarityColor(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'common':
        return Colors.grey;
      case 'rare':
        return Colors.blue;
      case 'epic':
        return Colors.purple;
      case 'legendary':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildBadgesTab() {
    return FutureBuilder<List<badge_model.Badge>>(
      future: GamificationService.loadBadges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final badges = snapshot.data!;
        return ListView.builder(
          itemCount: badges.length,
          itemBuilder: (context, index) {
            final badge = badges[index];
            final isUnlocked = badge.isUnlocked;
            final earnedDate = badge.earnedAt?.toDate();
            final formattedDate =
                earnedDate != null
                    ? '${earnedDate.month}/${earnedDate.day}/${earnedDate.year}'
                    : null;
            return Card(
              color: isUnlocked ? Colors.blue.shade50 : Colors.grey.shade100,
              child: ListTile(
                leading: Text(badge.icon, style: const TextStyle(fontSize: 30)),
                title: Text(
                  badge.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isUnlocked ? Colors.blue : Colors.grey,
                  ),
                ),
                subtitle: Text(
                  isUnlocked && formattedDate != null
                      ? '${badge.description}\nEarned on $formattedDate'
                      : badge.description,
                ),
                trailing:
                    isUnlocked
                        ? const Icon(Icons.verified, color: Colors.blue)
                        : const Icon(Icons.lock, color: Colors.grey),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContributionsTab() {
    return FutureBuilder<List<route_model.Route>>(
      future: RouteService.getRoutesByUser(
        user!.email,
      ), // Using email as userId for now
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading contributions: ${snapshot.error}'),
          );
        }

        final routes = snapshot.data ?? [];

        if (routes.isEmpty) {
          return const Center(
            child: Text('No contributions yet. Start contributing routes!'),
          );
        }

        return ListView.builder(
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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.shortDescription,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${route.startLocation} → ${route.endLocation}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
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
                  tooltip: 'Edit Route',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric('👥 ${route.views}', 'People Used'),
                _buildMetric('⭐ ${avgRating.toStringAsFixed(1)}', 'Avg Rating'),
                _buildMetric('👍 ${route.upvotes}', 'Upvotes'),
                _buildMetric('👎 ${route.downvotes}', 'Downvotes'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildMetric('${distance.toStringAsFixed(1)} km', 'Distance'),
                const SizedBox(width: 16),
                _buildMetric(route.eta ?? 'N/A', 'ETA'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

class ContributionCard extends StatelessWidget {
  final Contribution contribution;

  const ContributionCard({super.key, required this.contribution});

  Color _statusColor() {
    switch (contribution.status) {
      case ContributionStatus.pending:
        return Colors.amber.shade300;
      case ContributionStatus.approved:
        return Colors.green.shade300;
      case ContributionStatus.rejected:
        return Colors.red.shade300;
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(
          contribution.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(contribution.description),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _statusText(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
