import '../models/place_model.dart';
import 'distance_service.dart';

class PlacesService {
  static final List<Place> allPlaces = [
    // ── Schools ──────────────────────────────────────────────────────────────
    Place(
      name: 'Manila Central University',
      latitude: 14.6467,
      longitude: 120.9833,
      category: PlaceCategory.school,
      address: 'McArthur Highway, Caloocan City',
    ),
    Place(
      name: 'STI College Caloocan',
      latitude: 14.6533,
      longitude: 120.9722,
      category: PlaceCategory.school,
      address: '9th Ave., Grace Park East, Caloocan City',
    ),
    Place(
      name: 'Caloocan High School',
      latitude: 14.6494,
      longitude: 120.9747,
      category: PlaceCategory.school,
      address: '10th Ave., Grace Park East, Caloocan City',
    ),
    Place(
      name: 'University of Caloocan City',
      latitude: 14.6519,
      longitude: 120.9683,
      category: PlaceCategory.school,
      address: 'A. Mabini St., Grace Park East, Caloocan City',
    ),
    Place(
      name: 'La Consolacion College Caloocan',
      latitude: 14.6489,
      longitude: 120.9792,
      category: PlaceCategory.school,
      address: 'Samson Rd., Caloocan City',
    ),
    Place(
      name: 'Navotas National High School',
      latitude: 14.6639,
      longitude: 120.9467,
      category: PlaceCategory.school,
      address: 'M. Naval St., Navotas City',
    ),
    Place(
      name: 'Malabon National High School',
      latitude: 14.6683,
      longitude: 120.9567,
      category: PlaceCategory.school,
      address: 'Gov. Pascual Ave., Malabon City',
    ),
    Place(
      name: 'Valenzuela City School of Mathematics and Science',
      latitude: 14.7000,
      longitude: 120.9800,
      category: PlaceCategory.school,
      address: 'Maysan Rd., Valenzuela City',
    ),

    // ── Hospitals ────────────────────────────────────────────────────────────
    Place(
      name: 'Caloocan City Medical Center',
      latitude: 14.6467,
      longitude: 120.9833,
      category: PlaceCategory.hospital,
      address: 'McArthur Highway, Caloocan City',
    ),
    Place(
      name: 'Navotas City Hospital',
      latitude: 14.6650,
      longitude: 120.9450,
      category: PlaceCategory.hospital,
      address: 'Gov. Pascual Ave., Navotas City',
    ),
    Place(
      name: 'Malabon General Hospital',
      latitude: 14.6700,
      longitude: 120.9580,
      category: PlaceCategory.hospital,
      address: 'Gov. Pascual Ave., Malabon City',
    ),
    Place(
      name: 'Valenzuela Medical Center',
      latitude: 14.6950,
      longitude: 120.9750,
      category: PlaceCategory.hospital,
      address: 'McArthur Highway, Valenzuela City',
    ),
    Place(
      name: 'Dr. Jose N. Rodriguez Memorial Hospital',
      latitude: 14.6600,
      longitude: 120.9700,
      category: PlaceCategory.hospital,
      address: 'Gen. Malvar St., Caloocan City',
    ),
    Place(
      name: 'Tullahan Hospital',
      latitude: 14.6720,
      longitude: 120.9530,
      category: PlaceCategory.hospital,
      address: 'M. Naval St., Malabon City',
    ),

    // ── Malls ────────────────────────────────────────────────────────────────
    Place(
      name: 'SM Grand Central',
      latitude: 14.6533,
      longitude: 120.9800,
      category: PlaceCategory.mall,
      address: 'Rizal Ave. Ext., Caloocan City',
    ),
    Place(
      name: 'SM City Valenzuela',
      latitude: 14.7033,
      longitude: 120.9850,
      category: PlaceCategory.mall,
      address: 'McArthur Highway, Valenzuela City',
    ),
    Place(
      name: 'Robinsons Place Malabon',
      latitude: 14.6650,
      longitude: 120.9567,
      category: PlaceCategory.mall,
      address: 'Gov. Pascual Ave., Malabon City',
    ),
    Place(
      name: 'Puregold Malabon',
      latitude: 14.6689,
      longitude: 120.9522,
      category: PlaceCategory.mall,
      address: 'Gov. Pascual Ave., Malabon City',
    ),
    Place(
      name: 'Vista Mall Navotas',
      latitude: 14.6610,
      longitude: 120.9400,
      category: PlaceCategory.mall,
      address: 'M. Naval St., Navotas City',
    ),
    Place(
      name: 'Monetary Caloocan',
      latitude: 14.6550,
      longitude: 120.9750,
      category: PlaceCategory.mall,
      address: 'Rizal Ave. Ext., Caloocan City',
    ),

    // ── Public Parks ─────────────────────────────────────────────────────────
    Place(
      name: 'Caloocan Sports Complex',
      latitude: 14.6500,
      longitude: 120.9770,
      category: PlaceCategory.publicPark,
      address: '10th Ave., Grace Park East, Caloocan City',
    ),
    Place(
      name: 'Navotas City Park',
      latitude: 14.6611,
      longitude: 120.9422,
      category: PlaceCategory.publicPark,
      address: 'Gov. Pascual Ave., Navotas City',
    ),
    Place(
      name: 'Malabon People\'s Park',
      latitude: 14.6672,
      longitude: 120.9550,
      category: PlaceCategory.publicPark,
      address: 'F. Tayco St., Malabon City',
    ),
    Place(
      name: 'Valenzuela City People\'s Park',
      latitude: 14.6980,
      longitude: 120.9800,
      category: PlaceCategory.publicPark,
      address: 'McArthur Highway, Valenzuela City',
    ),
    Place(
      name: 'Tenejero River Park',
      latitude: 14.6700,
      longitude: 120.9500,
      category: PlaceCategory.publicPark,
      address: 'Tenejero, Malabon City',
    ),
  ];

  static List<Place> getByCategory(PlaceCategory category) {
    return allPlaces.where((p) => p.category == category).toList();
  }

  static List<Place> computeDistances(
    List<Place> places,
    double userLat,
    double userLng,
  ) {
    return places.map((p) {
      final dist = DistanceService.calculateKm(
        userLat,
        userLng,
        p.latitude,
        p.longitude,
      );
      return p.copyWith(distanceKm: dist);
    }).toList();
  }

  static List<Place> sortByDistance(List<Place> places) {
    final sorted = List<Place>.from(places)
      ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
    return sorted;
  }

  static List<Place> getByCategorySorted(
    PlaceCategory category,
    double userLat,
    double userLng,
  ) {
    final filtered = getByCategory(category);
    final withDistance = computeDistances(filtered, userLat, userLng);
    return sortByDistance(withDistance);
  }
}
