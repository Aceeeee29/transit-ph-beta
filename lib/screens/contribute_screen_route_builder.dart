part of 'contribute_screen.dart';

extension _ContributeScreenSections on _ContributeScreenState {
  static const _surface = _ContributeScreenState._surface;
  static const _surfaceAlt = _ContributeScreenState._surfaceAlt;
  static const _accent = _ContributeScreenState._accent;
  static const _accentSoft = _ContributeScreenState._accentSoft;
  static const _textPrimary = _ContributeScreenState._textPrimary;
  static const _textSecondary = _ContributeScreenState._textSecondary;
  static const _border = _ContributeScreenState._border;

  route_model.Route _buildRouteSection({String? existingId}) {
    double totalDurS = 0;
    double totalDistKm = 0;
    double totalFare = 0;
    final Distance distCalc = const Distance();

    for (int i = 0; i < steps.length; i++) {
      final orsDistM = i < _stepOrsDistM.length ? _stepOrsDistM[i] : null;
      final orsDurS = i < _stepOrsDurS.length ? _stepOrsDurS[i] : null;

      // A snap that reported 0 m would save the route as "0 m"; measure the
      // drawn step instead.
      if (orsDistM != null && orsDistM > 0 && orsDurS != null && orsDurS > 0) {
        totalDistKm += orsDistM / 1000;
        totalDurS += orsDurS;
        totalFare +=
            steps[i].actualFare ??
            RouteMetricsService.calculateFareForMode(
              steps[i].mode,
              orsDistM / 1000,
            );
      } else {
        final startIdx =
            (i == 0)
                ? 0
                : (i - 1 < stepBoundaries.length ? stepBoundaries[i - 1] : 0);
        final endIdx =
            (i < stepBoundaries.length)
                ? stepBoundaries[i]
                : pathPoints.length - 1;
        double segDistKm = 0;
        for (int j = startIdx; j < endIdx && j + 1 < pathPoints.length; j++) {
          segDistKm += distCalc.as(
            LengthUnit.Kilometer,
            pathPoints[j],
            pathPoints[j + 1],
          );
        }
        totalDistKm += segDistKm;
        final speedKmh = _speedForMode(steps[i].mode);
        totalDurS += (segDistKm / speedKmh) * 3600;
        totalFare +=
            steps[i].actualFare ??
            RouteMetricsService.calculateFareForMode(steps[i].mode, segDistKm);
      }
    }
    if (steps.length > 1) totalDurS += (steps.length - 1) * 120;

    final distStr = RouteMetricsService.formatDistance(totalDistKm);
    final etaStr = (totalDurS / 60).ceil().toString();
    final fareStr = 'PHP ${totalFare.round()}';
    final schedule = _deriveRouteSchedule(steps);

    final startLoc =
        _startLocationController.text.isEmpty
            ? 'Start Point (${pathPoints.first.latitude.toStringAsFixed(4)}, ${pathPoints.first.longitude.toStringAsFixed(4)})'
            : _startLocationController.text;
    final endLoc =
        _endLocationController.text.isEmpty
            ? 'End Point (${pathPoints.last.latitude.toStringAsFixed(4)}, ${pathPoints.last.longitude.toStringAsFixed(4)})'
            : _endLocationController.text;
    final desc =
        _shortDescriptionController.text.isEmpty
            ? 'Custom route with ${steps.length} steps'
            : _shortDescriptionController.text;

    return route_model.Route(
      id: existingId ?? DateTime.now().toString(),
      startLocation: startLoc,
      endLocation: endLoc,
      shortDescription: desc,
      steps: steps,
      startLat: pathPoints.first.latitude,
      startLng: pathPoints.first.longitude,
      endLat: pathPoints.last.latitude,
      endLng: pathPoints.last.longitude,
      pathPoints: pathPoints,
      stepBoundaries: stepBoundaries,
      eta: etaStr,
      price: fareStr,
      distance: distStr,
      schedule: schedule,
      audienceTags: _selectedRouteTags,
      distanceMeters: totalDistKm > 0 ? totalDistKm * 1000 : null,
      contributorId:
          widget.routeToEdit?.contributorId ??
          widget.contributorId ??
          FirebaseAuth.instance.currentUser?.uid,
      approvalStatus: route_model.RouteApprovalStatus.pending,
    );
  }

