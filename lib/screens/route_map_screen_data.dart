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

  Future<void> _loadReportsSection() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/reports.json');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final Map<String, dynamic> jsonData = jsonDecode(contents);
        final List<route_model.Report> loadedReports = [];
        if (jsonData.containsKey(widget.route.id)) {
          final List<dynamic> reportList = jsonData[widget.route.id];
          loadedReports.addAll(
            reportList.map(
              (r) => route_model.Report(
                type: r['type'],
                description: r['description'],
                timestamp: DateTime.fromMillisecondsSinceEpoch(r['timestamp']),
              ),
            ),
          );
        }
        _setRouteReports(
          loadedReports..addAll(widget.route.reports),
          sortByLatest: true,
        );
      } else {
        _setRouteReports(List.from(widget.route.reports));
      }
    } catch (_) {
      _setRouteReports(List.from(widget.route.reports));
    }
  }

  Future<void> _saveReportsSection() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/reports.json');
      Map<String, dynamic> allReports = {};
      if (await file.exists()) {
        allReports = jsonDecode(await file.readAsString());
      }
      allReports[widget.route.id] = _routeReports
          .map((r) => {
                'type': r.type,
                'description': r.description,
                'timestamp': r.timestamp.millisecondsSinceEpoch,
              })
          .toList();
      await file.writeAsString(jsonEncode(allReports));
    } catch (e) {
      debugPrint('RouteMapScreen: failed to save reports locally: $e');
    }
  }
}
