import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../services/route_metrics_service.dart';
import '../translated_text.dart';
import '../../theme/app_colors.dart';

/// Pin sizes. Kept small so a pin is hard to hit by accident while drawing
/// or panning; the selected one grows so it's easy to find again.
const double placePinSize = 24.0;
const double placePinSelectedSize = 36.0;

/// One neutral color for every place pin and category chip, so the map
/// stays calm; the icon tells the kind of place.
const Color placeNeutralColor = Color(0xFF4A5568);

/// A place-of-interest pin: the category icon on a neutral dot.
class PlacePin extends StatelessWidget {
  final Place place;
  final bool selected;
  final double scale;

  const PlacePin({
    super.key,
    required this.place,
    this.selected = false,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    const color = placeNeutralColor;
    final size = (selected ? placePinSelectedSize : placePinSize) * scale;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: (selected ? 2.5 : 1.5) * scale,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: selected ? 0.6 : 0.4),
            blurRadius: selected ? 10 : 5,
          ),
        ],
      ),
      child: Icon(
        place.categories.first.icon,
        color: Colors.white,
        size: (selected ? 19 : 13) * scale,
      ),
    );
  }
}

/// Zoom-based pin scale: hidden when zoomed far out so the map isn't
/// swamped, full size from street level.
double placePinScaleForZoom(double zoom) {
  const hideZoom = 10.5;
  const fullSizeZoom = 13.5;
  return ((zoom - hideZoom) / (fullSizeZoom - hideZoom)).clamp(0.0, 1.0);
}

/// Markers for [places], tappable. The selected place always shows at full
/// size; the rest follow [scale] and disappear when it is near zero.
List<Marker> placeMarkers({
  required Iterable<Place> places,
  required double scale,
  required ValueChanged<Place> onTap,
  String? selectedId,
}) {
  final markers = <Marker>[];
  Marker? selectedMarker;
  for (final place in places) {
    final selected = place.id == selectedId;
    final pinScale = selected ? 1.0 : scale;
    if (pinScale <= 0.02) continue;
    // A slightly larger hit box than the pin, but not by much: pins sit
    // under the drawing finger in contribute mode.
    final box = (selected ? placePinSelectedSize : placePinSize) * pinScale + 6;
    final marker = Marker(
      point: LatLng(place.lat, place.lng),
      width: box,
      height: box,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(place),
        child: Center(
          child: PlacePin(place: place, selected: selected, scale: pinScale),
        ),
      ),
    );
    if (selected) {
      selectedMarker = marker;
    } else {
      markers.add(marker);
    }
  }
  // Drawn last so it sits on top of its neighbours.
  if (selectedMarker != null) markers.add(selectedMarker);
  return markers;
}

/// "Directions": plan a trip to the place on screen.
class DirectionsButton extends StatelessWidget {
  final VoidCallback onPressed;

  const DirectionsButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF0B8FD6),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      icon: const Icon(Icons.directions_rounded, size: 18),
      label: const TranslatedText(
        'Directions',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// A selected place's details, shown at the top of the map drawer.
class PlaceDetailsSection extends StatelessWidget {
  final Place place;
  final double? distanceKm;
  final VoidCallback onClose;
  final VoidCallback? onLocate;

  /// Plan a trip here.
  final VoidCallback? onDirections;

  const PlaceDetailsSection({
    super.key,
    required this.place,
    required this.distanceKm,
    required this.onClose,
    this.onLocate,
    this.onDirections,
  });

  static const _accent = Color(0xFF0B8FD6);
  static Color get _surfaceAlt => AppColors.surfaceAlt;
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final category = place.categories.first;
    final typeLabel = place.categories.map((c) => c.singularLabel).join(', ');
    final locationParts = [
      place.city,
      if (place.address != null) place.address!,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(category.icon, color: category.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                TranslatedText(
                  typeLabel,
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.place_outlined, color: _textSecondary, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        locationParts.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (place.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TranslatedText(
                    place.description,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _distanceLabel(),
                if (onDirections != null) ...[
                  const SizedBox(height: 10),
                  DirectionsButton(onPressed: onDirections!),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Close',
            icon: Icon(Icons.close_rounded, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _distanceLabel() {
    final km = distanceKm;
    final known = km != null;
    return GestureDetector(
      onTap: known ? null : onLocate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: known ? AppColors.surfaceAlt : _surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              known ? Icons.near_me : Icons.location_on,
              color: known ? _accent : _textSecondary,
              size: 13,
            ),
            const SizedBox(width: 4),
            Flexible(
              child:
                  known
                      ? Text(
                        '${RouteMetricsService.formatDistance(km)} from your location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                      : TranslatedText(
                        'Enable location to see distance',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the drawer's nearby-places list.
class PlaceListTile extends StatelessWidget {
  final Place place;
  final double? distanceKm;
  final VoidCallback onTap;

  const PlaceListTile({
    super.key,
    required this.place,
    required this.distanceKm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const color = placeNeutralColor;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(place.categories.first.icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${place.city} · ${place.categories.map((c) => c.label).join(', ')}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (distanceKm != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  RouteMetricsService.formatDistance(distanceKm!),
                  style: const TextStyle(
                    color: Color(0xFF0B8FD6),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
