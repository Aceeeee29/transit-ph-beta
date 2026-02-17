enum UserRole { user, moderator }

class User {
  String name;
  String email;
  String? userCategory;
  List<String> badges;
  List<String> achievements;
  int routesContributed;
  int routesSearched;
  int reportsSubmitted;
  double totalDistance;
  double co2Saved;
  String? mostActiveRegion;
  int streakDays;
  UserRole role;
  bool isBanned;
  List<String> bookmarkedPostIds;
  List<String> followedRouteIds;

  User({
    required this.name,
    required this.email,
    this.userCategory,
    this.badges = const [],
    this.achievements = const [],
    this.routesContributed = 0,
    this.routesSearched = 0,
    this.reportsSubmitted = 0,
    this.totalDistance = 0.0,
    this.co2Saved = 0.0,
    this.mostActiveRegion,
    this.streakDays = 0,
    this.role = UserRole.user,
    this.isBanned = false,
    this.bookmarkedPostIds = const [],
    this.followedRouteIds = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'userCategory': userCategory,
      'badges': badges,
      'achievements': achievements,
      'routesContributed': routesContributed,
      'routesSearched': routesSearched,
      'reportsSubmitted': reportsSubmitted,
      'totalDistance': totalDistance,
      'co2Saved': co2Saved,
      'mostActiveRegion': mostActiveRegion,
      'streakDays': streakDays,
      'role': role.name,
      'isBanned': isBanned,
      'bookmarkedPostIds': bookmarkedPostIds,
      'followedRouteIds': followedRouteIds,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      name: json['name'] ?? 'N/A',
      email: json['email'] ?? 'N/A',
      userCategory: json['userCategory'],
      badges: List<String>.from(json['badges'] ?? []),
      achievements: List<String>.from(json['achievements'] ?? []),
      routesContributed: json['routesContributed'] ?? 0,
      routesSearched: json['routesSearched'] ?? 0,
      reportsSubmitted: json['reportsSubmitted'] ?? 0,
      totalDistance: (json['totalDistance'] as num?)?.toDouble() ?? 0.0,
      co2Saved: (json['co2Saved'] as num?)?.toDouble() ?? 0.0,
      mostActiveRegion: json['mostActiveRegion'],
      streakDays: json['streakDays'] ?? 0,
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.user,
      ),
      isBanned: json['isBanned'] ?? false,
      bookmarkedPostIds: List<String>.from(json['bookmarkedPostIds'] ?? []),
      followedRouteIds: List<String>.from(json['followedRouteIds'] ?? []),
    );
  }
}
