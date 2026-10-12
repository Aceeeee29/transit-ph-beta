import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/camanava_places.dart';
import '../models/location_search_result.dart';
import '../models/place.dart';

/// Place suggestions for a typed query: our CAMANAVA landmarks first, then
/// OpenStreetMap (Nominatim) results in the Philippines.
class PlaceSearchService {
  PlaceSearchService._();

  static List<Place> localMatches(String query, {int limit = 4}) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return const [];
    return camanavaPlaces
        .where(
          (p) =>
              p.name.toLowerCase().contains(lower) ||
              p.city.toLowerCase().contains(lower) ||
              (p.address ?? '').toLowerCase().contains(lower),
        )
        .take(limit)
        .toList();
  }

  /// The landmark at exactly this spot, if a suggestion came from one.
  static Place? landmarkAt(double lat, double lng) {
    for (final p in camanavaPlaces) {
      if (p.lat == lat && p.lng == lng) return p;
    }
    return null;
  }

  static Future<List<LocationSearchResult>> suggest(
    String query, {
    int limit = 7,
  }) async {
    final local =
        localMatches(query)
            .map(
              (p) => LocationSearchResult(
                name: '${p.name}, ${p.city}',
                latitude: p.lat,
                longitude: p.lng,
              ),
            )
            .toList();
    final remote = await _nominatim(query);
    final seen = local.map((e) => e.name.toLowerCase()).toSet();
    final merged = List<LocationSearchResult>.from(local);
    for (final r in remote) {
      if (merged.length >= limit) break;
      if (seen.add(r.name.toLowerCase())) merged.add(r);
    }
    return merged;
  }

  static Future<List<LocationSearchResult>> _nominatim(String query) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=jsonv2'
        '&q=${Uri.encodeComponent(query)}&countrycodes=ph&limit=5'
        '&addressdetails=1',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'transitph-beta/1.0'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      if (data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final lat = double.tryParse('${item['lat']}');
            final lng = double.tryParse('${item['lon']}');
            final name = '${item['display_name'] ?? query}';
            if (lat == null || lng == null) return null;
            final short = name.split(',').take(3).join(',').trim();
            return LocationSearchResult(
              name: short.isEmpty ? name : short,
              latitude: lat,
              longitude: lng,
            );
          })
          .whereType<LocationSearchResult>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
