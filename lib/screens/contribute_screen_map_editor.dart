part of 'contribute_screen.dart';

extension _ContributeScreenEditSections on _ContributeScreenState {
  Future<void> _openLocationSearchScreenSection() async {
    final query = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ContributeLocationSearchScreen(
          initialQuery: _lastLocationSearchQuery,
        ),
      ),
    );

    if (!mounted || query == null) {
      return;
    }

    final normalizedQuery = query.trim();
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
        content: Text('Location not found. Try a more specific place.'),
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

  _StepEditControls get _stepEditControlsSection {
    if (pathPoints.length < 2 || steps.isEmpty) {
      return _StepEditControls.empty();
    }

    final stepControls = <List<LatLng>>[];
    final boundaryWaypoints = <LatLng>[pathPoints.first];
    final bodyHandles = <DraggableStepBodyHandle>[];

    for (int i = 0; i < steps.length; i++) {
      var safeStartIdx = _clampPathIndexSection(i == 0 ? 0 : stepBoundaries[i - 1]);
      var safeEndIdx = _clampPathIndexSection(
        i < stepBoundaries.length ? stepBoundaries[i] : pathPoints.length - 1,
      );

      if (safeEndIdx <= safeStartIdx) {
        if (safeStartIdx < pathPoints.length - 1) {
          safeEndIdx = safeStartIdx + 1;
        } else if (safeStartIdx > 0) {
          safeStartIdx = safeStartIdx - 1;
        }
      }

      final controlsForStep = <LatLng>[pathPoints[safeStartIdx]];

      if (safeEndIdx - safeStartIdx >= 2) {
        final bodyPathIndex = _pickStepBodyHandleIndexSection(safeStartIdx, safeEndIdx);
        if (bodyPathIndex > safeStartIdx && bodyPathIndex < safeEndIdx) {
          controlsForStep.add(pathPoints[bodyPathIndex]);
          bodyHandles.add(
            DraggableStepBodyHandle(
              stepIndex: i,
              controlIndex: controlsForStep.length - 1,
              point: pathPoints[bodyPathIndex],
            ),
          );
        }
      }

      controlsForStep.add(pathPoints[safeEndIdx]);
      stepControls.add(controlsForStep);
      boundaryWaypoints.add(pathPoints[safeEndIdx]);
    }

    return _StepEditControls(
      stepControlPoints: stepControls,
      boundaryWaypoints: boundaryWaypoints,
      bodyHandles: bodyHandles,
    );
  }

  Future<void> _rebuildFromStepControlsSection(
    List<List<LatLng>> stepControlPoints,
  ) async {
    if (steps.isEmpty || stepControlPoints.isEmpty) return;

    final rebuilt = await ContributeRouteEditService.rebuildFromStepControlPoints(
      steps: List<route_model.Step>.from(steps),
      stepControlPoints: stepControlPoints,
      snapToRoadEnabled: _snapToRoadEnabled,
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

  Future<void> _onBoundaryWaypointDragEndSection(
    int index,
    LatLng updatedPoint,
  ) async {
    if (steps.isEmpty) return;

    final stepControlPoints = _stepEditControlsSection.stepControlPoints
        .map((controls) => List<LatLng>.from(controls))
        .toList();

    if (stepControlPoints.length != steps.length) {
      return;
    }

    if (index < 0 || index > steps.length) {
      return;
    }

    if (index == 0) {
      stepControlPoints[0][0] = updatedPoint;
    } else if (index == steps.length) {
      final lastStep = stepControlPoints.length - 1;
      final lastControl = stepControlPoints[lastStep].length - 1;
      stepControlPoints[lastStep][lastControl] = updatedPoint;
    } else {
      final previousStep = index - 1;
      final previousLastControl = stepControlPoints[previousStep].length - 1;
      stepControlPoints[previousStep][previousLastControl] = updatedPoint;
      stepControlPoints[index][0] = updatedPoint;
    }

    await _rebuildFromStepControlsSection(stepControlPoints);
  }

  Future<void> _onBodyHandleDragEndSection(
    int stepIndex,
    int controlIndex,
    LatLng updatedPoint,
  ) async {
    if (steps.isEmpty) return;

    final stepControlPoints = _stepEditControlsSection.stepControlPoints
        .map((controls) => List<LatLng>.from(controls))
        .toList();

    if (stepIndex < 0 || stepIndex >= stepControlPoints.length) {
      return;
    }

    if (controlIndex <= 0 ||
        controlIndex >= stepControlPoints[stepIndex].length - 1) {
      return;
    }

    stepControlPoints[stepIndex][controlIndex] = updatedPoint;
    await _rebuildFromStepControlsSection(stepControlPoints);
  }
}
