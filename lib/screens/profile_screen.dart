import 'package:flutter/material.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String userName = 'N/A';
  String userEmail = 'N/A';
  final List<Contribution> contributions = const [];

  final TextEditingController _editNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _editNameController.text = userName;
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
              onPressed: () {
                setState(() {
                  userName =
                      _editNameController.text.trim().isEmpty
                          ? 'N/A'
                          : _editNameController.text.trim();
                });
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
                        userName: userName,
                        userEmail: userEmail,
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
                userName.isNotEmpty ? userName[0] : '',
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
                  userName,
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
              userEmail,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Contributions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: contributions.length,
                      itemBuilder: (context, index) {
                        final contribution = contributions[index];
                        return ContributionCard(contribution: contribution);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
