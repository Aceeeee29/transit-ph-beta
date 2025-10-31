import 'package:flutter/material.dart';
import 'settings_screen.dart';
import '../services/gamification_service.dart';
import '../models/user.dart';
import '../models/achievement.dart';
import '../models/badge.dart' as badge_model;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? user;
  final List<Contribution> contributions = const [];

  final TextEditingController _editNameController = TextEditingController();

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

  void _logout() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
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
                Text(
                  user!.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
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
            ),
            const SizedBox(height: 12),

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
                    const Text('Routes Contributed'),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '${user!.routesSearched}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('Routes Searched'),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '${user!.reportsSubmitted}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('Reports Submitted'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
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
        return ListView.builder(
          itemCount: achievements.length,
          itemBuilder: (context, index) {
            final achievement = achievements[index];
            final isUnlocked = user!.achievements.contains(achievement.id);
            return Card(
              color: isUnlocked ? Colors.green.shade50 : Colors.grey.shade100,
              child: ListTile(
                leading: Text(
                  achievement.icon,
                  style: const TextStyle(fontSize: 30),
                ),
                title: Text(
                  achievement.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isUnlocked ? Colors.green : Colors.grey,
                  ),
                ),
                subtitle: Text(achievement.description),
                trailing:
                    isUnlocked
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.lock, color: Colors.grey),
              ),
            );
          },
        );
      },
    );
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
            final isUnlocked = user!.badges.contains(badge.id);
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
                subtitle: Text(badge.description),
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
    return ListView.builder(
      itemCount: contributions.length,
      itemBuilder: (context, index) {
        final contribution = contributions[index];
        return ContributionCard(contribution: contribution);
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
