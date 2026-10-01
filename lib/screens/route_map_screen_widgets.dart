part of 'route_map_screen.dart';

extension _RouteMapScreenSections on _RouteMapScreenState {
  static const _bg = _RouteMapScreenState._bg;
  static const _surface = _RouteMapScreenState._surface;
  static const _surfaceAlt = _RouteMapScreenState._surfaceAlt;
  static const _accent = _RouteMapScreenState._accent;
  static const _textPrimary = _RouteMapScreenState._textPrimary;
  static const _textSecondary = _RouteMapScreenState._textSecondary;
  static const _border = _RouteMapScreenState._border;
  static const _danger = _RouteMapScreenState._danger;
  static const _green = _RouteMapScreenState._green;

  AppBar _buildAppBarSection() {
    return AppBar(
      backgroundColor: _surface,
      foregroundColor: _textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _surfaceAlt,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _border),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            size: 15,
            color: _textSecondary,
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.route.startLocation,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: [
              const Icon(Icons.arrow_forward, size: 11, color: _textSecondary),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  widget.route.endLocation,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.showDownloadButton)
          GestureDetector(
            onTap:
                (_isDownloadingRoute || _isRouteDownloaded)
                    ? null
                    : _downloadRouteForOffline,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color:
                    _isRouteDownloaded
                        ? _green.withValues(alpha: 0.12)
                        : _accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      _isRouteDownloaded
                          ? _green.withValues(alpha: 0.35)
                          : _accent.withValues(alpha: 0.3),
                ),
              ),
              child:
                  _isDownloadingRoute
                      ? const Padding(
                        padding: EdgeInsets.all(8.5),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Icon(
                        _isRouteDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_rounded,
                        color: _isRouteDownloaded ? _green : _accent,
                        size: 18,
                      ),
            ),
          ),
        _VoteButton(
          icon: Icons.arrow_upward_rounded,
          count: widget.route.upvotes,
          active: _userVote == true,
          activeColor: _green,
          onTap: _isApplyingVote ? null : () => _vote(true),
        ),
        _VoteButton(
          icon: Icons.arrow_downward_rounded,
          count: widget.route.downvotes,
          active: _userVote == false,
          activeColor: _danger,
          onTap: _isApplyingVote ? null : () => _vote(false),
        ),
        GestureDetector(
          onTap: _showReportDialog,
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _danger.withValues(alpha: 0.25)),
            ),
            child: const Icon(
              Icons.report_problem_outlined,
              color: _danger,
              size: 17,
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  Widget _buildStepTileSection(int idx, route_model.Step step) {
    final isCompleted = _isStepCompleted(idx);
    final modeColor =
        isCompleted ? _textSecondary : (modeColors[step.mode] ?? _accent);
    final scheduleView = ScheduleWindowService.findStepView(
      _scheduleSnapshot,
      idx,
    );
    final stepSchedule = scheduleView?.displayText ?? _stepScheduleText(step);
    final altSuggestion = step.alternateRouteSuggestion?.trim();
    final isTransport = step.mode != 'Walk';
    final estimatedFare = isTransport ? _estimateStepFare(idx, step) : 0.0;
    final baseFareValue = step.actualFare ?? estimatedFare;
    final fareValue = _applyFareDiscount(baseFareValue);
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
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
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
                    Text(
                      step.mode,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: modeColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.instruction,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _textPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (step.details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        step.details,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
                          height: 1.4,
                        ),
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
                          color: (scheduleView != null
                                  ? _scheduleStateColor(scheduleView.state)
                                  : const Color(0xFFE89A3C))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (scheduleView != null
                                    ? _scheduleStateColor(scheduleView.state)
                                    : const Color(0xFFFFD9AE))
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          scheduleView == null
                              ? 'Schedule: $stepSchedule'
                              : stepSchedule,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color:
                                scheduleView != null
                                    ? _scheduleStateColor(scheduleView.state)
                                    : const Color(0xFF9A5A17),
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
                                  fontWeight: FontWeight.w600,
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
                        child: Text(
                          _isDiscountFareEnabled
                              ? 'Fare ($fareProfileLabel): PHP ${fareValue.toStringAsFixed(0)} '
                                  '(${step.actualFare != null ? 'actual' : 'estimated'})'
                              : 'Fare: PHP ${fareValue.toStringAsFixed(0)} '
                                  '(${step.actualFare != null ? 'actual' : 'estimated'})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
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
                fontWeight: FontWeight.w700,
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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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
                              fontWeight: FontWeight.w700,
                              color: trustColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const TranslatedText(
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
        title: const Text(
          'Route Map',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
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
              child: const Icon(
                Icons.map_outlined,
                size: 36,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No route data available',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSectionSection(LatLng center) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 10.0,
            minZoom: 5.0,
            maxZoom: 18.0,
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && _isAutoFollowEnabled) {
                _setAutoFollowEnabled(false);
              }
            },
            cameraConstraint: CameraConstraint.contain(
              bounds: LatLngBounds(
                const LatLng(4.5, 116.0),
                const LatLng(21.5, 127.0),
              ),
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.app.transitph_beta',
            ),
            if (_offlineTileTemplate != null)
              TileLayer(
                urlTemplate: _offlineTileTemplate!,
                tileProvider: FileTileProvider(),
              ),
            // Markers after the route so the user's arrow sits on top of it.
            PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
            _userLocationLayer,
          ],
        ),
        Positioned(top: 12, right: 12, child: _buildMapLegend()),
        if (_guidance.kind != FollowGuidanceKind.none)
          Positioned(
            left: 12,
            right: 64,
            bottom: 64,
            child: FollowGuidanceCard(
              guidance: _guidance,
              remainingMeters:
                  ActiveNavigationService.instance.connectorRemainingMeters,
              isRerouting: ActiveNavigationService.instance.isRerouting,
              routeStartLabel: widget.route.startLocation,
            ),
          ),
        Positioned(bottom: 12, left: 12, child: _buildStartControl()),
        if (kDebugMode && _isNavigationStarted && !_hasArrived)
          Positioned(
            bottom: 64,
            right: 12,
            child: FollowSimulatorButton(path: _pathPoints),
          ),
        Positioned(bottom: 12, right: 12, child: _buildCenterButton()),
      ],
    );
  }

  Widget _buildInfoPanelSection() {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border, width: 1.5)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
              iconColor: _textSecondary,
              iconSize: 16,
              activeColor: _accent,
            ),
          ],
          if (_scheduleSnapshot != null) ...[
            const SizedBox(height: 10),
            _buildScheduleSummaryChip(),
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
        ],
      ),
    );
  }

  Widget _buildScheduleSummaryChipSection() {
    final snapshot = _scheduleSnapshot;
    if (snapshot == null) return const SizedBox.shrink();

    final color = _scheduleStateColor(snapshot.state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.timelapse_rounded, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              snapshot.summaryText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRowSection() {
    // Saved values of 0 (some routes were stored as "0 m" / "0") fall back
    // to measuring the drawn path.
    final distanceValue = () {
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
    }();
    final etaValue = _routeEtaLabel();

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
            label: 'Distance',
            value: distanceValue,
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
              label: 'Fare',
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  if (report.description != null &&
                      report.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      report.description!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 11,
                        color: _textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _formatTime(report.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: _textSecondary,
                        ),
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
                style: const TextStyle(
                  fontSize: 11,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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
        style: const TextStyle(
          color: _textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
