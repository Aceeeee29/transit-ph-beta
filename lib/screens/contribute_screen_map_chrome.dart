part of 'contribute_screen.dart';

/// The Map tab's Google-Maps-style chrome: the search bar and category chips
/// on top, the round buttons on the right and the bottom drawer.
extension _ContributeScreenMapChrome on _ContributeScreenState {
  bool get _isStandaloneEditor =>
      widget.routeToEdit != null || widget.draftRoute != null;

  Widget _buildTopBarSection() {
    final isNearby = _mapMode == MapTabMode.nearby;
    final MapSearchBar bar;
    if (isNearby) {
      bar = MapSearchBar(
        hintText: 'Search places or routes',
        onTap: _openMapSearch,
        actions: [
          MapSearchBarAction(
            icon: Icons.add_circle_outline_rounded,
            tooltip: 'Contribute a route',
            onTap: () => _switchMapMode(MapTabMode.contribute),
          ),
          MapSearchBarAction(
            icon: Icons.help_outline_rounded,
            tooltip: 'Tutorial',
            color: _ContributeScreenState._textSecondary,
            onTap: () {
              _switchMapMode(MapTabMode.contribute);
              _showTutorialOverlay();
            },
          ),
        ],
      );
    } else {
      final query = _lastLocationSearchQuery.trim();
      bar = MapSearchBar(
        hintText:
            query.isNotEmpty
                ? query
                : (widget.routeToEdit != null
                    ? 'Editing route · search a place'
                    : 'Search a place to draw near'),
        onTap: _openLocationSearchScreen,
        leading: IconButton(
          tooltip: _isStandaloneEditor ? 'Back' : 'Done contributing',
          icon: Icon(
            Icons.arrow_back_rounded,
            color: _ContributeScreenState._textPrimary,
          ),
          onPressed: () {
            if (_isStandaloneEditor) {
              Navigator.of(context).maybePop();
            } else {
              _switchMapMode(MapTabMode.nearby);
            }
          },
        ),
        actions: [
          if (selectionMode == 'done' && steps.isNotEmpty)
            MapSearchBarAction(
              icon: Icons.preview_rounded,
              tooltip: 'Preview route',
              onTap: _onPreviewRoute,
            ),
          MapSearchBarAction(
            icon: Icons.help_outline_rounded,
            tooltip: 'Tutorial',
            color: _ContributeScreenState._textSecondary,
            onTap: _showTutorialOverlay,
          ),
        ],
      );
    }

    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: bar,
          ),
          const SizedBox(height: 8),
          PlaceCategoryChips(
            selected: _nearbySelected,
            onToggleAll: MapTabController.instance.toggleAllCategories,
            onToggle: _toggleNearbyCategory,
          ),
        ],
      ),
    );
  }

  Widget _buildSideButtonsSection() {
    return Positioned(
      right: 12,
      bottom: _ContributeScreenState._drawerPeekHeight + 12,
      child: MapSideButtons(
        children: [
          MapSideButton(
            icon: Icons.view_in_ar_rounded,
            tooltip: _tilted ? 'Flat view' : '3D view',
            active: _tilted,
            iconColor: _ContributeScreenState._accent,
            onTap: _toggleTilt,
          ),
          MapSideButton(
            icon:
                _showPins
                    ? Icons.location_on_rounded
                    : Icons.location_off_rounded,
            tooltip: _showPins ? 'Hide pins' : 'Show pins',
            iconColor:
                _showPins
                    ? _ContributeScreenState._accent
                    : _ContributeScreenState._textSecondary,
            onTap: _togglePins,
          ),
          MapSideButton(
            icon: Icons.my_location_rounded,
            tooltip: 'Center on my location',
            iconColor: _ContributeScreenState._accent,
            busy: _nearbyIsLocating,
            onTap: _centerOnNearbyUser,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSection() {
    final place = _nearbySelectedPlace;
    final isNearby = _mapMode == MapTabMode.nearby;
    return MapDrawer(
      controller: _drawerController,
      peekHeight: _ContributeScreenState._drawerPeekHeight,
      header: RegionWeatherRow(
        regions: philippineRegions.keys.toList(),
        selectedRegion: selectedRegion,
        onRegionSelected: _onRegionChanged,
      ),
      children: [
        if (place != null) ...[
          PlaceDetailsSection(
            place: place,
            distanceKm: _nearbyDistanceTo(place),
            onClose: _clearSelectedPlace,
            onLocate: _tryGetNearbyLocation,
            onDirections:
                isNearby
                    ? () => _openDirectionsTo(place.name, place.lat, place.lng)
                    : null,
          ),
          Divider(height: 1, color: _ContributeScreenState._border),
        ] else if (isNearby && _foundPlace != null) ...[
          _FoundPlaceSection(
            place: _foundPlace!,
            onClose: _clearFoundPlace,
            onDirections:
                () => _openDirectionsTo(
                  _foundPlace!.name,
                  _foundPlace!.latitude,
                  _foundPlace!.longitude,
                ),
          ),
          Divider(height: 1, color: _ContributeScreenState._border),
        ],
        if (isNearby)
          ..._nearbyListSection()
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              children: [
                if (steps.isNotEmpty) ...[
                  _buildStepsEditorSection(),
                  const SizedBox(height: 12),
                ],
                _buildFormContentSection(),
              ],
            ),
          ),
      ],
    );
  }

  /// The drawer's list when nothing else is open: the places matching the
  /// chips, nearest first once we know where you are.
  List<Widget> _nearbyListSection() {
    final from = _nearbyPosition;
    // Near you: the closest of every place on the map. Otherwise our own
    // list (OpenStreetMap's run into the thousands).
    var places = List<Place>.from(
      from != null ? _visibleMapPlaces : _visibleNearbyPlaces,
    );
    if (from != null) {
      final here = LatLng(from.latitude, from.longitude);
      final km = {
        for (final p in places) p.id: kmBetween(here, LatLng(p.lat, p.lng)),
      };
      places.sort((a, b) => km[a.id]!.compareTo(km[b.id]!));
      places = places.take(40).toList();
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Expanded(
              child: TranslatedText(
                'Nearby places',
                style: TextStyle(
                  color: _ContributeScreenState._textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (from == null)
              TextButton(
                onPressed: _tryGetNearbyLocation,
                child: const TranslatedText('Use my location'),
              ),
          ],
        ),
      ),
      if (from != null)
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: TranslatedText(
            'Nearest to farthest from you',
            style: TextStyle(
              color: _ContributeScreenState._textSecondary,
              fontSize: 11,
            ),
          ),
        ),
      for (final place in places)
        PlaceListTile(
          place: place,
          distanceKm: _nearbyDistanceTo(place),
          onTap: () => _centerOnNearbyPlace(place),
        ),
      const SizedBox(height: 16),
    ];
  }
}
