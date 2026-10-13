part of 'route_map_screen.dart';

/// The route view's Map-tab chrome: the top bar (or the guidance card while
/// following), the right-side buttons and the route drawer.
extension _RouteMapScreenChrome on _RouteMapScreenState {
  static const _accent = _RouteMapScreenState._accent;
  static Color get _textPrimary => _RouteMapScreenState._textPrimary;
  static Color get _textSecondary => _RouteMapScreenState._textSecondary;
  static Color get _border => _RouteMapScreenState._border;
  static const _danger = _RouteMapScreenState._danger;
  static const _green = _RouteMapScreenState._green;

  Widget _buildTopOverlaySection() {
    if (_guidance.kind != FollowGuidanceKind.none) {
      // Following: the next instruction takes the search bar's place.
      return Positioned(
        top: 8,
        left: 12,
        right: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RouteBackButton(onBack: _closeView),
            const SizedBox(width: 8),
            Expanded(
              child: FollowGuidanceCard(
                guidance: _guidance,
                remainingMeters:
                    ActiveNavigationService.instance.connectorRemainingMeters,
                isRerouting: ActiveNavigationService.instance.isRerouting,
                routeStartLabel: widget.route.startLocation,
              ),
            ),
          ],
        ),
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
            child: RouteTopBar(
              from: widget.route.startLocation,
              to: widget.route.endLocation,
              onBack: _closeView,
            ),
          ),
          if (!_isNavigationStarted) ...[
            const SizedBox(height: 8),
            PlaceCategoryChips(
              selected: MapTabController.instance.placeCategories.value,
              onSelectAll: MapTabController.instance.clearCategories,
              onToggle: MapTabController.instance.toggleCategory,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSideButtonsSection() {
    final pins = MapTabController.instance.showPins;
    final following = _isNavigationStarted && _isAutoFollowEnabled;
    return Positioned(
      right: 12,
      bottom: _RouteMapScreenState._drawerPeekHeight + 12,
      child: MapSideButtons(
        children: [
          MapSideButton(
            icon: Icons.report_problem_rounded,
            tooltip: 'Report a problem with this route',
            iconColor: _danger,
            onTap: _showReportDialog,
          ),
          MapSideButton(
            icon:
                pins.value
                    ? Icons.location_on_rounded
                    : Icons.location_off_rounded,
            tooltip: pins.value ? 'Hide pins' : 'Show pins',
            iconColor: pins.value ? _accent : _textSecondary,
            onTap: () => pins.value = !pins.value,
          ),
          MapSideButton(
            icon:
                following
                    ? Icons.navigation_rounded
                    : Icons.my_location_rounded,
            tooltip:
                following ? 'Following your location' : 'Center on my location',
            iconColor: _accent,
            active: following,
            onTap: _centerOnCurrentLocation,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteDrawerSection() {
    final place = _selectedPlace;
    final remaining = _remainingTrip();
    final fare = _routeFareLabel();
    final String primary;
    final List<String> details;
    if (remaining != null) {
      primary = '${math.max(1, remaining.minutes)} min left';
      details = [
        '${RouteMetricsService.formatDistance(remaining.meters / 1000)} left',
        if (fare != null) fare,
      ];
    } else {
      primary = _routeEtaLabel() ?? 'Route';
      details = [_routeDistanceLabel(), if (fare != null) fare];
    }

    return MapDrawer(
      controller: _drawerController,
      peekHeight: _RouteMapScreenState._drawerPeekHeight,
      header: RouteDrawerHeader(
        primary: primary,
        secondary: details.join(' · '),
        trailing: RouteFollowButton(
          isFollowing: _isNavigationStarted,
          hasArrived: _hasArrived,
          onStart: _startNavigation,
          onStop: _stopNavigation,
          onDone: _finishArrivedRoute,
        ),
      ),
      children: [
        if (place != null) ...[
          PlaceDetailsSection(
            place: place,
            distanceKm: _distanceToPlace(place),
            onClose: _clearSelectedPlace,
          ),
          Divider(height: 1, color: _border),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              RouteActionChip(
                icon: Icons.arrow_upward_rounded,
                label: '${widget.route.upvotes}',
                active: _userVote == true,
                activeColor: _green,
                onTap: _isApplyingVote ? null : () => _vote(true),
              ),
              RouteActionChip(
                icon: Icons.arrow_downward_rounded,
                label: '${widget.route.downvotes}',
                active: _userVote == false,
                activeColor: _danger,
                onTap: _isApplyingVote ? null : () => _vote(false),
              ),
              if (widget.showDownloadButton)
                RouteActionChip(
                  icon:
                      _isRouteDownloaded
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                  label: _isRouteDownloaded ? 'Downloaded' : 'Download',
                  active: _isRouteDownloaded,
                  activeColor: _green,
                  busy: _isDownloadingRoute,
                  onTap:
                      (_isDownloadingRoute || _isRouteDownloaded)
                          ? null
                          : _downloadRouteForOffline,
                ),
            ],
          ),
        ),
        _buildModeLegendRow(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _infoPanelChildren(),
          ),
        ),
      ],
    );
  }

  /// Which color is which mode on the map, inline under the actions.
  Widget _buildModeLegendRow() {
    final routeModes = widget.route.steps.map((s) => s.mode).toSet();
    final entries =
        modeColors.entries.where((e) => routeModes.contains(e.key)).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final entry in entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 4,
                  decoration: BoxDecoration(
                    color: entry.value,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 11,
                    color: _textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  double? _distanceToPlace(Place place) {
    final here = _displayPosition;
    if (here == null) return null;
    return const Distance().as(
      LengthUnit.Kilometer,
      here,
      LatLng(place.lat, place.lng),
    );
  }
}
