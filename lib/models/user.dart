import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { user, moderator, admin }

DateTime? _parseDateTime(dynamic rawValue) {
  if (rawValue is Timestamp) return rawValue.toDate();
  if (rawValue is String) {
    try {
      return DateTime.parse(rawValue);
    } catch (_) {
      return null;
    }
  }
  return null;
}

UserRole _parseUserRole(dynamic rawRole) {
  final normalized = (rawRole as String? ?? 'user')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  switch (normalized) {
    case 'moderator':
      return UserRole.moderator;
    case 'admin':
    case 'superadmin':
    case 'super_admin':
      return UserRole.admin;
    case 'user':
    default:
      return UserRole.user;
  }
}

class User {
  String? uid;
  String name;
  String email;
  String? photoUrl;
  String? userCategory;
  List<String> userTags;
  List<String> badges;
  List<String> achievements;
  int routesContributed;
  int routesSearched;
  int reportsSubmitted;
  double totalDistance;
  double co2Saved;
  String? mostActiveRegion;
  int streakDays;
  DateTime? lastActiveDate;
  DateTime? createdAt;
  UserRole role;
  bool isBanned;
  DateTime? restrictedUntil;
  List<String> followedRouteIds;
  bool hasSeenTutorial;
  List<String> recentSearches;

  User({
    this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.userCategory,
    this.userTags = const [],
    this.badges = const [],
    this.achievements = const [],
    this.routesContributed = 0,
    this.routesSearched = 0,
    this.reportsSubmitted = 0,
    this.totalDistance = 0.0,
    this.co2Saved = 0.0,
    this.mostActiveRegion,
    this.streakDays = 0,
    this.lastActiveDate,
    this.createdAt,
    this.role = UserRole.user,
    this.isBanned = false,
    this.restrictedUntil,
    this.followedRouteIds = const [],
    this.hasSeenTutorial = false,
    this.recentSearches = const [],
  });

  bool get hasActiveRestriction {
    final until = restrictedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'userCategory': userCategory,
      'userTags': userTags,
      'badges': badges,
      'achievements': achievements,
      'routesContributed': routesContributed,
      'routesSearched': routesSearched,
      'reportsSubmitted': reportsSubmitted,
      'totalDistance': totalDistance,
      'co2Saved': co2Saved,
      'mostActiveRegion': mostActiveRegion,
      'streakDays': streakDays,
      'lastActiveDate': lastActiveDate?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'role': role.name,
      'isBanned': isBanned,
      'restrictedUntil': restrictedUntil?.toIso8601String(),
      'followedRouteIds': followedRouteIds,
      'hasSeenTutorial': hasSeenTutorial,
      'recentSearches': recentSearches,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] as String? ?? '').trim().toLowerCase();
    return User(
      uid: json['uid'],
      name: json['name'] ?? 'N/A',
      email: json['email'] ?? 'N/A',
      photoUrl: json['photoUrl'],
      userCategory: json['userCategory'],
      userTags: List<String>.from(json['userTags'] ?? const []),
      badges: List<String>.from(json['badges'] ?? []),
      achievements: List<String>.from(json['achievements'] ?? []),
      routesContributed: json['routesContributed'] ?? 0,
      routesSearched: json['routesSearched'] ?? 0,
      reportsSubmitted: json['reportsSubmitted'] ?? 0,
      totalDistance: (json['totalDistance'] as num?)?.toDouble() ?? 0.0,
      co2Saved: (json['co2Saved'] as num?)?.toDouble() ?? 0.0,
      mostActiveRegion: json['mostActiveRegion'],
      streakDays: json['streakDays'] ?? 0,
      lastActiveDate: _parseDateTime(json['lastActiveDate']),
      createdAt: _parseDateTime(json['createdAt']),
      role: _parseUserRole(json['role']),
      isBanned: (json['isBanned'] as bool? ?? false) || status == 'banned',
      restrictedUntil: _parseDateTime(json['restrictedUntil']),
      followedRouteIds: List<String>.from(json['followedRouteIds'] ?? []),
      hasSeenTutorial: json['hasSeenTutorial'] ?? false,
      recentSearches: List<String>.from(json['recentSearches'] ?? []),
    );
  }
}
