part of 'route_map_screen.dart';

extension _RouteMapScreenMapSections on _RouteMapScreenState {
  static const _surface = _RouteMapScreenState._surface;
  static const _accent = _RouteMapScreenState._accent;
  static const _textPrimary = _RouteMapScreenState._textPrimary;
  static const _textSecondary = _RouteMapScreenState._textSecondary;
  static const _border = _RouteMapScreenState._border;

  Widget _buildStartControlSection() {
    if (!_isNavigationStarted) {
      return ElevatedButton.icon(
        onPressed: _startNavigation,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('Start'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      );
    }

    return GestureDetector(
      onTap: _toggleAutoFollowEnabled,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isAutoFollowEnabled ? _accent.withValues(alpha: 0.45) : _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isAutoFollowEnabled
                  ? Icons.gps_fixed_rounded
                  : Icons.gps_not_fixed_rounded,
              color: _isAutoFollowEnabled ? _accent : _textSecondary,
              size: 17,
            ),
            const SizedBox(width: 6),
            Text(
              _isAutoFollowEnabled ? 'Following' : 'Follow paused',
              style: TextStyle(
                color: _isAutoFollowEnabled ? _accent : _textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapLegendSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            modeColors.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: entry.value,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildCenterButtonSection() {
    return GestureDetector(
      onTap: _centerOnCurrentLocation,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.my_location_rounded, color: _accent, size: 20),
      ),
    );
  }
}
