part of 'contribute_screen.dart';

/// The rider's own drawing, put aside while the tour shows its example
/// route in the same controls and put back when the tour closes.
class _TourSnapshot {
  final List<LatLng> pathPoints;
  final List<route_model.Step> steps;
  final List<int> stepBoundaries;
  final List<double?> stepOrsDistM;
  final List<double?> stepOrsDurS;
  final List<LatLng> openStepControls;
  final String openStepMode;
  final String currentMode;
  final String selectionMode;
  final bool? expresswayOverride;

  _TourSnapshot(_ContributeScreenState s)
    : pathPoints = List.of(s.pathPoints),
      steps = List.of(s.steps),
      stepBoundaries = List.of(s.stepBoundaries),
      stepOrsDistM = List.of(s._stepOrsDistM),
      stepOrsDurS = List.of(s._stepOrsDurS),
      openStepControls = List.of(s._openStepControls),
      openStepMode = s._openStepMode,
      currentMode = s.currentMode,
      selectionMode = s.selectionMode,
      expresswayOverride = s._expresswayOverride;

  void restoreInto(_ContributeScreenState s) {
    s.pathPoints = pathPoints;
    s.steps = steps;
    s.stepBoundaries = stepBoundaries;
    s._stepOrsDistM = stepOrsDistM;
    s._stepOrsDurS = stepOrsDurS;
    s._openStepControls = openStepControls;
    s._openStepMode = openStepMode;
    s.currentMode = currentMode;
    s.selectionMode = selectionMode;
    s._expresswayOverride = expresswayOverride;
  }
}

/// The Contribute tour: lights up each part of the drawing screen in turn
/// and explains it. Most controls only show once something is drawn, so
/// the tour draws the example route (Monumento → Fatima) in the rider's
/// place for its duration.
extension _ContributeScreenTour on _ContributeScreenState {
  void _startTour() {
    if (_showTutorial) return;
    _tourSnapshot ??= _TourSnapshot(this);
    if (_drawerController.isAttached) _drawerController.reset();
    _setUiState(() => _showTutorial = true);
    final example = TutorialService.getExampleRoute();
    // Bottom: the drawer's peek plus the drawing card at its tallest
    // (vehicle chips showing), so the whole example stays in view.
    _map.fitPoints(
      example.pathPoints,
      padding: const EdgeInsets.fromLTRB(
        48,
        150,
        48 + _ContributeScreenState._sideButtonsInset,
        _ContributeScreenState._drawerPeekHeight + 250,
      ),
    );
  }

  /// The example route, either between steps (vehicle chips and Finish
  /// showing) or with its jeepney ride still being drawn (Save step, Undo,
  /// Snap to road and Expressways showing; Expressways hides for a walk).
  void _tourShowExample({required bool drawingStep}) {
    final example = TutorialService.getExampleRoute();
    final all = example.steps;
    _setUiState(() {
      selectionMode = 'step';
      _stepOrsDistM = [];
      _stepOrsDurS = [];
      _expresswayOverride = null;
      if (drawingStep) {
        // Walk saved, jeepney open, the last walk not drawn yet.
        final rideEnd = example.stepBoundaries[1];
        pathPoints = example.pathPoints.sublist(0, rideEnd + 1);
        steps = [all[0]];
        stepBoundaries = [example.stepBoundaries[0]];
        _openStepControls = List.of(all[1].controlPoints);
        _openStepMode = all[1].mode;
        currentMode = all[1].mode;
      } else {
        pathPoints = List.of(example.pathPoints);
        steps = List.of(all);
        stepBoundaries = List.of(example.stepBoundaries);
        _openStepControls = [];
        currentMode = 'Jeepney';
      }
    });
  }

  /// The rider's own map again, under the tour's last card.
  void _tourShowOwnMap() {
    final snapshot = _tourSnapshot;
    if (snapshot == null) return;
    _setUiState(() => snapshot.restoreInto(this));
  }

  void _endTour() {
    final snapshot = _tourSnapshot;
    _tourSnapshot = null;
    // Hide first: the save is a Firestore write that only completes once
    // the server answers (never while offline).
    _setUiState(() {
      _showTutorial = false;
      snapshot?.restoreInto(this);
    });
    // Leave the map tappable: an open drawer covers most of it.
    if (_drawerController.isAttached) _drawerController.reset();
    if (snapshot != null && snapshot.pathPoints.isNotEmpty) {
      _map.fitPoints(
        snapshot.pathPoints,
        padding: const EdgeInsets.fromLTRB(
          48,
          140,
          48,
          _ContributeScreenState._drawerPeekHeight + 48,
        ),
      );
    }
    unawaited(TutorialService.markContributeTutorialAsSeen());
  }

  /// The map between the search bar and the drawing card.
  Rect? _tourMapArea(RenderBox overlay) {
    final top = SpotlightTutorial.rectOf(_tourTopBarKey, overlay);
    final card = SpotlightTutorial.rectOf(_tourCardKey, overlay);
    if (top == null || card == null) return null;
    final bottom = card.top - 12;
    if (bottom - top.bottom < 80) return null;
    return Rect.fromLTRB(
      12,
      top.bottom + 8,
      overlay.size.width - _ContributeScreenState._sideButtonsInset,
      bottom,
    );
  }

