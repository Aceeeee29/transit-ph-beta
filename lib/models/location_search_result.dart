/// Result picked from the location search UI — carries coordinates so the
/// caller can jump straight to the point without re-geocoding.
class LocationSearchResult {
  final String name;
  final double latitude;
  final double longitude;

  const LocationSearchResult({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}
