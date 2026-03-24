import 'package:cloud_firestore/cloud_firestore.dart';

class Badge {
  final String id;
  final String name;
  final String description;
  final String icon;
  final bool isUnlocked;
  final Timestamp? earnedAt;

  Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.isUnlocked = false,
    this.earnedAt,
  });

  Badge copyWith({bool? isUnlocked, Timestamp? earnedAt}) {
    return Badge(
      id: id,
      name: name,
      description: description,
      icon: icon,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      earnedAt: earnedAt ?? this.earnedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'isUnlocked': isUnlocked,
      'earnedAt': earnedAt,
    };
  }

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      icon: json['icon'],
      isUnlocked: json['isUnlocked'] ?? false,
      earnedAt: json['earnedAt'] as Timestamp?,
    );
  }
}

//badges
List<Badge> getPredefinedBadges() {
  return [
    Badge(
      id: 'contributor',
      name: 'Contributor',
      description: 'Added 10 routes',
      icon: '⭐',
    ),
    Badge(
      id: 'explorer',
      name: 'Explorer',
      description: 'Searched 50 unique places',
      icon: '🔍',
    ),
    Badge(
      id: 'veteran_commuter',
      name: 'Veteran Commuter',
      description: 'Used TransitPH for 6 months+',
      icon: '🏃',
    ),
    Badge(
      id: 'community_mentor',
      name: 'Community Mentor',
      description: 'Highly rated route contributions',
      icon: '🧠',
    ),
  ];
}
