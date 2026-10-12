part of 'home_screen.dart';

extension _HomeScreenSections on _HomeScreenState {
  static const _surface = _HomeScreenState._surface;
  static const _accent = _HomeScreenState._accent;
  static const _accentSoft = _HomeScreenState._accentSoft;
  static const _textPrimary = _HomeScreenState._textPrimary;
  static const _textSecondary = _HomeScreenState._textSecondary;
  static const _border = _HomeScreenState._border;
  static const _danger = _HomeScreenState._danger;

  // ─── Header: name, quick tools, weather and "Where to?" ─────────────────────

  Widget _buildHeaderSection() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.buttonGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.directions_transit_filled,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TransitPH',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      TranslatedText(
                        'Your community transit guide',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(fontSize: 12, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fare matrix',
                  visualDensity: VisualDensity.compact,
                  onPressed: _showFareMatrixDialog,
                  icon: const Icon(
                    Icons.payments_outlined,
                    color: _textSecondary,
                  ),
                ),
                IconButton(
                  tooltip: 'Downloaded routes',
                  visualDensity: VisualDensity.compact,
                  onPressed: _openDownloadedRoutes,
                  icon: const Icon(
                    Icons.download_for_offline_outlined,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                if (_weatherData != null)
                  const WeatherChip()
                else if (!_isLoadingWeather)
                  _weatherButton(),
              ],
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: _surface,
                elevation: 2,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(26),
                child: InkWell(
                  onTap: widget.onOpenSearch,
                  borderRadius: BorderRadius.circular(26),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: _accent),
                        SizedBox(width: 12),
                        TranslatedText(
                          'Where to?',
                          style: TextStyle(fontSize: 16, color: _textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_totalUsers != null) ...[
              const SizedBox(height: 12),
              _activeUsersLine(_totalUsers!),
            ],
          ],
        ),
      ),
    );
  }

  /// Shown when the weather couldn't load (usually no location access).
  Widget _weatherButton() {
    return Tooltip(
      message: 'Turn on location to see the weather',
      child: ActionChip(
        onPressed: _enableWeather,
        avatar: const Icon(
          Icons.location_on_outlined,
          size: 16,
          color: _accent,
        ),
        label: const TranslatedText(
          'Weather',
          style: TextStyle(fontSize: 12, color: _accent),
        ),
        backgroundColor: _accentSoft,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// "1,234 commuters on TransitPH".
  Widget _activeUsersLine(int count) {
    final digits = count.toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          const Icon(Icons.people_outline_rounded, size: 16, color: _accent),
          const SizedBox(width: 6),
          Flexible(
            child: TranslatedText(
              '$grouped commuters on TransitPH',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStormWarningSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _danger.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: _danger, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: TranslatedText(
              'Storm warning: severe weather expected. Plan accordingly.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Recommended routes ──────────────────────────────────────────────────────

  Widget _buildRecommendationsSection() {
    if (_isLoadingRecommendations) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tagMatchedRoutes.isNotEmpty) ...[
          Row(
            children: [
              const Flexible(
                child: TranslatedText(
                  '🏷️ Routes Matching Your Tags',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 17,
                    color: _textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        _activePersonaTags
                            .map(
                              (tag) => Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentSoft,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _accent.withOpacity(0.2),
                                  ),
                                ),
                                child: TranslatedText(
                                  tag,
                                  style: const TextStyle(
                                    color: _accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tagMatchedRoutes.length,
              itemBuilder:
                  (context, index) =>
                      _buildRecommendationCardSection(_tagMatchedRoutes[index]),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (_recommendations['rushHourAlternatives']?.isNotEmpty == true)
          _buildRecommendationSection(
            '🚗 Rush Hour Alternatives',
            _recommendations['rushHourAlternatives']!,
          ),
        if (_recommendations['forYou']?.isNotEmpty == true)
          _buildRecommendationSection(
            '⭐ Recommended for You',
            _recommendations['forYou']!,
          ),
        if (_recommendations['popular']?.isNotEmpty == true)
          _buildRecommendationSection(
            '🔥 Popular Routes',
            _recommendations['popular']!,
          ),
      ],
    );
  }

  Widget _buildRecommendationCardSection(route_model.Route route) {
    final hasTransportSteps = route.steps.any((s) => s.mode != 'Walk');
    final hasActualFare =
        hasTransportSteps &&
        route.steps
            .where((s) => s.mode != 'Walk')
            .every((s) => s.actualFare != null);
    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TranslatedText(
                    '${route.startLocation} → ${route.endLocation}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: _textPrimary,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _routeIntegrityChip(route),
            const SizedBox(height: 6),
            TranslatedText(
              route.shortDescription,
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: _textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (route.audienceTags.isNotEmpty) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                      route.audienceTags
                          .take(3)
                          .map(
                            (tag) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _audienceTagChip(tag),
                            ),
                          )
                          .toList(),
                ),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                _statItem(
                  Icons.visibility_outlined,
                  '${route.views}',
                  _textSecondary,
                ),
                const SizedBox(width: 10),
                _statItem(
                  Icons.thumb_up_outlined,
                  '${route.upvotes}',
                  const Color(0xFF3EC97A),
                ),
                if (route.price != null) ...[
                  const SizedBox(width: 10),
                  _statItem(
                    Icons.payments_outlined,
                    route.price!,
                    const Color(0xFF3EC97A),
                  ),
                ],
                if (hasTransportSteps) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: TranslatedText(
                      hasActualFare ? 'Actual fare' : 'Estimated fare',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color:
                            hasActualFare
                                ? const Color(0xFF2D9F63)
                                : const Color(0xFFB8732F),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => MapTabController.openRoute(context, route),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B8FD6), Color(0xFF2BB5F0)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_outlined, color: Colors.white, size: 14),
                    SizedBox(width: 6),
                    Flexible(
                      child: TranslatedText(
                        'View Route',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationSection(
    String title,
    List<route_model.Route> routes,
  ) {
    if (routes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 17,
            color: _textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: routes.length > 5 ? 5 : routes.length,
            itemBuilder:
                (context, index) =>
                    _buildRecommendationCardSection(routes[index]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _statItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _audienceTagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _accent.withOpacity(0.2)),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          fontSize: 11,
          color: _accent,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _routeIntegrityChip(route_model.Route route) {
    return StreamBuilder<Map<String, int>>(
      stream: RouteService.watchRouteFeedbackSummary(route.id),
      builder: (context, snapshot) {
        final summary =
            snapshot.data ??
            const {
              'fareAccurateYes': 0,
              'fareAccurateNo': 0,
              'scheduleAccurateYes': 0,
              'scheduleAccurateNo': 0,
              'stillOperatingYes': 0,
              'stillOperatingNo': 0,
            };

        final trust = RouteTrustService.computeConfidence(
          route: route,
          feedbackSummary: summary,
        );
        final trustLabel = RouteTrustService.confidenceLabel(trust.total);
        final trustColor =
            trust.total >= 85
                ? const Color(0xFF2D9F63)
                : trust.total >= 65
                ? _accent
                : const Color(0xFFB8732F);

        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: trustColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: trustColor.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_outlined, size: 13, color: trustColor),
                const SizedBox(width: 5),
                Text(
                  'Integrity ${trust.total}/100 - $trustLabel',
                  style: TextStyle(
                    fontSize: 10,
                    color: trustColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
