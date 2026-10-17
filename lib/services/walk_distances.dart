import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Real walking distances along streets, from FOSSGIS's walking server: one
/// request measures from a few points to many.
///
/// The straight line can be far off: from 253 Galicia, Obando, the jeep
/// stop 280 m away as the crow flies is a 1.2 km walk (the street doesn't
/// connect), while a tricycle route the same distance away is 400 m.
///
/// The server answers about one table request per 10 s from the same
/// connection (later ones wait their turn), so a search makes just one.
class WalkDistances {
  WalkDistances._();

  static const _base =
      'https://routing.openstreetmap.de/routed-foot/table/v1/driving';

  /// Most points measured in one request (the URL gets long).
  static const maxTargets = 200;

  /// Meters on foot from each of [sources] to each of [targets] (at most
  /// [maxTargets]): one row per source, in order. Null where the server has
  /// no answer, or everywhere when it can't be reached within [timeout].
  static Future<List<List<double?>>> table(
    List<LatLng> sources,
    List<LatLng> targets, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final unknown = [
      for (final _ in sources) List<double?>.filled(targets.length, null),
    ];
    if (sources.isEmpty || targets.isEmpty || targets.length > maxTargets) {
      return unknown;
    }
    String spot(LatLng p) =>
        '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}';
    final n = sources.length;
    final uri = Uri.parse(
      '$_base/${[...sources, ...targets].map(spot).join(';')}'
      '?sources=${[for (var i = 0; i < n; i++) i].join(';')}'
      '&destinations=${[for (var i = 0; i < targets.length; i++) n + i].join(';')}'
      '&annotations=distance',
    );
    try {
      final response = await http
          .get(
            uri,
            headers: {'User-Agent': 'TransitPH/1.0 (transit-routing-app)'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return unknown;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return unknown;
      return [
        for (final row in data['distances'] as List)
          [for (final d in row as List) (d as num?)?.toDouble()],
      ];
    } catch (e) {
      debugPrint('[WalkDistances] Failed: $e');
      return unknown;
    }
  }
}
