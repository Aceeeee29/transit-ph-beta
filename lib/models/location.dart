class Location {
  final String id;
  final String name;
  final String type; // 'route' or 'stop'

  Location({required this.id, required this.name, required this.type});

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'type': type};
  }

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(id: json['id'], name: json['name'], type: json['type']);
  }
}
