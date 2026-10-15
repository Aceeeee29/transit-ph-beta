part of 'contribute_screen.dart';

/// The Map tab's map, browsing and drawing alike: [TransitMap] (MapLibre),
/// which can tilt into 3D and shows every place on the map (ours and
/// OpenStreetMap's) without slowing down. Zooms are the app's numbers.
extension _ContributeScreenMapLibre on _ContributeScreenState {
  /// How far the camera leans in 3D, in degrees.
  static const _tilt3d = 60.0;

  bool get _isBrowsing => _mapMode == MapTabMode.nearby;

  // ─── Camera ───────────────────────────────────────────────────────────────

  /// Moves the camera to [center] at [zoom].
  void _moveCamera(LatLng center, double zoom) {
    _currentZoom = zoom;
    _map.moveTo(center, zoom: zoom);
  }

  /// Shows all of [bounds] inside [padding].
  Future<void> _fitCamera(LatLngBounds bounds, EdgeInsets padding) =>
      _map.fitPoints([bounds.southWest, bounds.northEast], padding: padding);

  /// Keeps [_currentZoom] current, for the zoom-based choices elsewhere on
  /// the screen, and the 2D/3D button in step with the camera.
  void _onMapCameraIdle(TransitMapCamera camera) {
    _currentZoom = camera.zoom;
    final tilted = camera.tilt > 5;
    if (tilted != _tilted) _setUiState(() => _tilted = tilted);
  }

  /// The 2D/3D button: leans the camera over (buildings stand up) or back.
  void _toggleTilt() {
    final tilted = !_tilted;
    _setUiState(() => _tilted = tilted);
    _map.tiltTo(tilted ? _tilt3d : 0);
  }

  // ─── The map ──────────────────────────────────────────────────────────────

  Widget _buildMapLayerSection() {
    final browsing = _isBrowsing;
    final found = _foundPlace;
    final coord = _debugCoord;
    final searched = _searchedLocation;
    final me = _nearbyPosition;
    return TransitMap(
      controller: _map,
      initialCenter: CamanavaBounds.center,
      initialZoom: _currentZoom,
      minZoom: 10,
      maxZoom: 18,
      // Only the center is kept in the area: holding the whole screen
      // inside it blocked zooming out far enough to show all of Metro
      // Manila.
      bounds: (
        southWest: const LatLng(14.38, 120.82),
        northEast: const LatLng(14.95, 121.20),
      ),
      places: MapPlaces(
        places: _showPins ? _allPlaces : const [],
        highlighted: _nearbySelected,
        selected: _nearbySelectedPlace,
      ),
      lines: browsing ? const [] : _routeLines,
      icons: [
        if (browsing && found != null)
          MapIcon(
            LatLng(found.latitude, found.longitude),
            MapPinImages.foundPin,
            anchorBottom: true,
          ),
        if (browsing && coord != null) MapIcon(coord, MapPinImages.coordMark),
        if (!browsing && _showPins && pathPoints.isNotEmpty)
          MapIcon(
            pathPoints.first,
            MapPinImages.routeStart,
            anchorBottom: true,
          ),
        if (!browsing && _showPins && pathPoints.length > 1)
          MapIcon(pathPoints.last, MapPinImages.routeEnd, anchorBottom: true),
        if (!browsing && _showPins && searched != null)
          MapIcon(searched, MapPinImages.searched),
      ],
      handles: browsing ? const [] : _routeHandles(),
      user:
          me == null
              ? null
              : MapUser(
                LatLng(me.latitude, me.longitude),
                accuracyMeters: me.accuracy,
              ),
      onTap: _onMapTap,
      onPlaceTap: _onNearbyPlaceTapped,
      onCameraIdle: _onMapCameraIdle,
      // Below the search bar and the chips.
      compassMargin: const Point(16, 130),
      // The OpenStreetMap credit, just above the drawer.
      attributionMargin: const Point(
        8,
        _ContributeScreenState._drawerPeekHeight + 8,
      ),
    );
  }

  /// The route being drawn: each step in its mode's color on a dark edge.
  List<MapLine> get _routeLines {
    final result = <MapLine>[];
    for (int i = 0; i < steps.length; i++) {
      final color = modeColors[steps[i].mode] ?? Colors.blue;
      final startIdx = (i == 0) ? 0 : stepBoundaries[i - 1];
      final endIdx =
          (i < stepBoundaries.length)
              ? stepBoundaries[i]
              : pathPoints.length - 1;
      if (endIdx <= startIdx) continue;
      final pts = pathPoints.sublist(startIdx, endIdx + 1);
      result
        ..add(
          MapLine(pts, color: Colors.black.withValues(alpha: 0.5), width: 8),
        )
        ..add(MapLine(pts, color: color, width: 6));
    }
    return result;
  }

  /// Handles are always on, while drawing and after Finish, so any step's
  /// line can be fixed at any time: the "+" on each piece (drag to add a
  /// via point), the numbered stops between steps, and the via points
  /// (drag to move, long-press to remove).
  List<MapHandle> _routeHandles() {
    final editing =
        (selectionMode == 'done' && steps.isNotEmpty) ||
        (selectionMode == 'step' && _stepCount > 0);
    if (!editing) return const [];
    final controls = _stepEditControls;
    final stops = controls.boundaryWaypoints;
    return [
      for (final handle in controls.insertHandles)
        MapHandle(
          id: 'insert-${handle.stepIndex}-${handle.controlIndex}',
          point: handle.point,
          image: MapPinImages.handleInsert,
          size: 26,
          onDragEnd:
              (point) => _onInsertHandleDragEnd(
                handle.stepIndex,
                handle.controlIndex,
                point,
              ),
        ),
      for (var i = 0; i < stops.length; i++)
        MapHandle(
          id: 'stop-$i',
          point: stops[i],
          image:
              i == 0
                  ? MapPinImages.handleStart
                  : i == stops.length - 1
                  ? MapPinImages.handleEnd
                  : MapPinImages.handleMiddle,
          label: '${i + 1}',
          size: 40,
          onDragEnd: (point) => _onBoundaryWaypointDragEnd(i, point),
        ),
      for (final handle in controls.bodyHandles)
        MapHandle(
          id: 'via-${handle.stepIndex}-${handle.controlIndex}',
          point: handle.point,
          image: MapPinImages.handleVia,
          size: 30,
          onDragEnd:
              (point) => _onBodyHandleDragEnd(
                handle.stepIndex,
                handle.controlIndex,
                point,
              ),
          onLongPress:
              () => _onViaPointLongPress(handle.stepIndex, handle.controlIndex),
        ),
    ];
  }

  // ─── Pins ─────────────────────────────────────────────────────────────────

  /// Places in the highlighted categories (all when none are), for the
  /// drawer's list.
  List<Place> get _visibleMapPlaces {
    if (_nearbySelected.isEmpty) return _allPlaces;
    return _allPlaces
        .where((p) => p.categories.any(_nearbySelected.contains))
        .toList();
  }
}