  /// The drawer's peek: its handle and header, full width.
  Rect? _tourDrawerArea(RenderBox overlay) {
    final header = SpotlightTutorial.rectOf(_tourDrawerKey, overlay);
    if (header == null) return null;
    // The header can run past the bottom edge while the drawer is lowered.
    final bottom = header.bottom + 6;
    final limit = overlay.size.height - 2;
    return Rect.fromLTRB(
      4,
      header.top - 18,
      overlay.size.width - 4,
      bottom < limit ? bottom : limit,
    );
  }

  List<SpotlightStep> _contributeTourSteps() {
    void between() => _tourShowExample(drawingStep: false);
    void drawing() => _tourShowExample(drawingStep: true);
    return [
      SpotlightStep(
        title: 'Share how you commute',
        body:
            'This tour shows every part of the Contribute map. To show them '
            'all, we drew an example route (LRT-1 Monumento to Fatima '
            'University). Your own map comes back when the tour ends.',
        onShow: between,
      ),
      SpotlightStep(
        title: 'Find where to start',
        body:
            'Search a place to jump the map there before you draw. The back '
            'arrow leaves Contribute; what you drew is kept for later. The ? '
            'button plays this tour again.',
        target: _tourSearchKey,
        onShow: between,
      ),
      SpotlightStep(
        title: 'Tap where riders begin',
        body:
            'Your first tap on the map is the start of the route. Every step '
            'after that starts where the one before it ended, so a trip '
            'stays one connected line.',
        area: _tourMapArea,
        onShow: between,
      ),
      SpotlightStep(
        title: 'Pick the vehicle first',
        body:
            'Choose how this part of the trip is done before you tap: '
            'Jeepney, Bus, Train, Tricycle, FX/Van, Walk or Ferry. Each '
            'vehicle draws in its own color, so riders see where to transfer.',
        target: _tourModesKey,
        onShow: between,
      ),
      SpotlightStep(
        title: 'Draw along the road',
        body:
            'Keep tapping along the street the vehicle takes. Between taps '
            'the line follows the road for you. Drag a dot to fix a turn, '
            'or tap + on the line to add a bend.',
        area: _tourMapArea,
        onShow: drawing,
      ),
      SpotlightStep(
        title: 'Drawing tools',
        body: 'Long-press Snap to road or Expressways to see what they do.',
        points: const [
          SpotlightPoint(
            Icons.undo_rounded,
            'Undo',
            'Takes back the last point you tapped.',
          ),
          SpotlightPoint(
            Icons.redo_rounded,
            'Redo',
            'Puts back what Undo took away.',
          ),
          SpotlightPoint(
            Icons.delete_outline_rounded,
            'Clear',
            'Removes the whole drawing. It asks first.',
          ),
          SpotlightPoint(
            Icons.route_rounded,
            'Snap to road',
            'The line follows the roads. Turn it off for footpaths, ferry '
                'terminals and other places off the road.',
          ),
          SpotlightPoint(
            Icons.add_road_rounded,
            'Expressways',
            'Lets the line use NLEX, Skyway and other expressways. On for '
                'buses and FX/vans, off for jeepneys and tricycles.',
          ),
        ],
        target: _tourToolsKey,
        onShow: drawing,
      ),
      SpotlightStep(
        title: 'Save the step',
        body:
            'When the line reaches where riders get off, press Save step. '
            'It asks what riders do there: the instruction ("Ride a jeep '
            'with a Malinta signboard"), details, the fare, the operating '
            'hours, and whether riders board anywhere along it or only at '
            'stops. Discard drops just this step.',
        target: _tourSaveKey,
        onShow: drawing,
      ),
      SpotlightStep(
        title: 'Next ride, then Finish',
        body:
            'Changing vehicles? Pick the next one and tap to draw the next '
            'step from where this one ended. When the whole trip is drawn, '
            'press Finish. The number counts your steps.',
        target: _tourFinishKey,
        onShow: between,
      ),
      SpotlightStep(
        title: 'Steps and route details',
        body:
            'Pull this drawer up to see every step. Tap one to change its '
            'instruction, fare or stops. Below the steps, fill in where the '
            'route starts and ends, who it is for (tags) and a short '
            'description, then send it. A moderator checks every new route '
            'before everyone can see it.',
        area: _tourDrawerArea,
        onShow: between,
      ),
      SpotlightStep(
        title: 'Map buttons',
        body: 'These work the same while you browse and while you draw.',
        points: const [
          SpotlightPoint(
            Icons.view_in_ar_rounded,
            '3D view',
            'Tilts the map to show buildings, or back to flat.',
          ),
          SpotlightPoint(
            Icons.location_on_rounded,
            'Pins',
            'Shows or hides the place pins, so you can see the roads.',
          ),
          SpotlightPoint(
            Icons.my_location_rounded,
            'My location',
            'Moves the map to where you are.',
          ),
        ],
        target: _tourSideKey,
        onShow: between,
      ),
      SpotlightStep(
        title: "You're ready",
        body:
            'Start with a trip you know well, like your ride to school or '
            'work. Your map is back the way you left it.',
        onShow: _tourShowOwnMap,
      ),
    ];
  }
}
