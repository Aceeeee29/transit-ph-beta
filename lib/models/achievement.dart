class Achievement {
  final String id;
  final String name;
  final String description;
  final int pointsReward;
  final String icon;
  final bool isUnlocked;
  final int progress;
  final int maxProgress;
  final String rarity;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.pointsReward,
    required this.icon,
    this.isUnlocked = false,
    this.progress = 0,
    this.maxProgress = 1,
    this.rarity = 'Common',
  });

  Achievement copyWith({bool? isUnlocked, int? progress}) {
    return Achievement(
      id: id,
      name: name,
      description: description,
      pointsReward: pointsReward,
      icon: icon,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      progress: progress ?? this.progress,
      maxProgress: maxProgress,
      rarity: rarity,
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
      'progress': progress,
      'maxProgress': maxProgress,
      'rarity': rarity,
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
      progress: json['progress'] ?? 0,
      maxProgress: json['maxProgress'] ?? 1,
      rarity: json['rarity'] ?? 'Common',
    );
  }
}

// Predefined achievements
List<Achievement> getPredefinedAchievements() {
  return [
    Achievement(
      id: 'rookie_commuter',
      name: 'Rookie Commuter',
      description: 'First route searched',
      pointsReward: 100,
      icon: '🚏',
      maxProgress: 1,
      rarity: 'Common',
    ),
    Achievement(
      id: 'route_pioneer',
      name: 'Route Pioneer',
      description: 'Added 10+ routes',
      pointsReward: 500,
      icon: '🧭',
      maxProgress: 10,
      rarity: 'Rare',
    ),
    Achievement(
      id: 'daily_rider',
      name: 'Daily Rider',
      description: 'Used the app 7 days in a row',
      pointsReward: 300,
      icon: '🔥',
      maxProgress: 7,
      rarity: 'Epic',
    ),
    Achievement(
      id: 'community_hero',
      name: 'Community Hero',
      description: '50 route contributions',
      pointsReward: 1000,
      icon: '🛠️',
      maxProgress: 50,
      rarity: 'Legendary',
    ),
    Achievement(
      id: 'metro_master',
      name: 'Metro Master',
      description: 'Searched 100 unique routes',
      pointsReward: 750,
      icon: '🏙️',
      maxProgress: 100,
      rarity: 'Rare',
    ),
  ];
}
