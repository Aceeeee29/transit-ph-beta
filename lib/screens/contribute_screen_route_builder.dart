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

      if (orsDistM != null && orsDurS != null) {
        totalDistKm += orsDistM / 1000;
        totalDurS += orsDurS;
        totalFare +=
            steps[i].actualFare ??
            RouteMetricsService.calculateFareForMode(steps[i].mode, orsDistM / 1000);
      } else {
        final startIdx = (i == 0)
            ? 0
            : (i - 1 < stepBoundaries.length ? stepBoundaries[i - 1] : 0);
        final endIdx = (i < stepBoundaries.length)
            ? stepBoundaries[i]
            : pathPoints.length - 1;
        double segDistKm = 0;
        for (int j = startIdx; j < endIdx && j + 1 < pathPoints.length; j++) {
          segDistKm +=
              distCalc.as(LengthUnit.Kilometer, pathPoints[j], pathPoints[j + 1]);
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

    final startLoc = _startLocationController.text.isEmpty
        ? 'Start Point (${pathPoints.first.latitude.toStringAsFixed(4)}, ${pathPoints.first.longitude.toStringAsFixed(4)})'
        : _startLocationController.text;
    final endLoc = _endLocationController.text.isEmpty
        ? 'End Point (${pathPoints.last.latitude.toStringAsFixed(4)}, ${pathPoints.last.longitude.toStringAsFixed(4)})'
        : _endLocationController.text;
    final desc = _shortDescriptionController.text.isEmpty
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
          SnackBar(content: Text('Step $stepNo needs details for ${step.mode}.')),
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
            content: Text('Step $stepNo needs operating hours for ${step.mode}.'),
          ),
        );
        return false;
      }

      if (step.actualFare == null || step.actualFare! < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Step $stepNo needs a valid actual fare for ${step.mode}.'),
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
        const SnackBar(content: Text('Need at least start and end points on map')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit route: $e')),
        );
        return;
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) =>
            widget.routeToEdit != null
                ? const _SubmitSuccessDialog(isEdit: true)
                : _SubmitSuccessDialog(
                  isEdit: false,
                  quickCreateMode: _isQuickCreateMode,
                ),
      );

      if (widget.routeToEdit == null) {
        _resetAfterSubmitSuccess();
      }
    }
  }

  void _onPreviewRouteSection() {
    if (pathPoints.length < 2 || steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least start, end points and one step')),
      );
      return;
    }

    final route = _buildRoute();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoutePreview(
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
            child: const Icon(Icons.add_road_rounded, color: _accent, size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            widget.routeToEdit != null ? 'Edit Route' : 'Contribute a Route',
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
      actions: [
        if (selectionMode == 'done' && steps.isNotEmpty)
          GestureDetector(
            onTap: _toggleEditHandles,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _showEditHandles ? _accentSoft : _surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _showEditHandles ? _accent.withOpacity(0.35) : _border,
                ),
              ),
              child: Icon(
                _showEditHandles
                    ? Icons.edit_location_alt_rounded
                    : Icons.edit_location_alt_outlined,
                color: _showEditHandles ? _accent : _textSecondary,
                size: 18,
              ),
            ),
          ),
          GestureDetector(
            onTap: _showTutorialOverlay,
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.help_outline_rounded, color: _textSecondary, size: 18),
          ),
        ),
        if (selectionMode == 'done')
          GestureDetector(
            onTap: _onPreviewRoute,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withOpacity(0.3)),
              ),
              child: const Icon(Icons.preview_rounded, color: _accent, size: 18),
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

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(14.716, 121.032),
        initialZoom: 13.0,
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
            setState(() => _currentZoom = position.zoom);
            _revealZoomControls();
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app.transitph_beta',
        ),
        // PolygonLayer(polygons: _regionBoundaryPolygons), // TODO: re-enable once real boundary data is added
        PolylineLayer(polylines: polylines),
        if (_visiblePois.isNotEmpty)
          MarkerLayer(
            markers: _visiblePois.map((p) {
              return Marker(
                point: LatLng(p.latitude, p.longitude),
                child: Icon(
                  _ContributeScreenState._poiIcons[p.category],
                  color: _ContributeScreenState._poiColors[p.category],
                  size: 24,
                  shadows: const [Shadow(color: Colors.white, blurRadius: 3)],
                ),
              );
            }).toList(),
          ),
        MarkerLayer(
          markers: [
            if (pathPoints.isNotEmpty)
              Marker(
                point: pathPoints.first,
                child: const Icon(Icons.location_on, color: Colors.green, size: 40),
              ),
            if (pathPoints.length > 1)
              Marker(
                point: pathPoints.last,
                child: const Icon(Icons.flag, color: Colors.red, size: 40),
              ),
            if (_searchedLocation != null)
              Marker(
                point: _searchedLocation!,
                child: const Icon(Icons.my_location_rounded, color: _accent, size: 34),
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
      ],
    );
  }

  Widget _buildMapControlsOverlaySection() {
    double? totalOrsDistKm;
    int? totalOrsDurMinutes;

    if (_stepOrsDistM.isNotEmpty && _stepOrsDistM.every((d) => d != null)) {
      totalOrsDistKm = _stepOrsDistM.fold(0.0, (sum, d) => sum + (d ?? 0)) / 1000;
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
        onSnapToRoadToggled: _onSnapToRoadToggled,
        snapToRoadEnabled: _snapToRoadEnabled,
        orsDistanceKm: totalOrsDistKm,
        orsDurationMinutes: totalOrsDurMinutes,
      ),
    );
  }

  Widget _buildInstructionPillSection() {
    String text;
    switch (selectionMode) {
      case 'start':
        text = 'Tap on the map to select the starting point';
        break;
      case 'step':
        text = 'Tap to select next point for $currentMode';
        break;
      default:
        text = '';
    }

    return Positioned(
      bottom: 50,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _surface.withOpacity(0.96),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: _accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.touch_app_rounded, size: 13, color: _accent),
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
            ],
          ),
        ),
      ),
    );
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
          hint: const Text(
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
          items: philippineRegions.keys.map((region) {
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

  Widget _buildFormDrawerSection(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _isFormExpanded ? MediaQuery.of(context).size.height * 0.6 : 40,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: _border, width: 1.5)),
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
              if (_isFormExpanded) _buildFormContent(),
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
            Text(
              _isFormExpanded ? 'Hide Form' : 'Route Details',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
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
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          ),
        ),
      ),
    );
  }
}