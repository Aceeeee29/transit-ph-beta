part of 'contribute_screen.dart';

extension _ContributeScreenSections on _ContributeScreenState {
  static Color get _surface => _ContributeScreenState._surface;
  static Color get _surfaceAlt => _ContributeScreenState._surfaceAlt;
  static const _accent = _ContributeScreenState._accent;
  static Color get _accentSoft => _ContributeScreenState._accentSoft;
  static Color get _textPrimary => _ContributeScreenState._textPrimary;
  static Color get _textSecondary => _ContributeScreenState._textSecondary;
  static Color get _border => _ContributeScreenState._border;

  route_model.Route _buildRouteSection({String? existingId}) {
    double totalDurS = 0;
    double totalDistKm = 0;
    double totalFare = 0;
    final Distance distCalc = const Distance(roundResult: false);

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
      correctionOf: widget.correctionOf,
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

    // Typed by the rider, never filled in for them: a street address from
    // the map is rarely the name riders use for a terminal or landmark.
    if (_startLocationController.text.trim().isEmpty ||
        _endLocationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(
            'Type the starting and end locations in Basic Info first.',
          ),
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
      final isEdit = widget.routeToEdit != null;
      // An editor its opener already closed (the moderator's) is done.
      if (isEdit && !(ModalRoute.of(context)?.isCurrent ?? true)) return;

      await showDialog(
        context: context,
        builder:
            (_) =>
                isEdit
                    ? const _SubmitSuccessDialog(isEdit: true)
                    : _SubmitSuccessDialog(
                      isEdit: false,
                      quickCreateMode: _isQuickCreateMode,
                    ),
      );

      // An edit is done once it's sent for review: back to where it was
      // opened from.
      if (isEdit) {
        if (mounted) await Navigator.of(context).maybePop();
        return;
      }

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

  /// Distance · time · fare of what's drawn so far, e.g. "1.2 km · 14 min ·
  /// ₱14". Road-measured numbers once every step has them.
  String _routeMetricsLine() {
    final modes = steps.map((s) => s.mode).toList();
    final hasMeasuredDistance =
        _stepOrsDistM.isNotEmpty && _stepOrsDistM.every((d) => d != null);
    final distance = RouteMetricsService.formatDistance(
      hasMeasuredDistance
          ? _stepOrsDistM.fold(0.0, (sum, d) => sum + (d ?? 0)) / 1000
          : RouteMetricsService.calculateRouteDistance(pathPoints),
    );
    int minutes;
    if (_stepOrsDurS.isNotEmpty && _stepOrsDurS.every((d) => d != null)) {
      var seconds = _stepOrsDurS.fold(0.0, (sum, d) => sum + (d ?? 0));
      // About two minutes per transfer.
      if (steps.length > 1) seconds += (steps.length - 1) * 120;
      minutes = (seconds / 60).ceil();
    } else {
      minutes = RouteMetricsService.calculateEta(
        pathPoints,
        modes,
        stepBoundaries,
      );
    }
    final fare = RouteMetricsService.calculateFareEstimate(
      pathPoints,
      modes,
      stepBoundaries,
    ).replaceFirst('PHP ', '₱');
    return [
      distance,
      RouteMetricsService.formatEta(minutes),
      if (steps.isNotEmpty) fare,
    ].join(' · ');
  }

  /// The one drawing card above the drawer: what to do next, Finish, the
  /// route so far, undo/redo/clear, the snapping options and the modes.
  /// (Steps are listed and edited in the drawer.)
  Widget _buildDrawCardSection() {
    final drawing = selectionMode == 'step';
    final hasPoints = pathPoints.isNotEmpty;
    final String text =
        selectionMode == 'start'
            ? 'Tap on the map to select the starting point'
            : selectionMode == 'done'
            ? 'Route finished. Drag the dots to fix a line.'
            : _hasOpenStep
            ? 'Drawing a $_openStepMode step: tap to extend it, drag points '
                'or + to fix turns'
            : 'Tap to start the next $currentMode step';
    final canUndo = _hasOpenStep || _historyService.canUndo;
    final lineMode = _hasOpenStep ? _openStepMode : currentMode;

    // Above the drawer, and clear of the right-side buttons.
    return Positioned(
      bottom: _ContributeScreenState._drawerPeekHeight + 12,
      left: 12,
      right: _ContributeScreenState._sideButtonsInset,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TranslatedText(
                    text,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (drawing && steps.isNotEmpty && !_hasOpenStep) ...[
                  const SizedBox(width: 8),
                  _pillAction(
                    icon: Icons.check_rounded,
                    label: 'Finish (${steps.length})',
                    onTap: _onFinishRoutePressed,
                    primary: true,
                  ),
                ],
              ],
            ),
            if (hasPoints) ...[
              const SizedBox(height: 4),
              Text(
                _routeMetricsLine(),
                style: TextStyle(color: _textSecondary, fontSize: 12),
              ),
            ],
            if (_hasOpenStep) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _pillAction(
                    icon: Icons.close_rounded,
                    label: 'Discard',
                    onTap: _discardOpenStep,
                  ),
                  _pillAction(
                    icon: Icons.check_rounded,
                    label: 'Save step',
                    onTap: _saveOpenStep,
                    primary: true,
                  ),
                ],
              ),
            ],
            if (hasPoints) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _cardIconButton(
                    icon: Icons.undo_rounded,
                    tooltip: _hasOpenStep ? 'Undo point' : 'Undo',
                    onTap:
                        canUndo
                            ? (_hasOpenStep ? _undoOpenStepPoint : _onUndo)
                            : null,
                  ),
                  _cardIconButton(
                    icon: Icons.redo_rounded,
                    tooltip: 'Redo',
                    onTap:
                        !_hasOpenStep && _historyService.canRedo
                            ? _onRedo
                            : null,
                  ),
                  _cardIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Clear route',
                    onTap: _confirmClearRoute,
                    danger: true,
                  ),
                  _toggleChip(
                    icon: Icons.route_rounded,
                    label: 'Snap to road',
                    on: _snapToRoadEnabled,
                    onTap: () => _onSnapToRoadToggled(!_snapToRoadEnabled),
                    help:
                        'The line between the points you tap follows the '
                        'roads instead of going straight, also when you '
                        'drag the dots. Turn it off for off-road points '
                        '(ferry terminals, footpaths).',
                  ),
                  if (_snapToRoadEnabled && lineMode != 'Walk')
                    _toggleChip(
                      icon: Icons.add_road_rounded,
                      label: 'Expressways',
                      on: _allowExpressways,
                      onTap:
                          () => _setUiState(
                            () => _expresswayOverride = !_allowExpressways,
                          ),
                      help:
                          'Lets the road line use expressways (NLEX, '
                          'Skyway…). On by default for buses and FX/vans, '
                          'off for jeepneys and tricycles. Only affects how '
                          'new or dragged lines are snapped.',
                    ),
                ],
              ),
            ],
            if (drawing && !_hasOpenStep) ...[
              const SizedBox(height: 8),
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
                      // A new mode starts from its own expressway default.
                      onTap:
                          () => _setUiState(() {
                            currentMode = mode;
                            _expresswayOverride = null;
                          }),
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
                                fontWeight: FontWeight.w500,
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
    );
  }

  Future<void> _confirmClearRoute() async {
    final clear = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const TranslatedText('Clear this route?'),
            content: const TranslatedText(
              'All points and steps you drew will be removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const TranslatedText('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const TranslatedText('Clear'),
              ),
            ],
          ),
    );
    if (clear == true && mounted) _onReset();
  }

  Widget _cardIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final enabled = onTap != null;
    final color =
        !enabled
            ? _border
            : danger
            ? const Color(0xFFE05C6A)
            : _textPrimary;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _surfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: _border),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }

  /// An on/off option as a chip: filled when on. Long-press explains it.
  Widget _toggleChip({
    required IconData icon,
    required String label,
    required bool on,
    required VoidCallback onTap,
    required String help,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress:
          () => showDialog<void>(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: TranslatedText(label),
                  content: TranslatedText(help),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const TranslatedText('Got it'),
                    ),
                  ],
                ),
          ),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on ? _accentSoft : _surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? _accent.withValues(alpha: 0.5) : _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.check_rounded : icon,
              size: 14,
              color: on ? _accent : _textSecondary,
            ),
            const SizedBox(width: 4),
            TranslatedText(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: on ? _accent : _textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF3EC97A) : _surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primary ? const Color(0xFF3EC97A) : _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: primary ? Colors.white : _textPrimary),
            const SizedBox(width: 4),
            TranslatedText(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: primary ? Colors.white : _textPrimary,
              ),
            ),
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
            TranslatedText(
              'Route Steps',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
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
                  fontWeight: FontWeight.w500,
                  color: _accent,
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: TranslatedText(
                'Drag the dots on the map to fix a line',
                style: TextStyle(fontSize: 11, color: _textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < steps.length; i++) ...[
          _buildStepEditorTileSection(i),
          const SizedBox(height: 8),
        ],
        Divider(height: 8, color: _border),
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
                fontWeight: FontWeight.w500,
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
                Text(
                  _stepEditorSubtitle(step),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: _textSecondary),
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
    MapTabController.instance.toggleCategory(category);
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
    // Details live in the drawer, so bring it up to show them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MapDrawer.open(_drawerController);
    });
  }

  void _clearSelectedPlace() {
    _setUiState(() => _nearbySelectedPlace = null);
  }

  void _centerOnNearbyPlace(Place place) {
    _onNearbyPlaceTapped(place);
    final zoom = _currentZoom < 15 ? 15.0 : _currentZoom;
    _moveCamera(LatLng(place.lat, place.lng), zoom);
  }

  /// The GPS button: get a fresh fix, then center on it.
  Future<void> _centerOnNearbyUser() async {
    if (_nearbyIsLocating) return;
    await _tryGetNearbyLocation();
    final position = _nearbyPosition;
    if (!mounted || position == null) return;
    _moveCamera(LatLng(position.latitude, position.longitude), 16.0);
  }

  Widget _buildNearbyDebugCoordChip() {
    final coord = _debugCoord;
    if (coord == null) return const SizedBox.shrink();
    return Positioned(
      bottom: _ContributeScreenState._drawerPeekHeight + 12,
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
              style: TextStyle(
                color: _textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
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
              child: Icon(Icons.copy_rounded, color: _textSecondary, size: 14),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _setUiState(() => _debugCoord = null),
              child: Icon(Icons.close_rounded, color: _textSecondary, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}
