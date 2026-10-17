part of 'route_map_screen.dart';

extension _RouteMapScreenDataSections on _RouteMapScreenState {
  static const _skipTrustPromptDateKey =
      _RouteMapScreenState._skipTrustPromptDateKey;

  String _todayTokenSection() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<bool> _isTrustPromptSkippedTodaySection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_skipTrustPromptDateKey);
      return value == _todayTokenSection();
    } catch (_) {
      return false;
    }
  }

  Future<void> _setTrustPromptSkipTodaySection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_skipTrustPromptDateKey, _todayTokenSection());
    } catch (_) {}
  }

  /// Reports from every rider on this route's road (shared in Firestore),
  /// plus any saved on the route itself.
  Future<void> _loadReportsSection({bool refresh = false}) async {
    if (refresh) await RouteReportService.active(refresh: true);
    final shared = await RouteReportService.affecting(_pathPoints);
    if (!mounted) return;
    _sharedReports = shared;
    _setRouteReports([
      for (final r in shared)
        route_model.Report(
          type: r.type,
          description: _sharedReportText(r),
          timestamp: r.createdAt,
        ),
      ...widget.route.reports,
    ], sortByLatest: true);
  }

  /// A report filed on another route on the same road says which.
  String? _sharedReportText(RouteIssueReport report) {
    final note = report.description;
    if (report.routeId == widget.route.id) return note;
    final where = 'Reported on ${report.routeLabel}';
    return note == null || note.isEmpty ? where : '$where: $note';
  }
}
