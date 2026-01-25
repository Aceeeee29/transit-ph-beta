enum UserRole { user, moderator }

class User {
  String name;
  String email;
  List<String> badges;
  List<String> achievements;
  int routesContributed;
  int routesSearched;
  int reportsSubmitted;
  UserRole role;
  bool isBanned;

  User({
    required this.name,
    required this.email,
    this.badges = const [],
    this.achievements = const [],
    this.routesContributed = 0,
    this.routesSearched = 0,
    this.reportsSubmitted = 0,
    this.role = UserRole.user,
    this.isBanned = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'badges': badges,
      'achievements': achievements,
      'routesContributed': routesContributed,
      'routesSearched': routesSearched,
      'reportsSubmitted': reportsSubmitted,
      'role': role.name,
      'isBanned': isBanned,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      name: json['name'] ?? 'N/A',
      email: json['email'] ?? 'N/A',
      badges: List<String>.from(json['badges'] ?? []),
      achievements: List<String>.from(json['achievements'] ?? []),
      routesContributed: json['routesContributed'] ?? 0,
      routesSearched: json['routesSearched'] ?? 0,
      reportsSubmitted: json['reportsSubmitted'] ?? 0,
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.user,
      ),
      isBanned: json['isBanned'] ?? false,
    );
  }
}
