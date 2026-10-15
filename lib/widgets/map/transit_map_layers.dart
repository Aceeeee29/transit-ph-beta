part of 'transit_map.dart';

/// The sources and layers [TransitMap] adds over the base map, bottom to
/// top: place pins, route lines, dots, icons, drag handles, the open
/// place, then the traveler's dot over everything.
class _Layers {
  _Layers._();

  static const places = 'tph-places';
  static const selected = 'tph-selected';
  static const lines = 'tph-lines';
  static const dots = 'tph-dots';
  static const icons = 'tph-icons';
  static const handles = 'tph-handles';
  static const user = 'tph-user';

  static const placesOther = 'tph-places-other';
  static const placesHighlighted = 'tph-places-highlighted';
  static const placeSelected = 'tph-place-selected';
  static const dotLayer = 'tph-dots';
  static const iconLayer = 'tph-icons';

  /// Place pins a tap can open, top first.
  static const tappablePlaces = [placeSelected, placesHighlighted, placesOther];

  /// MapLibre zoom (app zoom − 1) where the places nobody highlighted
  /// appear: street level.
  static const placesFromZoom = 14.0;

  static Map<String, dynamic> sources() {
    const empty = {
      'type': 'geojson',
      'data': {'type': 'FeatureCollection', 'features': <Object>[]},
    };
    return {
      for (final id in [places, selected, lines, dots, icons, handles, user])
        id: empty,
    };
  }

  static List<Map<String, dynamic>> layers({required bool night}) {
    final label = {
      'text-font': ['Noto Sans Regular'],
      'text-size': 11,
      'text-anchor': 'top',
      'text-offset': [0, 1.1],
      'text-max-width': 8,
      'text-optional': true,
    };
    final labelPaint = {
      'text-color': night ? '#c3cbd6' : '#4a5568',
      'text-halo-color': night ? '#242f3e' : '#ffffff',
      'text-halo-width': 1.2,
    };
    // Names when zoomed in: ours a little sooner than OpenStreetMap's.
    final placeName = [
      'step', ['zoom'], '', //
      14.5,
      [
        'case',
        ['get', 'own'],
        ['get', 'name'],
        '',
      ],
      15.5, ['get', 'name'],
    ];
    // Ours first where pins would overlap, then the more prominent.
    final placeOrder = [
      'case',
      ['get', 'own'],
      -1,
      ['get', 'rank'],
    ];
    Map<String, dynamic> line(String style, Map<String, dynamic> extra) => {
      'id': '$lines-$style',
      'type': 'line',
      'source': lines,
      'filter': [
        '==',
        ['get', 'style'],
        style,
      ],
      'layout': {
        'line-join': 'round',
        'line-cap': style == 'dashed' ? 'butt' : 'round',
        'line-sort-key': ['get', 'order'],
      },
      'paint': {
        'line-color': ['get', 'color'],
        'line-width': ['get', 'width'],
        ...extra,
      },
    };
    final markerLabel = {
      'text-field': [
        'coalesce',
        ['get', 'label'],
        '',
      ],
      'text-font': ['Noto Sans Bold'],
      'text-size': 11,
      'text-allow-overlap': true,
      'text-ignore-placement': true,
    };

    return [
      // Places nobody highlighted: from street level, where there's room.
      {
        'id': placesOther,
        'type': 'symbol',
        'source': places,
        'minzoom': placesFromZoom,
        'filter': [
          '!',
          ['get', 'hl'],
        ],
        'layout': {
          'icon-image': ['get', 'icon'],
          'symbol-sort-key': placeOrder,
          ...label,
          'text-field': placeName,
        },
        'paint': labelPaint,
      },
      // Highlighted (the chips): at every zoom, smaller when far out.
      {
        'id': placesHighlighted,
        'type': 'symbol',
        'source': places,
        'filter': ['get', 'hl'],
        'layout': {
          'icon-image': ['get', 'icon'],
          'icon-size': [
            'interpolate', ['linear'], ['zoom'], 9, 0.55, 13, 1.0, //
          ],
          'symbol-sort-key': placeOrder,
          ...label,
          'text-field': placeName,
        },
        'paint': labelPaint,
      },
      line('solid', {}),
      line('dotted', {
        'line-dasharray': [0.1, 1.8],
      }),
      line('dashed', {
        'line-dasharray': [2.7, 1.8],
      }),
      {
        'id': dotLayer,
        'type': 'circle',
        'source': dots,
        'paint': {
          'circle-radius': ['get', 'radius'],
          'circle-color': ['get', 'color'],
          'circle-stroke-color': ['get', 'stroke'],
          'circle-stroke-width': ['get', 'strokeWidth'],
          'circle-pitch-alignment': 'map',
        },
      },
      {
        'id': '$dots-labels',
        'type': 'symbol',
        'source': dots,
        'filter': ['has', 'label'],
        'layout': markerLabel,
        'paint': {'text-color': '#1f2933'},
      },
      {
        'id': iconLayer,
        'type': 'symbol',
        'source': icons,
        'layout': {
          'icon-image': ['get', 'image'],
          'icon-anchor': ['get', 'anchor'],
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          ...markerLabel,
        },
        'paint': {'text-color': '#ffffff'},
      },
      {
        'id': handles,
        'type': 'symbol',
        'source': handles,
        'layout': {
          'icon-image': ['get', 'image'],
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          ...markerLabel,
        },
        'paint': {'text-color': '#ffffff'},
      },
      {
        'id': placeSelected,
        'type': 'symbol',
        'source': selected,
        'layout': {
          'icon-image': ['get', 'icon'],
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
          ...label,
          'text-field': ['get', 'name'],
          'text-offset': [0, 1.6],
        },
        'paint': labelPaint,
      },
      // The traveler: how sure the fix is, which way they're heading, the dot.
      {
        'id': '$user-accuracy',
        'type': 'circle',
        'source': user,
        'filter': [
          '==',
          ['get', 'kind'],
          'accuracy',
        ],
        'paint': {
          // Meters on the ground at any zoom (r0: pixels at zoom 0).
          'circle-radius': [
            'interpolate', ['exponential', 2], ['zoom'], //
            0, ['get', 'r0'],
            22,
            [
              '*',
              ['get', 'r0'],
              4194304,
            ],
          ],
          'circle-color': 'rgba(11,143,214,0.12)',
          'circle-stroke-color': 'rgba(11,143,214,0.3)',
          'circle-stroke-width': 1,
          'circle-pitch-alignment': 'map',
        },
      },
      {
        'id': '$user-heading',
        'type': 'symbol',
        'source': user,
        'filter': [
          '==',
          ['get', 'kind'],
          'heading',
        ],
        'layout': {
          'icon-image': MapPinImages.headingCone,
          'icon-rotate': ['get', 'heading'],
          'icon-rotation-alignment': 'map',
          'icon-pitch-alignment': 'map',
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
      {
        'id': '$user-dot',
        'type': 'symbol',
        'source': user,
        'filter': [
          '==',
          ['get', 'kind'],
          'dot',
        ],
        'layout': {
          'icon-image': MapPinImages.userDot,
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      },
    ];
  }

  // ─── Features ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> collection(Iterable<Map<String, dynamic>> f) => {
    'type': 'FeatureCollection',
    'features': f.toList(),
  };

  static Map<String, dynamic> point(LatLng at, Map<String, dynamic> props) => {
    'type': 'Feature',
    'properties': props,
    'geometry': {
      'type': 'Point',
      'coordinates': [at.longitude, at.latitude],
    },
  };

  static String color(Color c) =>
      'rgba(${(c.r * 255).round()},${(c.g * 255).round()},'
      '${(c.b * 255).round()},${c.a.toStringAsFixed(3)})';

  static Map<String, dynamic> placeFeature(
    Place place, {
    required bool highlighted,
    bool selected = false,
  }) => point(LatLng(place.lat, place.lng), {
    'id': place.id,
    'name': place.name,
    'icon': MapPinImages.placePin(place.categories.first, selected: selected),
    'own': !place.isFromMap,
    'rank': place.rank,
    'hl': highlighted,
  });

  static Map<String, dynamic> lineFeatures(List<MapLine> lines) => collection([
    for (var i = 0; i < lines.length; i++)
      if (lines[i].points.length >= 2)
        {
          'type': 'Feature',
          'properties': {
            'color': color(lines[i].color),
            'width': lines[i].width,
            'style': lines[i].style.name,
            'order': i,
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final p in lines[i].points) [p.longitude, p.latitude],
            ],
          },
        },
  ]);

