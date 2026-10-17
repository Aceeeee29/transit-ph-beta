part of 'route_map_screen.dart';

extension _RouteMapScreenSections on _RouteMapScreenState {
  static Color get _bg => _RouteMapScreenState._bg;
  static Color get _surface => _RouteMapScreenState._surface;
  static Color get _surfaceAlt => _RouteMapScreenState._surfaceAlt;
  static const _accent = _RouteMapScreenState._accent;
  static Color get _textPrimary => _RouteMapScreenState._textPrimary;
  static Color get _textSecondary => _RouteMapScreenState._textSecondary;
  static Color get _border => _RouteMapScreenState._border;
  static const _danger = _RouteMapScreenState._danger;
  static const _green = _RouteMapScreenState._green;

  Widget _buildStepTileSection(int idx, route_model.Step step) {
    final isCompleted = _isStepCompleted(idx);
    final modeColor =
        isCompleted ? _textSecondary : (modeColors[step.mode] ?? _accent);
    final instructionStyle = TextStyle(
      fontSize: 13,
      color: _textPrimary,
      height: 1.4,
    );
    final stepSchedule = _stepScheduleText(step);
    final altSuggestion = step.alternateRouteSuggestion?.trim();
    final isTransport = step.mode != 'Walk';
    final estimatedFare = isTransport ? _estimateStepFare(idx, step) : 0.0;
    final baseFareValue = step.actualFare ?? estimatedFare;
    final fareValue = _applyFareDiscount(baseFareValue, step.mode);
    // Only jeepneys and buses give the discount.
    final showsDiscount =
        _isDiscountFareEnabled && PhFareCalculator.givesDiscount(step.mode);
    final fareProfileLabel = FareDiscountToggle.defaultLabel;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isCompleted ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isCompleted ? _surfaceAlt : _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: modeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: modeColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      isCompleted
                          ? Icons.check_rounded
                          : _getModeIcon(step.mode),
                      color: modeColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      shape: BoxShape.circle,
                      border: Border.all(color: _border),
                    ),
                    child: Center(
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          step.mode,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: modeColor,
                          ),
                        ),
                        if (isCompleted) ...[
                          const SizedBox(width: 6),
                          const StepDoneLabel(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.instruction,
                      style:
                          isCompleted
                              ? StepDoneLabel.strike(instructionStyle)
                              : instructionStyle,
                    ),
                    if (step.details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        step.details,
                        style: TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (_boardingLabel(step) case final boarding?) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            step.usesDesignatedStops
                                ? Icons.place_rounded
                                : Icons.front_hand_outlined,
                            size: 13,
                            color: _textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TranslatedText(
                              boarding,
                              style: TextStyle(
                                fontSize: 11,
                                color: _textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (stepSchedule != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFE89A3C,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFFFFD9AE,
                            ).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'Schedule: $stepSchedule',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9A5A17),
                          ),
                        ),
                      ),
                    ],
                    if (altSuggestion != null && altSuggestion.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFD54F)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: Color(0xFF7A5800),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                altSuggestion,
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF7A5800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isTransport) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF8F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFB9E4C6)),
                        ),
                        // The regular fare is always shown; the discounted
                        // one is added when the discount toggle is on and
                        // the ride gives it.
                        child: Text(
                          'Fare: PHP ${baseFareValue.toStringAsFixed(0)} '
                          '(${step.actualFare != null ? 'actual' : 'estimated'})'
                          '${showsDiscount ? '\n$fareProfileLabel: PHP ${fareValue.toStringAsFixed(0)}' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF2D9F63),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showExitTrustFeedbackDialogSection() async {
    bool fare = _fareAccurate;
    bool schedule = _scheduleAccurate;
    bool operating = _stillOperating;

    Widget yesNoToggle({
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      Widget pill({
        required String label,
        required bool selected,
        required VoidCallback onTap,
      }) {
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? _accent.withValues(alpha: 0.12) : _surfaceAlt,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? _accent.withValues(alpha: 0.35) : _border,
              ),
            ),
            alignment: Alignment.center,
            child: TranslatedText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected ? _accent : _textSecondary,
              ),
            ),
          ),
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(label: 'Yes', selected: value, onTap: () => onChanged(true)),
          const SizedBox(width: 6),
          pill(label: 'No', selected: !value, onTap: () => onChanged(false)),
        ],
      );
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final score =
                _trustScore ??
                RouteTrustService.computeConfidence(
                  route: widget.route,
                  feedbackSummary: _feedbackSummary,
                );
            final trustLabel = RouteTrustService.confidenceLabel(score.total);
            final trustColor =
                score.total >= 85
                    ? _green
                    : score.total >= 65
                    ? _accent
                    : const Color(0xFFE89A3C);

            Widget questionRow({
              required String label,
              required bool value,
              required ValueChanged<bool> onChanged,
            }) {
              return Row(
                children: [
                  Flexible(
                    child: TranslatedText(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  yesNoToggle(
                    value: value,
                    onChanged: (v) => setDialogState(() => onChanged(v)),
                  ),
                ],
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const TranslatedText('Before You Go'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.verified_outlined,
                          size: 16,
                          color: trustColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: TranslatedText(
                            'Route confidence: ${score.total}/100 ($trustLabel)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: trustColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TranslatedText(
                      'Quick trust feedback helps other commuters (asked at most once every 30 days).',
                      style: TextStyle(
                        fontSize: 11,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    questionRow(
                      label: 'Fare accurate?',
                      value: fare,
                      onChanged: (v) => fare = v,
                    ),
                    const SizedBox(height: 10),
                    questionRow(
                      label: 'Schedule accurate?',
                      value: schedule,
                      onChanged: (v) => schedule = v,
                    ),
                    const SizedBox(height: 10),
                    questionRow(
                      label: 'Still operating?',
                      value: operating,
                      onChanged: (v) => operating = v,
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.end,
              actions: [
                TextButton(
                  onPressed:
                      () => Navigator.of(dialogContext).pop({
                        'action': 'dismiss',
                        'fareAccurate': fare,
                        'scheduleAccurate': schedule,
                        'stillOperating': operating,
                      }),
                  child: const TranslatedText('Dismiss'),
                ),
                TextButton(
                  onPressed:
                      () => Navigator.of(dialogContext).pop({
                        'action': 'skip_today',
                        'fareAccurate': fare,
                        'scheduleAccurate': schedule,
                        'stillOperating': operating,
                      }),
                  child: const TranslatedText('Skip for Today'),
                ),
                FilledButton(
                  onPressed:
                      () => Navigator.of(dialogContext).pop({
                        'action': 'submit',
                        'fareAccurate': fare,
                        'scheduleAccurate': schedule,
                        'stillOperating': operating,
                      }),
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  child: const TranslatedText('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyStateSection() {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          onPressed: _closeView,
          tooltip: 'Back to map',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Route Map',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 17,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.map_outlined, size: 36, color: _textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              'No route data available',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSectionSection(LatLng center) {
    // Place pins sit under the route, its stops and markers; the
    // traveler's dot on top of everything.
    return TransitMap(
      controller: _map,
      initialCenter: center,
      initialZoom: 10.0,
      minZoom: 5.0,
      maxZoom: 18.0,
      bounds: (
        southWest: const LatLng(4.5, 116.0),
        northEast: const LatLng(21.5, 127.0),
      ),
      // Zooming out stops at Metro Manila (with all of the route and the
      // traveler), as on the Map tab.
      keepInside: TransitMap.areaWith(TransitMap.metroManila, [
        ..._pathPoints,
        _displayPosition,
      ]),
      keepInsidePadding: const EdgeInsets.fromLTRB(
        16,
        120,
        16,
        _RouteMapScreenState._drawerPeekHeight + 16,
      ),
      places: _mapPlaces,
      lines: _lines,
      dots: _dots,
      icons: _icons,
      user: _mapUser,
      userHeading: _facing,
      onTap: (_) => _clearSelectedPlace(),
      onPlaceTap: _onPlaceTapped,
      onUserGesture: () {
        if (_isAutoFollowEnabled) _setAutoFollowEnabled(false);
      },
      onCameraIdle: _onMapCameraIdle,
      // Below the top bar and the chips.
      compassMargin: const math.Point(16, 130),
      attributionMargin: const math.Point(
        8,
        _RouteMapScreenState._drawerPeekHeight + 8,
      ),
    );
  }

  /// The old bottom info panel, now the drawer's content.
  List<Widget> _infoPanelChildren() {
    return [
      _buildMetricsRow(),
      if (_hasFareSteps) ...[
        const SizedBox(height: 10),
        FareDiscountToggle(
          value: _isDiscountFareEnabled,
          onChanged: _setDiscountEnabled,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textPrimary,
          ),
          iconColor: _textSecondary,
          iconSize: 16,
          activeColor: _accent,
        ),
      ],
      const SizedBox(height: 16),
      _buildSectionLabel('Route Steps (${widget.route.steps.length})'),
      ...widget.route.steps.asMap().entries.map(
        (e) => _buildStepTile(e.key, e.value),
      ),
      if (_routeReports.isNotEmpty) ...[
        const SizedBox(height: 6),
        _buildSectionLabel('Recent Reports'),
        ..._routeReports.map(_buildReportTile),
      ],
      const SizedBox(height: 16),
    ];
  }

  /// The route's length. Saved values of 0 (some routes were stored as
  /// "0 m" / "0") fall back to measuring the drawn path.
  String _routeDistanceLabel() {
    if (widget.route.distanceMeters != null &&
        widget.route.distanceMeters! > 0) {
      return RouteMetricsService.formatDistance(
        widget.route.distanceMeters! / 1000,
      );
    }
    final saved = widget.route.distance?.trim() ?? '';
    if (saved.isNotEmpty) {
      final parsedKm = RouteMetricsService.parseDistanceToKm(saved);
      if (parsedKm == null) return saved;
      if (parsedKm > 0) return RouteMetricsService.formatDistance(parsedKm);
    }
    return RouteMetricsService.formatDistance(
      RouteMetricsService.calculateRouteDistance(_pathPoints),
    );
  }

  Widget _buildMetricsRowSection() {
    final distanceValue = _routeDistanceLabel();
    // While following, both count down from where the traveler is.
    final remaining = _remainingTrip();
    final etaValue =
        remaining != null
            ? RouteMetricsService.formatEtaLabel(
              '${math.max(1, remaining.minutes)}',
            )
            : _routeEtaLabel();

    final scheduleText = _routeScheduleText();
    final trustScore = _trustScore;
    final trustLabel =
        trustScore != null
            ? RouteTrustService.confidenceLabel(trustScore.total)
            : 'Loading';
    final trustColor =
        trustScore == null
            ? _textSecondary
            : trustScore.total >= 85
            ? _green
            : trustScore.total >= 65
            ? _accent
            : const Color(0xFFE89A3C);
    final trustValue = trustScore != null ? '${trustScore.total}/100' : '--';

    final fareLabel = _routeFareLabel();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _metricCard(
            icon: Icons.straighten,
            iconColor: const Color(0xFF9B7FE8),
            label: remaining != null ? 'Remaining' : 'Distance',
            value:
                remaining != null
                    ? RouteMetricsService.formatDistance(
                      remaining.meters / 1000,
                    )
                    : distanceValue,
          ),
          if (etaValue != null) ...[
            const SizedBox(width: 10),
            _metricCard(
              icon: Icons.access_time_rounded,
              iconColor: _accent,
              label: 'ETA',
              value: etaValue,
            ),
          ],
          if (fareLabel != null) ...[
            const SizedBox(width: 10),
            _metricCard(
              icon: Icons.payments_outlined,
              iconColor: _green,
              label: _regularFareNote() ?? 'Fare',
              value: fareLabel,
            ),
          ],
          if (scheduleText != null) ...[
            const SizedBox(width: 10),
            _metricCard(
              icon: Icons.schedule_outlined,
              iconColor: const Color(0xFFE89A3C),
              label: 'Schedule',
              value: scheduleText,
            ),
          ],
          if (widget.enableRouteIntegrity) ...[
            const SizedBox(width: 10),
            _metricCard(
              icon: Icons.verified_user_outlined,
              iconColor: trustColor,
              label: 'Integrity ($trustLabel)',
              value: trustValue,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportTileSection(route_model.Report report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _danger.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                _getReportIcon(report.type),
                color: _danger,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.type,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                    ),
                  ),
                  if (report.description != null &&
                      report.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      report.description!,
                      style: TextStyle(fontSize: 12, color: _textSecondary),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 11, color: _textSecondary),
                      const SizedBox(width: 3),
                      Text(
                        _formatTime(report.timestamp),
                        style: TextStyle(fontSize: 11, color: _textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCardSection({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabelSection(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: _textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
