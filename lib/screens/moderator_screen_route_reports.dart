part of 'moderator_screen.dart';

/// Riders' route reports still showing: each shows for a day on every route
/// on its road. Keep holds one until removed; Remove takes it down now.
extension _ModeratorScreenRouteReports on _ModeratorScreenState {
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
                Icon(
                  Icons.report_problem_outlined,
                  size: 36,
                  color: _ModeratorScreenState._textSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  'No route reports right now',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _ModeratorScreenState._textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Reports show on routes for a day unless you keep them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: _ModeratorScreenState._textSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _routeReportCard(reports[i]),
        );
      },
    );
  }

  Widget _routeReportCard(RouteIssueReport report) {
    final note = report.description;
    final status =
        report.kept
            ? 'Kept until removed'
            : 'Shows for ${_hoursLeft(report.expiresAt)} more';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ModeratorScreenState._surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ModeratorScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.type,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _ModeratorScreenState._textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'On ${report.routeLabel} · ${_reportAge(report.createdAt)}',
            style: TextStyle(
              fontSize: 12.5,
              color: _ModeratorScreenState._textSecondary,
            ),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: TextStyle(
                fontSize: 13.5,
                color: _ModeratorScreenState._textPrimary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color:
                  report.kept
                      ? _ModeratorScreenState._accent
                      : _ModeratorScreenState._textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _lockWhileBusy(
            'report:${report.id}',
            Row(
              children: [
                if (!report.kept)
                  OutlinedButton(
                    onPressed:
                        () => _runReportAction(
                          report.id,
                          () => RouteReportService.keep(report.id),
                          'Report kept until removed',
                        ),
                    child: const Text('Keep'),
                  ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _ModeratorScreenState._danger,
                  ),
                  onPressed:
                      () => _runReportAction(
                        report.id,
                        () => RouteReportService.remove(report.id),
                        'Report removed',
                      ),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runReportAction(
    String reportId,
    Future<void> Function() action,
    String done,
  ) => _runOnce('report:$reportId', () async {
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
  });

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