  static Map<String, dynamic> dotFeatures(List<MapDot> dots) => collection([
    for (final dot in dots)
      point(dot.point, {
        if (dot.id != null) 'id': dot.id,
        'radius': dot.radius,
        'color': color(dot.color),
        'stroke': color(dot.strokeColor),
        'strokeWidth': dot.strokeWidth,
        if (dot.label != null) 'label': dot.label,
      }),
  ]);

  static Map<String, dynamic> iconFeatures(List<MapIcon> icons) => collection([
    for (final icon in icons)
      point(icon.point, {
        if (icon.id != null) 'id': icon.id,
        'image': icon.image,
        'anchor': icon.anchorBottom ? 'bottom' : 'center',
        if (icon.label != null) 'label': icon.label,
      }),
  ]);

  static Map<String, dynamic> handleFeatures(
    List<MapHandle> handles, {
    String? hiddenId,
  }) => collection([
    for (final handle in handles)
      if (handle.id != hiddenId)
        point(handle.point, {
          'image': handle.image,
          if (handle.label != null) 'label': handle.label,
        }),
  ]);

  /// The traveler at [at]: the accuracy circle, the heading cone while
  /// moving, and the dot.
  static Map<String, dynamic> userFeatures(
    LatLng at, {
    required double accuracyMeters,
    required double? headingDegrees,
  }) {
    // Meters per pixel at zoom 0 on MapLibre's 512-pixel world.
    final metersPerPixelZ0 =
        40075016.686 * math.cos(at.latitude * math.pi / 180) / 512;
    return collection([
      point(at, {
        'kind': 'accuracy',
        'r0': accuracyMeters.clamp(5.0, 60.0) / metersPerPixelZ0,
      }),
      if (headingDegrees != null)
        point(at, {'kind': 'heading', 'heading': headingDegrees}),
      point(at, {'kind': 'dot'}),
    ]);
  }
}
