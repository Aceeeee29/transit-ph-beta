part of 'route_map_screen.dart';

/// The route view's Map-tab chrome: the top bar (or the step card while
/// following), the right-side buttons and the route drawer.
extension _RouteMapScreenChrome on _RouteMapScreenState {
  static const _accent = _RouteMapScreenState._accent;
  static Color get _textSecondary => _RouteMapScreenState._textSecondary;
  static Color get _border => _RouteMapScreenState._border;
  static const _danger = _RouteMapScreenState._danger;
  static const _green = _RouteMapScreenState._green;

  /// Following and not yet arrived: the step card and no tabs.
  bool get _isFollowingNow => _isNavigationStarted && !_hasArrived;

  Widget _buildTopOverlaySection() {
    // Following: the step being travelled takes the top bar's place.
    final legCard = _isFollowingNow ? _buildLegCard() : null;
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child:
          legCard ??
          RouteTopBar(
            from: widget.route.startLocation,
            to: widget.route.endLocation,
            onBack: _closeView,
          ),
    );
  }

  /// Step [index] as the top card shows it.
  FollowLegInfo _legInfo(int index) {
    final step = widget.route.steps[index];
    final ends = FollowLegs.riderStepEnds(widget.route, index);
    final isWalk = step.mode == 'Walk';
    final instruction = step.instruction.trim();
    final fare =
        isWalk
            ? null
            : _applyFareDiscount(
              step.actualFare ?? _estimateStepFare(index, step),
              step.mode,
            );
    return FollowLegInfo(
      mode: step.mode,
      headline:
          ends.to != null
              ? '${isWalk ? 'Walk' : 'Ride'} to ${ends.to}'
              : instruction.isNotEmpty
              ? instruction
              : step.mode,
      from: ends.from,
      fare: fare != null && fare > 0 ? '₱${fare.round()}' : null,
    );
  }

  /// The card while following; how to get back to the route replaces the
  /// step while off it.
  Widget? _buildLegCard() {
    final steps = widget.route.steps;
    if (steps.isEmpty) return null;
    final navigation = ActiveNavigationService.instance;
    final progress = navigation.legProgress;
    final index = math.min(progress?.index ?? 0, steps.length - 1);
    final next =
        index + 1 < steps.length
            ? _legInfo(index + 1).headline
            : 'Arrive at ${widget.route.endLocation}';
    final followSteps = navigation.activeTarget?.steps ?? const <FollowStep>[];
    return FollowLegCard(
      leg: _legInfo(index),
      metersLeft: progress?.metersLeft ?? _estimateStepDistanceKm(index) * 1000,
      next: next,
      getOffSoon:
          progress != null &&
          _guidance.kind == FollowGuidanceKind.none &&
          progress.isGetOffSoon(followSteps),
      getOffName: FollowLegs.riderStepEnds(widget.route, index).to,
      guidance:
          _guidance.kind == FollowGuidanceKind.none
              ? null
              : FollowGuidanceCard(
                guidance: _guidance,
                remainingMeters: navigation.connectorRemainingMeters,
                isRerouting: navigation.isRerouting,
                routeStartLabel: widget.route.startLocation,
              ),
    );
  }

  /// The whole route in view. While following, the camera stops tracking
  /// until the location button is pressed.
  void _showWholeRoute() {
    if (_pathPoints.isEmpty) return;
    if (_isAutoFollowEnabled) _setAutoFollowEnabled(false);
    _map.fitPoints(
      _pathPoints,
      padding: EdgeInsets.fromLTRB(
        40,
        _isNavigationStarted ? 190 : 90,
        40,
        _drawerPeekHeight + 40,
      ),
      flat: true,
    );
  }

  Widget _buildSideButtonsSection() {
    final pins = MapTabController.instance.showPins;
    final following = _isNavigationStarted && _isAutoFollowEnabled;
    return Positioned(
      right: 12,
      bottom: _drawerPeekHeight + 12,
      child: MapSideButtons(
        children: [
          MapSideButton(
            icon: Icons.report_problem_rounded,
            tooltip: 'Report a problem with this route',
            iconColor: _danger,
            onTap: _showReportDialog,
          ),
          MapSideButton(
            icon: Icons.view_in_ar_rounded,
            tooltip: _tilted ? 'Flat view' : '3D view',
            active: _tilted,
            iconColor: _accent,
            onTap: _toggleTilt,
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
    final fare = _routeFareLabel()?.replaceFirst('PHP ', '₱');
    final time =
        remaining != null
            ? RouteMetricsService.formatEta(math.max(1, remaining.minutes))
            : _routeEtaLabel() ?? 'Route';
    final distance =
        remaining != null
            ? RouteMetricsService.formatDistance(remaining.meters / 1000)
            : _routeDistanceLabel();
    final modes = <String>[];
    for (final step in widget.route.steps) {
      if (!modes.contains(step.mode)) modes.add(step.mode);
    }

    return MapDrawer(
      controller: _drawerController,
      peekHeight: _drawerPeekHeight,
      header: RouteDrawerHeader(
        primary: time,
        secondary: [distance, if (fare != null) fare].join(' · '),
        isFollowing: _isNavigationStarted,
        hasArrived: _hasArrived,
        isStarting: _isStarting,
        onStart: _startNavigation,
        onStop: _stopNavigation,
        onDone: _finishArrivedRoute,
        onOverview: _showWholeRoute,
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
        RouteReportBanner(reports: _sharedReports, routeId: widget.route.id),
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
        RouteModeLegend(modes: modes),
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

  double? _distanceToPlace(Place place) {
    final here = _displayPosition;
    if (here == null) return null;
    return const Distance(
      roundResult: false,
    ).as(LengthUnit.Kilometer, here, LatLng(place.lat, place.lng));
  }
}
