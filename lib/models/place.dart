import 'package:flutter/material.dart';

/// Categories used by the CAMANAVA "Nearby Places" map filters.
/// [tourist] holds the leisure/sightseeing spots — heritage sites, churches,
/// markets and attractions.
enum PlaceCategory { tourist, school, hospital, mall, park }

extension PlaceCategoryX on PlaceCategory {
  String get label {
    switch (this) {
      case PlaceCategory.tourist:
        return 'Attractions';
      case PlaceCategory.school:
        return 'Schools';
      case PlaceCategory.hospital:
        return 'Hospitals';
      case PlaceCategory.mall:
        return 'Malls';
      case PlaceCategory.park:
        return 'Parks';
    }
  }

  String get singularLabel {
    switch (this) {
      case PlaceCategory.tourist:
        return 'Attraction';
      case PlaceCategory.school:
        return 'School';
      case PlaceCategory.hospital:
        return 'Hospital';
      case PlaceCategory.mall:
        return 'Mall';
      case PlaceCategory.park:
        return 'Park';
    }
  }

  IconData get icon {
    switch (this) {
      case PlaceCategory.tourist:
        return Icons.attractions;
      case PlaceCategory.school:
        return Icons.school;
      case PlaceCategory.hospital:
        return Icons.local_hospital;
      case PlaceCategory.mall:
        return Icons.local_mall;
      case PlaceCategory.park:
        return Icons.park;
    }
  }

  Color get color {
    switch (this) {
      case PlaceCategory.tourist:
        return const Color(0xFF9C27B0);
      case PlaceCategory.school:
        return const Color(0xFF2E7CF6);
      case PlaceCategory.hospital:
        return const Color(0xFFE05C6A);
      case PlaceCategory.mall:
        return const Color(0xFFF2992F);
      case PlaceCategory.park:
        return const Color(0xFF3DBE6B);
    }
  }
}

/// A point of interest inside CAMANAVA used by the "Nearby Places" module.
///
/// A place can belong to several categories (e.g. Malabon Zoo is both an
/// attraction and a park), so [categories] is a list.
class Place {
  final String id;
  final String name;
  final String city;
  final List<PlaceCategory> categories;
  final double lat;
  final double lng;
  final String description;
  final String? address;

  const Place({
    required this.id,
    required this.name,
    required this.city,
    required this.categories,
    required this.lat,
    required this.lng,
    required this.description,
    this.address,
  });

  bool get isGalaan => categories.contains(PlaceCategory.tourist);
}