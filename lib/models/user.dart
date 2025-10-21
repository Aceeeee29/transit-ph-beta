class User {
  String name;
  String email;
  int points;
  int level;
  List<String> badges;
  List<String> achievements;
  int routesContributed;
  int routesSearched;
  int reportsSubmitted;

  User({
    required this.name,
    required this.email,
    this.points = 0,
    this.level = 1,
    this.badges = const [],
    this.achievements = const [],
    this.routesContributed = 0,
    this.routesSearched = 0,
    this.reportsSubmitted = 0,
  });

  int get nextLevelPoints => level * 100; // Example: 100 points per level

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'points': points,
      'level': level,
      'badges': badges,
      'achievements': achievements,
      'routesContributed': routesContributed,
      'routesSearched': routesSearched,
      'reportsSubmitted': reportsSubmitted,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      name: json['name'] ?? 'N/A',
      email: json['email'] ?? 'N/A',
      points: json['points'] ?? 0,
      level: json['level'] ?? 1,
      badges: List<String>.from(json['badges'] ?? []),
      achievements: List<String>.from(json['achievements'] ?? []),
      routesContributed: json['routesContributed'] ?? 0,
      routesSearched: json['routesSearched'] ?? 0,
      reportsSubmitted: json['reportsSubmitted'] ?? 0,
    );
  }
}
