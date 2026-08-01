enum PlaceCategory {
  school,
  hospital,
  mall,
  publicPark;

  String get label {
    switch (this) {
      case PlaceCategory.school:
        return 'Schools';
      case PlaceCategory.hospital:
        return 'Hospitals';
      case PlaceCategory.mall:
        return 'Malls';
      case PlaceCategory.publicPark:
        return 'Public Parks';
    }
  }

  String get iconLabel {
    switch (this) {
      case PlaceCategory.school:
        return 'School';
      case PlaceCategory.hospital:
        return 'Hospital';
      case PlaceCategory.mall:
        return 'Mall';
      case PlaceCategory.publicPark:
        return 'Park';
    }
  }
}

class Place {
  final String name;
  final double latitude;
  final double longitude;
  final PlaceCategory category;
  final String address;
  double? distanceKm;

  Place({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.address,
    this.distanceKm,
  });

  Place copyWith({double? distanceKm}) => Place(
        name: name,
        latitude: latitude,
        longitude: longitude,
        category: category,
        address: address,
        distanceKm: distanceKm ?? this.distanceKm,
      );
}
