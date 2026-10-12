part of 'contribute_screen.dart';

/// The browse search bar: find a place or a community route, like Google
/// Maps. A place is shown on the map with "Directions"; a route opens.
extension _ContributeScreenMapSearch on _ContributeScreenState {
  Future<void> _openMapSearch() async {
    final result = await Navigator.of(context).push<MapSearchResult>(
      MaterialPageRoute(
        builder: (_) => MapSearchScreen(routes: widget.searchableRoutes),
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case MapSearchPlace(:final place):
        _showFoundPlace(place);
      case MapSearchRoute(:final route):
        MapTabController.openRoute(context, route);
      case MapSearchDirections(:final query):
        widget.onOpenDirections?.call(query, null);
    }
  }

  void _showFoundPlace(LocationSearchResult found) {
    final landmark = PlaceSearchService.landmarkAt(
      found.latitude,
      found.longitude,
    );
    if (landmark != null) {
      // One of ours: its own pin and details card.
      _setUiState(() => _foundPlace = null);
      _centerOnNearbyPlace(landmark);
      return;
    }
    _setUiState(() {
      _nearbySelectedPlace = null;
      _foundPlace = found;
    });
    final zoom = _currentZoom < 16 ? 16.0 : _currentZoom;
    _mapController.move(LatLng(found.latitude, found.longitude), zoom);
    _setUiState(() => _currentZoom = zoom);
    // Its card (with Directions) lives in the drawer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MapDrawer.open(_drawerController);
    });
  }

  void _clearFoundPlace() => _setUiState(() => _foundPlace = null);

  void _openDirectionsTo(String name, double lat, double lng) {
    widget.onOpenDirections?.call(name, LatLng(lat, lng));
  }
}

/// The drawer card for a place found by search that isn't a landmark.
class _FoundPlaceSection extends StatelessWidget {
  final LocationSearchResult place;
  final VoidCallback onDirections;
  final VoidCallback onClose;

  const _FoundPlaceSection({
    required this.place,
    required this.onDirections,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.place, color: Colors.red, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _ContributeScreenState._textPrimary,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(
                  Icons.close_rounded,
                  color: _ContributeScreenState._textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DirectionsButton(onPressed: onDirections),
        ],
      ),
    );
  }
}
