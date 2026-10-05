part of 'contribute_screen.dart';

extension _ContributeScreenEditSections on _ContributeScreenState {
  Future<void> _openLocationSearchScreenSection() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ContributeLocationSearchScreen(
              initialQuery: _lastLocationSearchQuery,
            ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    // Tapped a live suggestion — coordinates included, no re-geocode needed.
    if (result is LocationSearchResult) {
      _onLocationPicked(result.latitude, result.longitude, result.name);
      return;
    }

    if (result is! String) return;
    final normalizedQuery = result.trim();
    if (normalizedQuery.isEmpty) {
      return;
    }

    setState(() => _lastLocationSearchQuery = normalizedQuery);

    final success = await _onLocationSearched(normalizedQuery);
    if (!mounted || success) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: TranslatedText(
          'Location not found. Try a more specific place.',
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  int _clampPathIndexSection(int index) {
    if (pathPoints.isEmpty) return 0;
    if (index < 0) return 0;
    if (index >= pathPoints.length) return pathPoints.length - 1;
    return index;
  }

  int _pickStepBodyHandleIndexSection(int startIdx, int endIdx) {
    final mid = startIdx + ((endIdx - startIdx) / 2).round();
    if (mid <= startIdx) return startIdx + 1;
    if (mid >= endIdx) return endIdx - 1;
    return mid;
  }

  /// Step [index]'s line split at its control points (derived along the
  /// line for steps saved without them).
  StepGeometry _stepGeometrySection(int index) =>
      StepGeometry.fromPath(_stepPath(index), _controlsForStep(index));

  _StepEditControls get _stepEditControlsSection {
    if (pathPoints.length < 2 || _stepCount == 0) {
      return _StepEditControls.empty();
    }

    final stepControlPoints = <List<LatLng>>[];
    final boundaryWaypoints = <LatLng>[];
    final viaHandles = <DraggableStepBodyHandle>[];
    final insertHandles = <DraggableStepBodyHandle>[];

    for (int i = 0; i < _stepCount; i++) {
      final geometry = _stepGeometrySection(i);
      final controls = geometry.controls;
      if (controls.isEmpty) continue;
      stepControlPoints.add(controls);
      if (i == 0) boundaryWaypoints.add(controls.first);
      boundaryWaypoints.add(controls.last);
      for (var k = 1; k < controls.length - 1; k++) {
        viaHandles.add(
          DraggableStepBodyHandle(
            stepIndex: i,
            controlIndex: k,
            point: controls[k],
          ),
        );
      }
      for (var k = 0; k < geometry.pieces.length; k++) {
        insertHandles.add(
          DraggableStepBodyHandle(
            stepIndex: i,
            controlIndex: k,
            point: geometry.pieceMidpoint(k),
          ),
        );
      }
    }

    return _StepEditControls(
      stepControlPoints: stepControlPoints,
      boundaryWaypoints: boundaryWaypoints,
      bodyHandles: viaHandles,
      insertHandles: insertHandles,
    );
  }

  /// Routes the pieces of step [index] in its own mode, with the current
  /// snap-to-road and expressway choices.
  PieceRouter _pieceRouterSection(int index) =>
      ContributeRouteEditService.pieceRouter(
        mode: _modeForStep(index),
        snapToRoadEnabled: _snapToRoadEnabled,
        allowExpressways: _expresswayOverride,
      );

  /// Replaces the geometry of the [changed] steps, keeping every other
  /// step's line exactly as it was, and saves the new control points.
  void _applyStepGeometriesSection(Map<int, StepGeometry> changed) {
    if (changed.isEmpty || !mounted) return;
    final newPath = <LatLng>[];
    final newBoundaries = <int>[];
    // The open step (if any) is drawn last and has no saved boundary.
    for (var i = 0; i < _stepCount; i++) {
      final stepPath = changed[i]?.path ?? _stepPath(i);
      if (stepPath.isEmpty) {
        if (i < steps.length) {
          newBoundaries.add(newPath.isEmpty ? 0 : newPath.length - 1);
        }
        continue;
      }
      if (newPath.isNotEmpty && newPath.last == stepPath.first) {
        newPath.addAll(stepPath.skip(1));
      } else {
        newPath.addAll(stepPath);
      }
      if (i < steps.length) newBoundaries.add(newPath.length - 1);
    }
    if (newPath.length < 2) return;

    setState(() {
      pathPoints = newPath;
      stepBoundaries = newBoundaries;
      for (final entry in changed.entries) {
        if (entry.key >= steps.length) {
          _openStepControls = entry.value.controls;
          continue;
        }
        steps[entry.key] = steps[entry.key].copyWith(
          controlPoints: entry.value.controls,
        );
        // Measured from the new line when the route is built.
        if (entry.key < _stepOrsDistM.length) _stepOrsDistM[entry.key] = null;
        if (entry.key < _stepOrsDurS.length) _stepOrsDurS[entry.key] = null;
      }
    });
    // History holds saved steps only; an open step's edits are undone
    // point by point instead.
    if (!_hasOpenStep) _saveToHistory();
  }

  /// Kept for deleting/reordering steps, which re-route from control points.
  Future<void> _rebuildFromStepControlsSection(
    List<List<LatLng>> stepControlPoints,
  ) async {
    if (steps.isEmpty || stepControlPoints.isEmpty) return;

    final rebuilt =
        await ContributeRouteEditService.rebuildFromStepControlPoints(
          steps: List<route_model.Step>.from(steps),
          stepControlPoints: stepControlPoints,
          snapToRoadEnabled: _snapToRoadEnabled,
          allowExpressways: _expresswayOverride,
          baseline: ContributionRouteBaseline(
            stepControlPoints: _stepEditControlsSection.stepControlPoints,
            pathPoints: List<LatLng>.from(pathPoints),
            stepBoundaries: List<int>.from(stepBoundaries),
            stepOrsDistM: List<double?>.from(_stepOrsDistM),
            stepOrsDurS: List<double?>.from(_stepOrsDurS),
          ),
        );

    if (!mounted ||
        rebuilt.pathPoints.length < 2 ||
        rebuilt.stepBoundaries.length != steps.length) {
      return;
    }

    setState(() {
      pathPoints = rebuilt.pathPoints;
      stepBoundaries = rebuilt.stepBoundaries;

      _stepOrsDistM
        ..clear()
        ..addAll(rebuilt.stepOrsDistM);
      _stepOrsDurS
        ..clear()
        ..addAll(rebuilt.stepOrsDurS);
    });
    _saveToHistory();
  }

  /// Boundary [index] is the start of step [index] and the end of step
  /// [index] - 1; moving it re-routes only the pieces touching it.
  Future<void> _onBoundaryWaypointDragEndSection(
    int index,
    LatLng updatedPoint,
  ) async {
    if (_stepCount == 0 || index < 0 || index > _stepCount) return;
    final changed = <int, StepGeometry>{};
    if (index > 0) {
      final before = _stepGeometrySection(index - 1);
      changed[index - 1] = await before.moveControl(
        before.controls.length - 1,
        updatedPoint,
        _pieceRouterSection(index - 1),
      );
    }
    if (index < _stepCount) {
      changed[index] = await _stepGeometrySection(
        index,
      ).moveControl(0, updatedPoint, _pieceRouterSection(index));
    }
    _applyStepGeometriesSection(changed);
  }

  Future<void> _onBodyHandleDragEndSection(
    int stepIndex,
    int controlIndex,
    LatLng updatedPoint,
  ) async {
    if (stepIndex < 0 || stepIndex >= _stepCount) return;
    final geometry = _stepGeometrySection(stepIndex);
    if (controlIndex <= 0 || controlIndex >= geometry.controls.length - 1) {
      return;
    }
    _applyStepGeometriesSection({
      stepIndex: await geometry.moveControl(
        controlIndex,
        updatedPoint,
        _pieceRouterSection(stepIndex),
      ),
    });
  }

  Future<void> _onViaPointLongPressSection(
    int stepIndex,
    int controlIndex,
  ) async {
    if (stepIndex < 0 || stepIndex >= _stepCount) return;
    final geometry = _stepGeometrySection(stepIndex);
    if (controlIndex <= 0 || controlIndex >= geometry.controls.length - 1) {
      return;
    }
    _applyStepGeometriesSection({
      stepIndex: await geometry.removeControl(
        controlIndex,
        _pieceRouterSection(stepIndex),
      ),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: TranslatedText('Point removed.'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _onInsertHandleDragEndSection(
    int stepIndex,
    int pieceIndex,
    LatLng point,
  ) async {
    if (stepIndex < 0 || stepIndex >= _stepCount) return;
    final geometry = _stepGeometrySection(stepIndex);
    if (pieceIndex < 0 || pieceIndex >= geometry.pieces.length) return;
    _applyStepGeometriesSection({
      stepIndex: await geometry.insertControl(
        pieceIndex,
        point,
        _pieceRouterSection(stepIndex),
      ),
    });
  }
}
