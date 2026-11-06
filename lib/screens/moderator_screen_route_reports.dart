part of 'moderator_screen.dart';

/// Riders' route reports still showing: each shows for a day on every route
/// on its road. Keep holds one until removed. Remove takes it down now.
/// The cards use the same pieces as the other tabs so the panel looks the same.
extension _ModeratorScreenRouteReports on _ModeratorScreenState {
  static Color get _surfaceAlt => _ModeratorScreenState._surfaceAlt;
  static const _accent = _ModeratorScreenState._accent;
  static Color get _textPrimary => _ModeratorScreenState._textPrimary;
  static Color get _textSecondary => _ModeratorScreenState._textSecondary;
  static Color get _border => _ModeratorScreenState._border;
  static const _danger = _ModeratorScreenState._danger;
  static const _warning = _ModeratorScreenState._warning;

  Widget _buildRouteReportsTabSection() {
    return StreamBuilder<List<RouteIssueReport>>(
      stream: RouteReportService.watchActive(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final reports = snapshot.data ?? const <RouteIssueReport>[];
        if (reports.isEmpty) {
          return _refreshableEmptyState(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.report_problem_outlined,
                    size: 32,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'No route reports right now',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Reports show on routes for a day unless you keep them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: _accent,
          onRefresh: _refreshModeratorPanel,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: reports.length,
            itemBuilder: (context, i) => _routeReportCard(reports[i]),
          ),
        );
      },
    );
  }

  Widget _routeReportCard(RouteIssueReport report) {
    final note = report.description;
    final statusColor = report.kept ? _accent : _warning;
    final statusLabel =
        report.kept ? 'kept' : '${_hoursLeft(report.expiresAt)} left';

    return _panelCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.report_problem_outlined,
                    size: 16,
                    color: _warning,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    report.type,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  note,
                  style: TextStyle(
                    fontSize: 13,
                    color: _textPrimary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _metaChip(Icons.alt_route_rounded, report.routeLabel, _accent),
                _metaChip(
                  Icons.schedule_outlined,
                  _reportAge(report.createdAt),
                  _textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!report.kept) ...[
                  _actionButton(
                    label: 'Keep',
                    color: _accent,
                    filled: true,
                    lockItem: 'report:${report.id}',
                    onTap:
                        () => _runReportAction(
                          () => RouteReportService.keep(report.id),
                          'Report kept until removed',
                        ),
                  ),
                  const SizedBox(width: 8),
                ],
                _actionButton(
                  label: 'Remove',
                  color: _danger,
                  lockItem: 'report:${report.id}',
                  onTap:
                      () => _runReportAction(
                        () => RouteReportService.remove(report.id),
                        'Report removed',
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Runs a Keep/Remove and says how it went. [_actionButton] already stops
  /// double taps, so this doesn't need its own lock.
  Future<void> _runReportAction(
    Future<void> Function() action,
    String done,
  ) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  static String _hoursLeft(DateTime expiresAt) {
    final left = expiresAt.difference(DateTime.now());
    if (left.inHours >= 1) return '${left.inHours} h';
    return '${left.inMinutes.clamp(1, 59)} min';
  }

  static String _reportAge(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