  bool _validateStepReliabilitySection() {
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final stepNo = i + 1;
      final isMotorized = step.mode != 'Walk';

      if (step.instruction.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Step $stepNo is missing an instruction.')),
        );
        return false;
      }

      if (!isMotorized) continue;

      if (step.details.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Step $stepNo needs details for ${step.mode}.'),
          ),
        );
        return false;
      }

      final hasSchedule =
          step.is24_7 ||
          ((step.startTime?.trim().isNotEmpty ?? false) &&
              (step.endTime?.trim().isNotEmpty ?? false));
      if (!hasSchedule) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Step $stepNo needs operating hours for ${step.mode}.',
            ),
          ),
        );
        return false;
      }

      if (step.actualFare == null || step.actualFare! < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Step $stepNo needs a valid actual fare for ${step.mode}.',
            ),
          ),
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _submitSection({bool forceModeration = false}) async {
    if (pathPoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText('Need at least start and end points on map'),
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (!_validateStepReliability()) {
        return;
      }
      final route = _buildRoute(existingId: widget.routeToEdit?.id);
      try {
        if (_isQuickCreateMode && !forceModeration) {
          final userId = FirebaseAuth.instance.currentUser?.uid;
          if (userId == null || userId.isEmpty) {
            throw StateError('Please sign in to quick create a route.');
          }
          await QuickRouteLinkService.createQuickRouteFromLink(
            token: _activeQuickRouteToken!,
            route: route,
            creatorId: userId,
          );
        } else {
          await widget.onRouteSubmitted(route);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit route: $e')));
        return;
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder:
            (_) =>
                widget.routeToEdit != null
                    ? const _SubmitSuccessDialog(isEdit: true)
                    : _SubmitSuccessDialog(
                      isEdit: false,
                      quickCreateMode: _isQuickCreateMode,
                    ),
      );

      if (widget.routeToEdit == null) {
        await _bumpContributionStats();
        if (!mounted) return;
        _resetAfterSubmitSuccess();
      }
    }
  }

  void _onPreviewRouteSection() {
    if (pathPoints.length < 2 || steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(
            'Need at least start, end points and one step',
          ),
        ),
      );
      return;
    }

    final route = _buildRoute();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => RoutePreview(
              route: route,
              onEdit: () {
                Navigator.pop(context);
              },
              onSubmit: () {
                Navigator.pop(context);
                _submit();
              },
            ),
      ),
    );
  }

  AppBar _buildAppBarSection() {
    final isNearby = _mapMode == MapTabMode.nearby;
    return AppBar(
      backgroundColor: _surface,
      foregroundColor: _textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              isNearby ? Icons.near_me_rounded : Icons.add_road_rounded,
              color: _accent,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TranslatedText(
                  isNearby
                      ? 'Nearby Places'
                      : (widget.routeToEdit != null
                          ? 'Edit Route'
                          : 'Contribute a Route'),
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (isNearby)
                  const TranslatedText(
                    'Places across CAMANAVA',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        GestureDetector(
          onTap:
              () => _switchMapMode(
                isNearby ? MapTabMode.contribute : MapTabMode.nearby,
              ),
          child: Tooltip(
            message:
                isNearby ? 'Back to route contribution' : 'Show Nearby Places',
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isNearby ? Icons.add_road_outlined : Icons.near_me_outlined,
                    color: _accent,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  TranslatedText(
                    isNearby ? 'Contribute' : 'Show Nearby Places',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Pin visibility has its own toggle floating on the map itself
        // (_buildPinsToggleSection) — no duplicate control here.
        // Secondary actions live in an overflow menu so the AppBar can
        // never overflow, no matter how many become visible at once
        // (e.g. after Load Example sets selectionMode to done with steps,
        // which previously added edit-handles + preview buttons and broke
        // the layout on narrow screens).
        if (!isNearby)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PopupMenuButton<String>(
              tooltip: 'More actions',
              offset: const Offset(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: const Icon(
                  Icons.more_vert_rounded,
                  color: _textSecondary,
                  size: 18,
                ),
              ),
              onSelected: (value) {
                switch (value) {
                  case 'handles':
                    _toggleEditHandles();
                  case 'preview':
                    _onPreviewRoute();
                  case 'tutorial':
                    _showTutorialOverlay();
                }
              },
              itemBuilder:
                  (_) => [
                    if (selectionMode == 'done' && steps.isNotEmpty)
                      PopupMenuItem(
                        value: 'handles',
                        child: Row(
                          children: [
                            Icon(
                              _showEditHandles
                                  ? Icons.edit_location_alt_rounded
                                  : Icons.edit_location_alt_outlined,
                              color: _accent,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TranslatedText(
                                _showEditHandles
                                    ? 'Hide edit handles'
                                    : 'Show edit handles',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (selectionMode == 'done')
                      const PopupMenuItem(
                        value: 'preview',
                        child: Row(
                          children: [
                            Icon(
                              Icons.preview_rounded,
                              color: _accent,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: TranslatedText(
                                'Preview route',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'tutorial',
                      child: Row(
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            color: _textSecondary,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: TranslatedText(
                              'Tutorial',
                              style: TextStyle(
                                fontSize: 13,
                                color: _textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  Widget _buildMapLayerSection() {
    final editControls = _stepEditControls;
    final isNearby = _mapMode == MapTabMode.nearby;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: CamanavaBounds.center,
        initialZoom: CamanavaBounds.initialZoom,
        minZoom: 9.0,
        maxZoom: 18.0,
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(
            const LatLng(14.38, 120.82),
            const LatLng(14.95, 121.20),
          ),
        ),
        onTap: _onMapTap,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) {
            _setUiState(() => _currentZoom = position.zoom);
            _revealZoomControls();
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app.transitph_beta',
        ),
        if (!isNearby) ...[
          // PolygonLayer(polygons: _regionBoundaryPolygons), // TODO: re-enable once real boundary data is added
          PolylineLayer(polylines: polylines),
          MarkerLayer(
            markers: [
              // POI reference pins (schools, attractions, parks, …) — shown
              // in contribute mode too so users can draw routes relative to
              // them. Deliberately non-interactive (IgnorePointer) so taps
              // always fall through to route-point drawing; full details
              // stay in Nearby Places mode. Hidden via the pins toggle.
              if (_showPins && _poiPinScale > 0.02)
                for (final place in camanavaPlaces)
                  Marker(
                    point: LatLng(place.lat, place.lng),
                    width: 34 * _poiPinScale,
                    height: 34 * _poiPinScale,
                    child: IgnorePointer(
                      child: _NearbyPlacePin(
                        place: place,
                        selected: false,
                        scale: _poiPinScale,
                      ),
                    ),
                  ),
              if (_showPins && pathPoints.isNotEmpty)
                Marker(
                  point: pathPoints.first,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.green,
                    size: 40,
                  ),
                ),
              if (_showPins && pathPoints.length > 1)
                Marker(
                  point: pathPoints.last,
                  child: const Icon(Icons.flag, color: Colors.red, size: 40),
                ),
              if (_showPins && _searchedLocation != null)
                Marker(
                  point: _searchedLocation!,
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: _accent,
                    size: 34,
                  ),
                ),
            ],
          ),
          if (selectionMode == 'done' && steps.isNotEmpty && _showEditHandles)
            DraggableStepMarkersLayer(
              boundaryWaypoints: editControls.boundaryWaypoints,
              bodyHandles: editControls.bodyHandles,
              onBoundaryDragEnd: _onBoundaryWaypointDragEnd,
              onBodyDragEnd: _onBodyHandleDragEnd,
              accent: _accent,
            ),
        ] else
          MarkerLayer(
            markers: [
              if (_showPins)
                for (final marker
                    in _visibleNearbyPlaces
                        .map(_buildNearbyPlaceMarker)
                        .whereType<Marker>())
                  marker,
              if (_showPins && _nearbyPosition != null)
                Marker(
                  point: LatLng(
                    _nearbyPosition!.latitude,
                    _nearbyPosition!.longitude,
                  ),
                  child: const _NearbyUserPin(),
                ),
              if (_debugCoord != null)
                Marker(
                  point: _debugCoord!,
                  child: const Icon(Icons.add, color: _accent, size: 40),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildMapControlsOverlaySection() {
    double? totalOrsDistKm;
    int? totalOrsDurMinutes;

    if (_stepOrsDistM.isNotEmpty && _stepOrsDistM.every((d) => d != null)) {
      totalOrsDistKm =
          _stepOrsDistM.fold(0.0, (sum, d) => sum + (d ?? 0)) / 1000;
    }
    if (_stepOrsDurS.isNotEmpty && _stepOrsDurS.every((d) => d != null)) {
      double totalSeconds = _stepOrsDurS.fold(0.0, (sum, d) => sum + (d ?? 0));
      if (steps.length > 1) totalSeconds += ((steps.length - 1) * 120);
      totalOrsDurMinutes = (totalSeconds / 60).ceil();
    }

    return Positioned(
      top: 70,
      left: 20,
      child: MapControls(
        historyService: _historyService,
        pathPoints: pathPoints,
        steps: steps,
        stepBoundaries: stepBoundaries,
        selectionMode: selectionMode,
        currentMode: currentMode,
        onUndo: _onUndo,
        onRedo: _onRedo,
        onReset: _onReset,
        onPreview: _onPreviewRoute,
        showPreview: false,
        onSnapToRoadToggled: _onSnapToRoadToggled,
        snapToRoadEnabled: _snapToRoadEnabled,
        orsDistanceKm: totalOrsDistKm,
        orsDurationMinutes: totalOrsDurMinutes,
      ),
    );
  }

  Widget _buildInstructionPillSection() {
    if (selectionMode == 'done') return const SizedBox.shrink();

    final String text =
        selectionMode == 'start'
            ? 'Tap on the map to select the starting point'
            : 'Tap to select next point for $currentMode';

    // NOTE: sits above the bottom-left pins toggle (drawer 0-40,
    // pins 46-80), so bottom is 88 to avoid overlap.
    return Positioned(
      bottom: 88,
      left: 12,
      right: 12,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _surface.withOpacity(0.97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: _accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.touch_app_rounded,
                      size: 13,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selectionMode == 'step' && steps.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _onFinishRoutePressed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3EC97A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Finish (${steps.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (selectionMode == 'step') ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _ContributeScreenState.modes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final mode = _ContributeScreenState.modes[i];
                      final selected = currentMode == mode;
                      final color = modeColors[mode] ?? _accent;
                      return GestureDetector(
                        onTap: () => _setUiState(() => currentMode = mode),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? color : _surfaceAlt,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? color : _border,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getModeIcon(mode),
                                size: 13,
                                color: selected ? Colors.white : color,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                mode,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? Colors.white : _textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepChipsBarSection() {
    if (steps.isEmpty) return const SizedBox.shrink();

    // Stacked above the pins toggle (46-80) and, when selecting points,
    // above the instruction pill as well.
    final bottom = selectionMode == 'done' ? 88.0 : 180.0;

    return Positioned(
      bottom: bottom,
      left: 12,
      right: 12,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              GestureDetector(
                onTap: () => _showEditStepDialog(i),
                onLongPress: () => _deleteStep(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _surface.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getModeIcon(steps[i].mode),
                        size: 12,
                        color: modeColors[steps[i].mode] ?? _accent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${i + 1}. ${_stepChipLabel(steps[i])}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  String _stepChipLabel(route_model.Step step) {
    final text = step.instruction.trim();
    if (text.isEmpty) return step.mode;
    final space = text.indexOf(' ');
    final first = space > 0 ? text.substring(0, space) : text;
    return first.length > 14 ? first.substring(0, 14) : first;
  }

  Widget _buildRegionSelectorSection() {
    return Positioned(
      top: 10,
      right: 16,
      child: Container(
        width: 155,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: _surface.withOpacity(0.97),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: DropdownButtonFormField<String>(
          initialValue: selectedRegion,
          hint: const TranslatedText(
            'Select Area',
            style: TextStyle(fontSize: 11, color: _textSecondary),
          ),
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _accent,
            size: 18,
          ),
          dropdownColor: _surface,
          style: const TextStyle(color: _textPrimary, fontSize: 11),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          items:
              philippineRegions.keys.map((region) {
                return DropdownMenuItem<String>(
                  value: region,
                  child: Text(
                    region,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
          onChanged: _onRegionChanged,
        ),
      ),
    );
  }

  Widget _buildLocationSearchBarSection() {
    return Positioned(
      top: 10,
      left: 16,
      right: 180,
      child: ContributeLocationSearchBar(
        onSearch: _onLocationSearched,
        onTapSearch: _openLocationSearchScreen,
        displayText: _lastLocationSearchQuery,
        surface: _surface,
        border: _border,
        accent: _accent,
        textPrimary: _textPrimary,
        textSecondary: _textSecondary,
      ),
    );
  }

  Widget _buildPinsToggleSection() {
    // Bottom-left, just above the route details drawer (contribute mode)
    // or above the bottom nav (nearby mode). Kept clear of the MapControls
    // box (top-left), the instruction pill, and the step chips — see the
    // bottom offsets on those overlays.
    final isNearby = _mapMode == MapTabMode.nearby;
    return Positioned(
      bottom: isNearby ? 16 : 46,
      left: 12,
      child: GestureDetector(
        onTap: _togglePins,
        child: Tooltip(
          message: _showPins ? 'Hide pins' : 'Show pins',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _showPins ? _accentSoft : _surface.withOpacity(0.97),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _showPins ? _accent.withOpacity(0.35) : _border,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showPins
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: _showPins ? _accent : _textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 6),
                TranslatedText(
                  _showPins ? 'Hide Pins' : 'Show Pins',
                  style: TextStyle(
                    color: _showPins ? _accent : _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormDrawerSection(BuildContext context, double availableHeight) {
    // The drawer must always fit inside the body area (above the app bar,
    // bottom nav and keyboard) — otherwise its lower half sits off-screen and
    // scrolled content becomes unreachable.
    final expandedHeight =
        (availableHeight * 0.6).clamp(200.0, availableHeight - 8.0).toDouble();
    // The top border sits inside the container's height, so the collapsed
    // drawer must be the handle plus the border or the handle overflows.
    const borderWidth = 1.5;
    const collapsedHeight = 40.0 + borderWidth;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _isFormExpanded ? expandedHeight : collapsedHeight,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: _border, width: borderWidth),
          ),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Column(
            children: [
              _buildDrawerHandle(),
              if (_isFormExpanded)
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerHandleSection() {
    return InkWell(
      onTap: _toggleFormExpanded,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: TranslatedText(
                _isFormExpanded ? 'Hide Form' : 'Route Details',
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              _isFormExpanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: _accent,
            ),
            if (!_isFormExpanded && steps.isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _accent.withOpacity(0.2)),
                ),
                child: Text(
                  '${steps.length} step${steps.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormContentSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Form(
        key: _formKey,
        child: RouteFormStepper(
          startLocationController: _startLocationController,
          endLocationController: _endLocationController,
          shortDescriptionController: _shortDescriptionController,
          selectedRouteTags: _selectedRouteTags,
          userTagOptions: _ContributeScreenState.onboardingUserTags,
          otherTagOptions: _ContributeScreenState.otherRouteTags,
          onRouteTagsChanged: _setSelectedRouteTags,
          onSubmit: () => _submit(),
          onSubmitForReviewInstead:
              _isQuickCreateMode ? _submitForReviewInstead : null,
          onCreateQuickLink: _isQuickCreateMode ? null : _createQuickLink,
          onReset: _onReset,
          selectionMode: selectionMode,
          quickCreateMode: _isQuickCreateMode,
          // Same condition as the map's Finish pill.
          onFinishRoute:
              selectionMode == 'step' && steps.isNotEmpty
                  ? _onFinishRoutePressed
                  : null,
        ),
      ),
    );
  }

  Widget _buildStepsEditorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const TranslatedText(
              'Route Steps',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${steps.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _accent,
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: GestureDetector(
                onTap: _toggleEditHandles,
                child: TranslatedText(
                  _showEditHandles ? 'Drag handles ON' : 'Drag handles',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < steps.length; i++) ...[
          _buildStepEditorTileSection(i),
          const SizedBox(height: 8),
        ],
        const Divider(height: 8, color: _border),
      ],
    );
  }

  Widget _buildStepEditorTileSection(int index) {
    final step = steps[index];
    final color = modeColors[step.mode] ?? _accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(_getModeIcon(step.mode), color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.instruction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  _stepEditorSubtitle(step),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: _textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            color: _textSecondary,
            onPressed: index > 0 ? () => _moveStep(index, -1) : null,
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            color: _textSecondary,
            onPressed:
                index < steps.length - 1 ? () => _moveStep(index, 1) : null,
            icon: const Icon(Icons.arrow_downward),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            color: _accent,
            onPressed: () => _showEditStepDialog(index),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            color: const Color(0xFFE05C6A),
            onPressed: () => _deleteStep(index),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  String _stepEditorSubtitle(route_model.Step step) {
    final parts = <String>[];
    if (step.mode == 'Walk') {
      parts.add('Walk');
    } else {
      if (step.actualFare != null) parts.add('PHP ${step.actualFare!.round()}');
      if (step.is24_7) {
        parts.add('24/7');
      } else if (step.startTime != null && step.endTime != null) {
        parts.add('${step.startTime}–${step.endTime}');
      }
    }
    return parts.join(' · ');
  }

  // ─── Nearby-places mode ────────────────────────────────────────────────

  List<Place> get _visibleNearbyPlaces {
    if (_nearbySelected.isEmpty) return camanavaPlaces;
    return camanavaPlaces
        .where((p) => p.categories.any(_nearbySelected.contains))
        .toList();
  }

  Future<void> _tryGetNearbyLocation() async {
    _setUiState(() => _nearbyIsLocating = true);
    final hasAccess = await ensureLocationAccess(
      context,
      reason: 'show how far nearby places are from you',
    );
    if (!mounted) return;
    final position =
        hasAccess ? await LocationService.getCurrentPosition() : null;
    if (!mounted) return;
    _setUiState(() {
      _nearbyPosition = position;
      _nearbyIsLocating = false;
    });
    if (position == null && hasAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(
            'Could not get a GPS fix. Try again in a moment.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _toggleNearbyCategory(PlaceCategory category) {
    _setUiState(() {
      if (_nearbySelected.contains(category)) {
        _nearbySelected.remove(category);
      } else {
        _nearbySelected.add(category);
      }
    });
  }

  double? _nearbyDistanceTo(Place place) {
    final from = _nearbyPosition;
    if (from == null) return null;
    return kmBetween(
      LatLng(from.latitude, from.longitude),
      LatLng(place.lat, place.lng),
    );
  }

  void _onNearbyPlaceTapped(Place place) {
    _setUiState(() => _nearbySelectedPlace = place);
  }

  /// Builds a nearby-place marker, or null when it should be auto-hidden
  /// (zoomed out too far and not the currently-selected place).
  Marker? _buildNearbyPlaceMarker(Place place) {
    final selected = place.id == _nearbySelectedPlace?.id;
    final scale = selected ? 1.0 : _poiPinScale;
    if (scale <= 0.02) return null;
    final size = (selected ? 48.0 : 34.0) * scale;
    return Marker(
      point: LatLng(place.lat, place.lng),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => _onNearbyPlaceTapped(place),
        child: _NearbyPlacePin(place: place, selected: selected, scale: scale),
      ),
    );
  }

  void _centerOnNearbyPlace(Place place) {
    _setUiState(() {
      _nearbySelectedPlace = place;
      _nearbySelected.clear();
      _nearbySelected.addAll(place.categories);
    });
    _mapController.move(
      LatLng(place.lat, place.lng),
      CamanavaBounds.initialZoom,
    );
  }

  Future<void> _openNearbyListSheet() async {
    final sorted = List<Place>.from(_visibleNearbyPlaces);
    final from = _nearbyPosition;
    if (from != null) {
      sorted.sort((a, b) {
        final da = kmBetween(
          LatLng(from.latitude, from.longitude),
          LatLng(a.lat, a.lng),
        );
        final db = kmBetween(
          LatLng(from.latitude, from.longitude),
          LatLng(b.lat, b.lng),
        );
        return da.compareTo(db);
      });
    }
    final place = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _NearbyPlacesListSheet(
            places: sorted,
            currentPosition: from,
            onLocate: () => Navigator.pop(context),
          ),
    );
    if (place != null && mounted) {
      _centerOnNearbyPlace(place);
    }
  }

  void _centerOnNearbyUser() {
    if (_nearbyPosition == null) {
      _tryGetNearbyLocation();
      return;
    }
    _mapController.move(
      LatLng(_nearbyPosition!.latitude, _nearbyPosition!.longitude),
      CamanavaBounds.initialZoom,
    );
  }

  Widget _buildNearbyFilterChips() {
    Widget chip({
      required String label,
      required IconData icon,
      required Color color,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : _border, width: 1.2),
            boxShadow:
                selected
                    ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8)]
                    : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? Colors.white : color),
              const SizedBox(width: 5),
              TranslatedText(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : _textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(
              label: 'All',
              icon: Icons.apps,
              color: _accent,
              selected: _nearbySelected.isEmpty,
              onTap: () => _setUiState(() => _nearbySelected.clear()),
            ),
            for (final category in PlaceCategory.values) ...[
              const SizedBox(width: 8),
              chip(
                label: category.label,
                icon: category.icon,
                color: category.color,
                selected: _nearbySelected.contains(category),
                onTap: () => _toggleNearbyCategory(category),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyDebugCoordChip() {
    final coord = _debugCoord;
    if (coord == null) return const SizedBox.shrink();
    return Positioned(
      bottom: 98,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _surface.withOpacity(0.97),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(color: _accent.withOpacity(0.1), blurRadius: 10),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.my_location_rounded, color: _accent, size: 14),
            const SizedBox(width: 6),
            Text(
              '${coord.latitude.toStringAsFixed(5)}, ${coord.longitude.toStringAsFixed(5)}',
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}',
                  ),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: TranslatedText('Coordinates copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Icon(
                Icons.copy_rounded,
                color: _textSecondary,
                size: 14,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _setUiState(() => _debugCoord = null),
              child: const Icon(
                Icons.close_rounded,
                color: _textSecondary,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyInfoCard(Place place) {
    final distanceKm = _nearbyDistanceTo(place);
    final typeLabel = place.categories.map((c) => c.singularLabel).join(', ');
    final locationParts = [
      place.city,
      if (place.address != null) place.address!,
    ];
    return Positioned(
      left: 12,
      right: 12,
      bottom: 84,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: place.categories.first.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                place.categories.first.icon,
                color: place.categories.first.color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place.name,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap:
                            () =>
                                _setUiState(() => _nearbySelectedPlace = null),
                        child: const Icon(
                          Icons.close_rounded,
                          color: _textSecondary,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  TranslatedText(
                    typeLabel,
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (locationParts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          color: _textSecondary,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locationParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildNearbyDistanceLabel(distanceKm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyDistanceLabel(double? distanceKm) {
    if (distanceKm != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF6FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.near_me, color: _accent, size: 13),
            const SizedBox(width: 4),
            Text(
              '${RouteMetricsService.formatDistance(distanceKm)} from your location',
              style: const TextStyle(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _tryGetNearbyLocation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, color: _textSecondary, size: 13),
            const SizedBox(width: 4),
            const TranslatedText(
              'Enable location to see distance',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyFabs() {
    return Positioned(
      right: 14,
      bottom: 14,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _openNearbyListSheet,
            child: Tooltip(
              message: 'Show Nearby Places list',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(color: _accent.withOpacity(0.12), blurRadius: 12),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.format_list_bulleted_rounded,
                      color: _accent,
                      size: 20,
                    ),
                    SizedBox(width: 6),
                    TranslatedText(
                      'Show Nearby Places',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _centerOnNearbyUser,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: _accent.withOpacity(0.4), blurRadius: 14),
                ],
              ),
              child:
                  _nearbyIsLocating
                      ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(
                        Icons.my_location,
                        color: Colors.white,
                        size: 22,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyPlacePin extends StatelessWidget {
  final Place place;
  final bool selected;
  final double scale;

  const _NearbyPlacePin({
    required this.place,
    required this.selected,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final color = place.categories.first.color;
    final baseSize = selected ? 48.0 : 34.0;
    final size = baseSize * scale;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: (selected ? 3 : 2) * scale,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(selected ? 0.6 : 0.45),
            blurRadius: selected ? 12 : 8,
          ),
        ],
      ),
      child: Icon(
        place.categories.first.icon,
        color: Colors.white,
        size: (selected ? 22 : 17) * scale,
      ),
    );
  }
}

class _NearbyUserPin extends StatelessWidget {
  const _NearbyUserPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _ContributeScreenState._accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: _ContributeScreenState._accent.withOpacity(0.4),
            blurRadius: 10,
          ),
        ],
      ),
      child: const Icon(Icons.my_location, color: Colors.white, size: 20),
    );
  }
}

class _NearbyPlacesListSheet extends StatelessWidget {
  final List<Place> places;
  final Position? currentPosition;
  final VoidCallback onLocate;

  const _NearbyPlacesListSheet({
    required this.places,
    required this.currentPosition,
    required this.onLocate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.74,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F8FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Nearby places',
                    style: TextStyle(
                      color: Color(0xFF0F1D35),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (currentPosition == null)
                  GestureDetector(
                    onTap: onLocate,
                    child: const Text(
                      'Use my location',
                      style: TextStyle(
                        color: Color(0xFF2E7CF6),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (currentPosition != null)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                'Sorted nearest to farthest from you',
                style: TextStyle(color: Color(0xFF7A92B2), fontSize: 11),
              ),
            ),
          const Divider(height: 1, color: Color(0xFFD4E4F7)),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: places.length,
              itemBuilder: (context, index) {
                final place = places[index];
                final distanceKm =
                    currentPosition == null
                        ? null
                        : kmBetween(
                          LatLng(
                            currentPosition!.latitude,
                            currentPosition!.longitude,
                          ),
                          LatLng(place.lat, place.lng),
                        );
                return _NearbyPlaceListTile(
                  place: place,
                  distanceKm: distanceKm,
                  onTap: () => Navigator.of(context).pop(place),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyPlaceListTile extends StatelessWidget {
  final Place place;
  final double? distanceKm;
  final VoidCallback onTap;

  const _NearbyPlaceListTile({
    required this.place,
    required this.distanceKm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = place.categories.first.color;
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
                color: color.withOpacity(0.12),
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
                    style: const TextStyle(
                      color: Color(0xFF0F1D35),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${place.city} · ${place.categories.map((c) => c.label).join(', ')}',
                    style: const TextStyle(
                      color: Color(0xFF7A92B2),
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
                  color: const Color(0xFFEAF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  RouteMetricsService.formatDistance(distanceKm!),
                  style: const TextStyle(
                    color: Color(0xFF2E7CF6),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF7A92B2),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
