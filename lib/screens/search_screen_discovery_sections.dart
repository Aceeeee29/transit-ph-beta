part of 'search_screen.dart';

extension _SearchScreenDiscoverySections on _SearchScreenState {
  static const _surface = _SearchScreenState._surface;
  static const _surfaceAlt = _SearchScreenState._surfaceAlt;
  static const _textPrimary = _SearchScreenState._textPrimary;
  static const _textSecondary = _SearchScreenState._textSecondary;
  static const _border = _SearchScreenState._border;

  Widget _buildSearchSuggestionsSection() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_recentSearches.isNotEmpty) ...[
            _buildRecentSearches(),
            const SizedBox(height: 24),
          ],
          _buildTopSearches(),
        ],
      ),
    );
  }

  Widget _buildRecentSearchesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT SEARCHES',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            GestureDetector(
              onTap: _onClearRecentSearches,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _border),
                ),
                child: const Text(
                  'Clear All',
                  style: TextStyle(
                    fontSize: 11,
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _recentSearches.map((search) {
                return GestureDetector(
                  onTap: () => _onRecentSearchTap(search),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 13,
                          color: _textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          search,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _onRemoveRecentSearch(search),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildTopSearchesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TOP SEARCHES',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Popular routes based on community activity',
          style: TextStyle(fontSize: 13, color: _textSecondary),
        ),
        const SizedBox(height: 16),
        ..._topSearches.map((route) => _routeCardWithBadge(route)),
      ],
    );
  }
}
