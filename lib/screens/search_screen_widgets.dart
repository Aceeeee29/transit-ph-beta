part of 'search_screen.dart';

extension _SearchScreenSections on _SearchScreenState {
  static const _surface = _SearchScreenState._surface;
  static const _accent = _SearchScreenState._accent;
  static const _textPrimary = _SearchScreenState._textPrimary;
  static const _textSecondary = _SearchScreenState._textSecondary;

  // ─── Top: where you start and the search field ────────────────────────────

  Widget _buildSearchBarSection() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, color: _textPrimary),
              ),
              Expanded(child: _buildFromRow()),
              const SizedBox(width: 48),
            ],
          ),
          if (_originSuggestions.isNotEmpty)
            _buildSuggestionList(_originSuggestions, _onOriginSuggestionTap),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(
                width: 48,
                child: Icon(
                  Icons.location_on_outlined,
                  size: 20,
                  color: _textSecondary,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: _textPrimary, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Where to?',
                    hintStyle: const TextStyle(
                      color: _textSecondary,
                      fontSize: 16,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF1F4F9),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon:
                        _searchController.text.isNotEmpty
                            ? IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _searchController.clear();
                                _onSearch('');
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: _textSecondary,
                              ),
                            )
                            : null,
                  ),
                  onChanged: _onSearch,
                  onSubmitted: _onSearchSubmitted,
                  onTap: _onSearchFocus,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: _textSecondary,
                ),
                onSelected: (value) {
                  if (value == 'downloaded') _openDownloadedRoutes();
                  if (value == 'help') _showSearchHelpSheet();
                },
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(
                        value: 'downloaded',
                        child: Text('Downloaded routes'),
                      ),
                      PopupMenuItem(
                        value: 'help',
                        child: Text('How search works'),
                      ),
                    ],
              ),
            ],
          ),
          if (_showOmnibox && _suggestions.isNotEmpty) _buildOmnibox(),
        ],
      ),
    );
  }

  /// Where routes start. Left empty it reads "Your location" and uses GPS;
  /// type a place to start somewhere else, clear it to go back.
  Widget _buildFromRow() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _originController,
      builder: (context, value, _) {
        final isCustom = value.text.isNotEmpty;
        return TextField(
          controller: _originController,
          focusNode: _originFocusNode,
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: _textPrimary, fontSize: 16),
          decoration: InputDecoration(
            // Reads as the value, not a faded hint: it's the real start.
            hintText: 'Your location',
            hintStyle: const TextStyle(color: _textPrimary, fontSize: 16),
            prefixIcon: Icon(
              isCustom ? Icons.trip_origin_rounded : Icons.my_location_rounded,
              size: 18,
              color: _accent,
            ),
            filled: true,
            fillColor: const Color(0xFFF1F4F9),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            suffixIcon:
                isCustom
                    ? IconButton(
                      tooltip: 'Start from your location',
                      onPressed: () {
                        _originController.clear();
                        _onOriginTyped('');
                        _onOriginChanged();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: _textSecondary,
                      ),
                    )
                    : null,
          ),
          onChanged: _onOriginTyped,
          onSubmitted: (_) {
            _onOriginTyped('');
            _onOriginChanged();
          },
        );
      },
    );
  }

  Widget _buildOmniboxSection() =>
      _buildSuggestionList(_suggestions, _onSuggestionTap);

  /// Place suggestions under a field (start or "Where to?").
  Widget _buildSuggestionList(
    List<String> suggestions,
    void Function(String) onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          for (final suggestion in suggestions)
            InkWell(
              onTap: () => onTap(suggestion),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Icon(
                        _recentSearches.contains(suggestion)
                            ? Icons.history_rounded
                            : Icons.place_outlined,
                        size: 20,
                        color: _textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        suggestion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Results ──────────────────────────────────────────────────────────────

  Widget _buildSearchResultsSection() {
    final community = _sortContributedRoutes(
      _filteredRoutes,
      _contributedSortMode,
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
      children: [
        RouteOptionSection(
          title: 'Suggested routes',
          footnote:
              _routeAlternatives.isNotEmpty || _orsResult != null
                  ? 'Built from transit stops and community routes. Times '
                      'and fares are estimates.'
                  : null,
          children: _suggestedRouteRows(),
        ),
        const SizedBox(height: 24),
        RouteOptionSection(
          title: 'Community routes',
          trailing: community.length > 1 ? _sortMenu() : null,
          children:
              community.isEmpty
                  ? [
                    const _MessageRow(
                      text: 'No community routes match this search yet.',
                    ),
                  ]
                  : [for (final route in community) _communityRouteRow(route)],
        ),
      ],
    );
  }

  List<Widget> _suggestedRouteRows() {
    final hasOptions = _routeAlternatives.isNotEmpty || _orsResult != null;
    if (_isLoadingOrs && !hasOptions) {
      return const [_MessageRow(text: 'Finding routes…', busy: true)];
    }
    final rows = <Widget>[
      if (_orsError)
        _MessageRow(
          text: _orsErrorMessage,
          isError: true,
          actionLabel: 'Try again',
          onAction: _fetchOrsRoute,
        ),
    ];
    if (_routeAlternatives.isNotEmpty) {
      for (var i = 0; i < _routeAlternatives.length; i++) {
        rows.add(_alternativeRow(i));
      }
    } else if (_orsResult != null) {
      rows.add(_generatedResultRow(_orsResult!));
    } else if (!_orsError) {
      rows.add(
        _MessageRow(
          text: 'Search to see routes from where you are.',
          actionLabel: 'Find routes',
          onAction: _fetchOrsRoute,
        ),
      );
    }
    return rows;
  }

  Widget _alternativeRow(int index) {
    final alt = _routeAlternatives[index];
    final fallback = _fallbackAlternativeRoutes[index];
    final legs = alt.result.plan.legs;
    final usesCommunity =
        fallback == null && legs.any((leg) => leg.isCommunity);
    final fare =
        fallback == null
            ? alt.estimatedFarePhp
            : fallback.steps.fold<double>(0, (sum, s) => sum + s.estimatedFare);
    final minutes =
        fallback == null
            ? alt.estimatedTimeMinutes
            : fallback.durationSeconds / 60;
    final modes =
        fallback != null
            ? collapseModes(fallback.steps.map((s) => s.suggestedMode))
            : collapseModes([
              if (alt.totalWalkKm >= 0.05) 'Walk',
              for (final leg in legs) RoutingService.modeForLeg(leg),
            ]);
    final label = _alternativeLabels[index];
    return RouteOptionRow(
      headline: _SearchScreenState._minutesLabel(minutes),
      details: [
        _SearchScreenState._fareLabel(fare),
        if (fallback == null)
          _SearchScreenState._transfersLabel(legs.length)
        else
          'Walk only',
        if (fallback == null && alt.totalWalkKm >= 0.05)
          _SearchScreenState._walkLabel(alt.totalWalkKm),
      ].join(' · '),
      modes: modes,
      tag:
          usesCommunity
              ? 'Community'
              : (label == null || label.isEmpty
                  ? null
                  : label.split(' • ').first),
      tagHighlighted: usesCommunity,
      busy: _pendingAlternativeIndex == index,
      onTap: () => _openAlternative(index),
    );
  }

  Widget _generatedResultRow(OrsRouteResult result) {
    final fare = result.steps.fold<double>(
      0,
      (sum, s) => sum + s.estimatedFare,
    );
    return RouteOptionRow(
      headline: _SearchScreenState._minutesLabel(result.durationSeconds / 60),
      details: [
        _SearchScreenState._fareLabel(fare),
        result.distanceLabel,
      ].join(' · '),
      modes: collapseModes(result.steps.map((s) => s.suggestedMode)),
      tag: result.usesCommunityRoutes ? 'Community' : null,
      tagHighlighted: result.usesCommunityRoutes,
      onTap: _openResultOnMap,
    );
  }

  Widget _communityRouteRow(route_model.Route route) {
    final fare = _routeEstimatedFare(route);
    return RouteOptionRow(
      headline: '${route.startLocation} → ${route.endLocation}',
      details: [
        _SearchScreenState._fareLabel(fare),
        '${_routeEstimatedMinutes(route)} min',
        if (route.upvotes > 0) '▲ ${route.upvotes}',
      ].join(' · '),
      modes: collapseModes(route.steps.map((s) => s.mode)),
      onTap: () => _onRouteTap(route),
    );
  }

  Widget _sortMenu() {
    const labels = {
      ContributedRouteSortMode.balanced: 'Best',
      ContributedRouteSortMode.budget: 'Cheapest',
      ContributedRouteSortMode.fastest: 'Fastest',
    };
    return PopupMenuButton<ContributedRouteSortMode>(
      tooltip: 'Sort',
      onSelected: _setContributedSortMode,
      itemBuilder:
          (_) => [
            for (final entry in labels.entries)
              PopupMenuItem(value: entry.key, child: Text(entry.value)),
          ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labels[_contributedSortMode]!,
            style: const TextStyle(color: _accent, fontSize: 13),
          ),
          const Icon(Icons.arrow_drop_down_rounded, color: _accent),
        ],
      ),
    );
  }
}

/// A plain line in a results section: loading, empty or an error, with an
/// optional action on the right.
class _MessageRow extends StatelessWidget {
  final String text;
  final bool busy;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageRow({
    required this.text,
    this.busy = false,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          if (busy) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color:
                    isError
                        ? const Color(0xFFC6414F)
                        : _SearchScreenState._textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
