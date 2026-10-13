part of 'search_screen.dart';

extension _SearchScreenDiscoverySections on _SearchScreenState {
  static Color get _textPrimary => _SearchScreenState._textPrimary;
  static Color get _textSecondary => _SearchScreenState._textSecondary;

  /// Before searching: recent searches, then popular community routes.
  Widget _buildSearchSuggestionsSection() {
    final popular = _topSearches;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          RouteOptionSection(
            title: 'Recent',
            trailing: TextButton(
              onPressed: _onClearRecentSearches,
              child: const Text('Clear'),
            ),
            children: [
              for (final search in _recentSearches)
                InkWell(
                  onTap: () => _onRecentSearchTap(search),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 20,
                          color: _textSecondary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            search,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _textPrimary, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _onRemoveRecentSearch(search),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (popular.isNotEmpty)
          RouteOptionSection(
            title: 'Popular routes',
            children: [for (final route in popular) _communityRouteRow(route)],
          ),
      ],
    );
  }
}
