part of 'home_screen.dart';

extension _HomeScreenSections on _HomeScreenState {
  static const _bg = _HomeScreenState._bg;
  static const _surface = _HomeScreenState._surface;
  static const _surfaceAlt = _HomeScreenState._surfaceAlt;
  static const _accent = _HomeScreenState._accent;
  static const _accentSoft = _HomeScreenState._accentSoft;
  static const _textPrimary = _HomeScreenState._textPrimary;
  static const _textSecondary = _HomeScreenState._textSecondary;
  static const _border = _HomeScreenState._border;
  static const _danger = _HomeScreenState._danger;

  Widget _buildRouteCardSection(route_model.Route route, {double? cheapestFare}) {
    final hasTransportSteps = route.steps.any((s) => s.mode != 'Walk');
    final hasActualFare = hasTransportSteps &&
        route.steps.where((s) => s.mode != 'Walk').every((s) => s.actualFare != null);
    final estimatedFare = _routeEstimatedFare(route);
    final estimatedMins = _routeEstimatedMinutes(route);
    final possibleSavings = cheapestFare != null ? (estimatedFare - cheapestFare) : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RouteMapScreen(route: route)),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${route.startLocation} -> ${route.endLocation}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _routeIntegrityChip(route),
              const SizedBox(height: 8),
              Text(
                route.shortDescription,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (route.audienceTags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: route.audienceTags.take(4).map((tag) => _audienceTagChip(tag)).toList(),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: route.steps.map((step) => _modeChip(step.mode)).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _statItem(Icons.payments_outlined, 'PHP ${estimatedFare.toStringAsFixed(0)}', const Color(0xFF2D9F63)),
                  const SizedBox(width: 14),
                  _statItem(Icons.timer_outlined, '${estimatedMins} min', _textSecondary),
                ],
              ),
              if (possibleSavings > 0.9) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x143EC97A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'You save PHP ${possibleSavings.toStringAsFixed(0)} vs higher-fare options',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D9F63),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _statItem(Icons.visibility_outlined, '${route.views}', _textSecondary),
                    const SizedBox(width: 14),
                    _statItem(Icons.thumb_up_outlined, '${route.upvotes}', const Color(0xFF3EC97A)),
                    const SizedBox(width: 14),
                    _statItem(Icons.thumb_down_outlined, '${route.downvotes}', _danger),
                    if (route.eta != null) ...[
                      const SizedBox(width: 14),
                      _statItem(
                        Icons.schedule_outlined,
                        RouteMetricsService.formatEtaLabel(route.eta),
                        _textSecondary,
                      ),
                    ],
                    if (route.price != null) ...[
                      const SizedBox(width: 14),
                      _statItem(Icons.payments_outlined, route.price!, const Color(0xFF3EC97A)),
                    ],
                    if (hasTransportSteps) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasActualFare
                              ? const Color(0x143EC97A)
                              : const Color(0x14E89A3C),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          hasActualFare ? 'Actual' : 'Estimated',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: hasActualFare
                                ? const Color(0xFF2D9F63)
                                : const Color(0xFFB8732F),
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

  Widget _buildRecommendationCardSection(route_model.Route route) {
    final hasTransportSteps = route.steps.any((s) => s.mode != 'Walk');
    final hasActualFare = hasTransportSteps &&
        route.steps.where((s) => s.mode != 'Walk').every((s) => s.actualFare != null);
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
                  child: Text(
                    '${route.startLocation} → ${route.endLocation}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
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
            Text(
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
                  children: route.audienceTags
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
                _statItem(Icons.visibility_outlined, '${route.views}', _textSecondary),
                const SizedBox(width: 10),
                _statItem(Icons.thumb_up_outlined, '${route.upvotes}', const Color(0xFF3EC97A)),
                if (route.price != null) ...[
                  const SizedBox(width: 10),
                  _statItem(Icons.payments_outlined, route.price!, const Color(0xFF3EC97A)),
                ],
                if (hasTransportSteps) ...[
                  const SizedBox(width: 8),
                  Text(
                    hasActualFare ? 'Actual fare' : 'Estimated fare',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: hasActualFare
                          ? const Color(0xFF2D9F63)
                          : const Color(0xFFB8732F),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RouteMapScreen(route: route)),
              ),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
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
                    Text(
                      'View Route',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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

  Widget _buildHeaderSection() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.directions_transit_filled,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TransitPH',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Your community transit guide',
              style: TextStyle(fontSize: 12, color: _textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeatherSectionSection() {
    if (_isLoadingWeather) {
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
          ),
        ),
      );
    }

    if (_weatherData == null) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.wb_sunny_outlined,
                  color: Color(0xFFE89A3C),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_weatherData!.condition}  •  ${_weatherData!.temp}  •  💧 ${_weatherData!.humidity}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_weatherData!.isStorm) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _danger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _danger.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.warning_amber_outlined,
                    color: _danger,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Storm Warning: Severe weather expected. Plan accordingly.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchCardSection() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: TextField(
                      controller: _startController,
                      readOnly: true,
                      style: const TextStyle(color: _textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(
                          Icons.radio_button_checked,
                          color: Color(0xFF3EC97A),
                          size: 18,
                        ),
                        hintText: 'Starting from...',
                        hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 13,
                          horizontal: 4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isDetectingLocation ? null : _detectCurrentLocation,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isDetectingLocation ? _surfaceAlt : _accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isDetectingLocation
                            ? _border
                            : _accent.withOpacity(0.3),
                      ),
                    ),
                    child: _isDetectingLocation
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _accent,
                              ),
                            ),
                          )
                        : const Icon(Icons.my_location, color: _accent, size: 18),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
              child: Column(
                children: List.generate(
                  3,
                  (_) => Container(
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: const BoxDecoration(
                      color: _border,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchScreen(
                    routes: widget.routes,
                    onRefresh: widget.onRefresh,
                  ),
                ),
              ),
              child: AbsorbPointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: TextField(
                    controller: _destinationController,
                    style: const TextStyle(color: _textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.location_on,
                        color: _accent,
                        size: 18,
                      ),
                      hintText: 'Going to...',
                      hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _openDownloadedRoutes,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.download_for_offline_rounded,
                      size: 18,
                      color: _accent,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Open Offline Routes',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
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

  Widget _buildUserCountCardSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.people_alt_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_totalUsers!.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} commuters',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const Text(
                'Community members & counting',
                style: TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF3EC97A).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.circle, size: 7, color: Color(0xFF3EC97A)),
                SizedBox(width: 5),
                Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3EC97A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
              const Text(
                '🏷️ Routes Matching Your Tags',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: _textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _activePersonaTags
                        .map(
                          (tag) => Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _accentSoft,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: _accent.withOpacity(0.2)),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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
            height: 212,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tagMatchedRoutes.length,
              itemBuilder: (context, index) =>
                  _buildRecommendationCard(_tagMatchedRoutes[index]),
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

  Widget _buildCtaFooterSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.add_road, color: _accent, size: 20),
          ),
          const SizedBox(height: 10),
          const Text(
            'New to the area?',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Help build our database by contributing a route you know!',
            style: TextStyle(fontSize: 13, color: _textSecondary, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
