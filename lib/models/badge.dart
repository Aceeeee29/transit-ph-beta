class Badge {
  final String id;
  final String name;
  final String description;
  final String icon;
  final bool isUnlocked;

  Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.isUnlocked = false,
  });

  Badge copyWith({bool? isUnlocked}) {
    return Badge(
      id: id,
      name: name,
      description: description,
      icon: icon,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'isUnlocked': isUnlocked,
    };
  }

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      icon: json['icon'],
      isUnlocked: json['isUnlocked'] ?? false,
    );
  }
}

// Predefined badges
List<Badge> predefinedBadges = [
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
