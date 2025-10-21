class Achievement {
  final String id;
  final String name;
  final String description;
  final int pointsReward;
  final String icon;
  final bool isUnlocked;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.pointsReward,
    required this.icon,
    this.isUnlocked = false,
  });

  Achievement copyWith({bool? isUnlocked}) {
    return Achievement(
      id: id,
      name: name,
      description: description,
      pointsReward: pointsReward,
      icon: icon,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'pointsReward': pointsReward,
      'icon': icon,
      'isUnlocked': isUnlocked,
    };
  }

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      pointsReward: json['pointsReward'],
      icon: json['icon'],
      isUnlocked: json['isUnlocked'] ?? false,
    );
  }
}

// Predefined achievements
List<Achievement> predefinedAchievements = [
  Achievement(
    id: 'rookie_commuter',
    name: 'Rookie Commuter',
    description: 'First route searched',
    pointsReward: 100,
    icon: '🚏',
  ),
  Achievement(
    id: 'route_pioneer',
    name: 'Route Pioneer',
    description: 'Added 10+ routes',
    pointsReward: 500,
    icon: '🧭',
  ),
  Achievement(
    id: 'daily_rider',
    name: 'Daily Rider',
    description: 'Used the app 7 days in a row',
    pointsReward: 300,
    icon: '🔥',
  ),
  Achievement(
    id: 'community_hero',
    name: 'Community Hero',
    description: '50 route contributions',
    pointsReward: 1000,
    icon: '🛠️',
  ),
  Achievement(
    id: 'metro_master',
    name: 'Metro Master',
    description: 'Searched 100 unique routes',
    pointsReward: 750,
    icon: '🏙️',
  ),
];
