part of 'search_screen.dart';

extension _SearchScreenSections on _SearchScreenState {
  static const _surface = _SearchScreenState._surface;
  static const _surfaceAlt = _SearchScreenState._surfaceAlt;
  static const _accent = _SearchScreenState._accent;
  static const _accentSoft = _SearchScreenState._accentSoft;
  static const _textPrimary = _SearchScreenState._textPrimary;
  static const _textSecondary = _SearchScreenState._textSecondary;
  static const _border = _SearchScreenState._border;

  Widget _buildOrsResultCardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border.all(color: Colors.blue.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fallback auto-generated route from transit stop data. '
                  'Use community-verified routes first whenever available. '
                  'Distances and fares here are estimates.',
                  style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
                ),
              ),
            ],
          ),
        ),
        if (_routeAlternatives.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildAlternativesPanel(),
        ],
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.blue.shade200, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.route, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _searchController.text.trim(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _infoChip(
                      Icons.straighten,
                      _orsResult!.distanceLabel,
                      Colors.green,
                    ),
                    _infoChip(
                      Icons.timer_outlined,
                      _orsResult!.durationLabel,
                      Colors.orange,
                    ),
                    _infoChip(
                      Icons.payments_outlined,
                      _totalFareRange(),
                      Colors.green.shade700,
                    ),
                  ],
                ),
                if (_orsResult!.steps.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text(
                    'Route steps',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  ..._orsResult!.steps.take(6).map(
                    (step) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _stepModeIcon(step.suggestedMode),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _stepModeColor(step.suggestedMode),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    step.suggestedMode,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  step.instruction,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_orsResult!.steps.length > 6)
                    Text(
                      '+ ${_orsResult!.steps.length - 6} more steps',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OrsRouteMapScreen(
                    result: _orsResult!,
                    originName: _lastGeneratedOriginName ??
                        (_originController.text.trim().isEmpty
                            ? 'Current Location'
                            : _originController.text.trim()),
                    destinationName: _lastGeneratedDestinationName ??
                        _searchController.text.trim(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map, color: Colors.white),
            label: const Text(
              'View on Map',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _routeCardWithBadgeSection(route_model.Route route) {
    return SearchRouteCard(
      route: route,
      onTap: () => _onRouteTap(route),
      isVerified: route.isApproved,
    );
  }

  Widget _buildSearchBarSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: _surface,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 1.5),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              style: const TextStyle(color: _textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search destinations...',
                hintStyle: const TextStyle(color: _textSecondary, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _accent,
                  size: 20,
                ),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _onSearch('');
                          },
                          child: Container(
                            margin: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _border,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: _textSecondary,
                            ),
                          ),
                        )
                        : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 4,
                ),
              ),
              onChanged: _onSearch,
              onSubmitted: _onSearchSubmitted,
              onTap: _onSearchFocus,
            ),
          ),
          if (_showOmnibox && _suggestions.isNotEmpty) _buildOmnibox(),
        ],
      ),
    );
  }

  Widget _buildOmniboxSection() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _suggestions.length,
        separatorBuilder: (_, index) => Divider(color: _border, height: 1),
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          final isRecent = _recentSearches.contains(suggestion);
          return InkWell(
            onTap: () => _onSuggestionTap(suggestion),
            borderRadius: BorderRadius.vertical(
              top: index == 0 ? const Radius.circular(14) : Radius.zero,
              bottom:
                  index == _suggestions.length - 1
                      ? const Radius.circular(14)
                      : Radius.zero,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isRecent ? _surfaceAlt : _accentSoft,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      isRecent ? Icons.history_rounded : Icons.search_rounded,
                      size: 14,
                      color: isRecent ? _textSecondary : _accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(Icons.north_west, size: 13, color: _textSecondary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResultsSection() {
    if (_filteredRoutes.isNotEmpty) {
      final sortedRoutes = _sortContributedRoutes(
        _filteredRoutes,
        _contributedSortMode,
      );
      final topPicks = _topThreeModePicks(_filteredRoutes);

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildGenerateRouteOptionCard(),
          const SizedBox(height: 12),
          if (_isLoadingOrs) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ] else if (_orsResult != null) ...[
            _buildOrsResultCard(),
            const SizedBox(height: 12),
          ] else if (_orsError) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _orsErrorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ),
          ],
          _buildContributedFilterRow(),
          const SizedBox(height: 10),
          if (topPicks.isNotEmpty) ...[
            _buildTopPicksCard(topPicks),
            const SizedBox(height: 12),
          ],
          ...sortedRoutes.map(_routeCardWithBadge),
        ],
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_isLoadingOrs) ...[
            const SizedBox(height: 60),
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Finding your route…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ] else if (_orsResult != null) ...[
            _buildOrsResultCard(),
          ] else ...[
            _buildOrsEmptyState(),
          ],
        ],
      ),
    );
  }

  Widget _buildGenerateRouteOptionCardSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Community routes found',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.blue.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Need another option? You can still generate a fallback route from transit stop data.',
            style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
          ),
          const SizedBox(height: 10),
          _buildOriginSelector(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoadingOrs ? null : _onGenerateRoutePressed,
              icon: const Icon(Icons.map_outlined, color: Colors.white),
              label: const Text(
                'Generate Route Anyway',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContributedFilterRowSection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _sortFilterChip(
          label: 'Balanced',
          active: _contributedSortMode == ContributedRouteSortMode.balanced,
          onTap: () => _setContributedSortMode(ContributedRouteSortMode.balanced),
        ),
        _sortFilterChip(
          label: 'Budget',
          active: _contributedSortMode == ContributedRouteSortMode.budget,
          onTap: () => _setContributedSortMode(ContributedRouteSortMode.budget),
        ),
        _sortFilterChip(
          label: 'Fastest',
          active: _contributedSortMode == ContributedRouteSortMode.fastest,
          onTap: () => _setContributedSortMode(ContributedRouteSortMode.fastest),
        ),
      ],
    );
  }

  Widget _sortFilterChipSection({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _accentSoft : _surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? _accent.withValues(alpha: 0.35) : _border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? _accent : _textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTopPicksCardSection(List<route_model.Route> topPicks) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top route picks',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Best picks for Balanced, Budget, and Fastest based on available contributed routes.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          ...topPicks.asMap().entries.map((entry) {
            final route = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _onRouteTap(route),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${route.startLocation} to ${route.endLocation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'PHP ${_routeEstimatedFare(route).toStringAsFixed(0)} • ${_routeEstimatedMinutes(route)} min',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAlternativesPanelSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top ${_routeAlternatives.length} alternatives',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Best picks for Balanced, Fastest, and Budget from GTFS alternatives.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          ..._routeAlternatives.asMap().entries.map((entry) {
            final index = entry.key;
            final alt = entry.value;
            final selected = index == _selectedAlternativeIndex;
            final fallbackRoute = _fallbackAlternativeRoutes[index];
            final displayFare =
                fallbackRoute == null
                    ? alt.estimatedFarePhp
                    : fallbackRoute.steps.fold<double>(
                      0.0,
                      (sum, s) => sum + s.estimatedFare,
                    );
            final displayTimeMinutes =
                fallbackRoute == null
                    ? alt.estimatedTimeMinutes
                    : fallbackRoute.durationSeconds / 60.0;

            final tags = <String>[];
            final optionLabel = _alternativeLabels[index];
            if (optionLabel != null && optionLabel.isNotEmpty) {
              tags.add(optionLabel);
            }
            if (fallbackRoute != null) {
              tags.add('Walk Fallback');
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _selectAlternative(index),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.blue.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          selected
                              ? Colors.blue.shade400
                              : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Option ${index + 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Fare: PHP ${displayFare.toStringAsFixed(0)} • Time: ${displayTimeMinutes.toStringAsFixed(0)} min',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                tags.join(' • '),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle,
                          color: Colors.blue.shade700,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOrsEmptyStateSection() {
    return Column(
      children: [
        const SizedBox(height: 32),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _surfaceAlt,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.search_off_rounded,
            size: 36,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'No community routes found',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'You can use this as substitute but be aware that this might not be the best route / it is possibly outdated.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _textSecondary),
        ),
        const SizedBox(height: 24),
        _buildOriginSelector(),
        const SizedBox(height: 16),
        if (_orsError)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _orsErrorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isLoadingOrs ? null : _onGenerateRoutePressed,
            icon: const Icon(Icons.map_outlined, color: Colors.white),
            label: const Text(
              'Generate Route',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOriginSelectorSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Starting point',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _originToggleBtn(
                label: 'My location',
                icon: Icons.my_location,
                active: _useCurrentLocation,
                onTap: _setOriginUseCurrentLocation,
              ),
              const SizedBox(width: 8),
              _originToggleBtn(
                label: 'Enter address',
                icon: Icons.edit_location_alt_outlined,
                active: !_useCurrentLocation,
                onTap: _setOriginUseManualAddress,
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState:
                _useCurrentLocation
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _originController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Quezon City Hall, EDSA Cubao...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                        prefixIcon: Icon(
                          Icons.location_on_outlined,
                          color: Colors.blue.shade600,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed:
                        _isDetectingLocation ? null : _detectAndFillOrigin,
                    icon:
                        _isDetectingLocation
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.my_location, size: 18),
                    tooltip: 'Use GPS location',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _originToggleBtnSection({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.blue.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? Colors.blue.shade700 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
