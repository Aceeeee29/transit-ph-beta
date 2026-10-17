part of 'route_map_screen.dart';

/// Start pressed far from the route (more than a 20-minute walk from any
/// part of it): offer a way to its start, rider routes first, and open both
/// as one trip ("VGC → Monumento + Monumento → STI").
extension _RouteMapScreenWayToStart on _RouteMapScreenState {
  /// A 20-minute walk, by road (walks run about 1.3× the straight line).
  static const _farMeters = 20 / 60 * 5000 / 1.3;

  /// True when Start should not go on: the rider chose a way to the start
  /// (opened instead) or closed the question.
  Future<bool> _offerWayToStartSection(LatLng here) async {
    if (_pathPoints.length < 2) return false;
    const distance = Distance(roundResult: false);
    final nearest = _pathPoints
        .map((p) => distance.as(LengthUnit.Meter, here, p))
        .reduce(math.min);
    if (nearest <= _farMeters) return false;

    final start = _pathPoints.first;
    final km = distance.as(LengthUnit.Kilometer, here, start);
    final choice = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("You're far from this route"),
            content: Text(
              '${widget.route.startLocation} is about '
              '${km < 10 ? km.toStringAsFixed(1) : km.round()} km from you. '
              'Find a way there using rider routes?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'start'),
                child: const Text('Start anyway'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'find'),
                child: const Text('Find a way'),
              ),
            ],
          ),
    );
    if (choice == 'start') return false;
    if (choice == 'find' && mounted) await _openWayToStart(here, start);
    return true;
  }

  Future<void> _openWayToStart(LatLng here, LatLng start) async {
    var loading = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Finding a way to ${widget.route.startLocation}…',
                  ),
                ),
              ],
            ),
          ),
    );
    void closeLoading() {
      if (loading && mounted) Navigator.of(context, rootNavigator: true).pop();
      loading = false;
    }

    try {
      final routes = await RouteService.getAllRoutes();
      final riderRoutes =
          routes
              .where((r) => r.id != widget.route.id)
              .map(CommunityRoute.fromRoute)
              .whereType<CommunityRoute>()
              .toList();
      // Rider routes first; the transit data fills in where none go.
      var options = await RoutingService.getRouteAlternatives(
        origin: here,
        destination: start,
        optimization: riderRoutes.isEmpty ? 'balanced' : 'community',
        maxAlternatives: 3,
        communityRoutes: riderRoutes,
      );
      if (options.isEmpty && riderRoutes.isNotEmpty) {
        options = await RoutingService.getRouteAlternatives(
          origin: here,
          destination: start,
          maxAlternatives: 3,
          communityRoutes: riderRoutes,
        );
      }
      if (!mounted) return;
      if (options.isEmpty) {
        closeLoading();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't find a way to ${widget.route.startLocation}. "
              'Try Search.',
            ),
          ),
        );
        return;
      }
      final best = options.first.result;
      final toStart = await RoutingService.buildRouteFromDijkstraAlternative(
        origin: here,
        destination: start,
        alternative: best,
      );
      final trip = TripJoiner.join(
        toStart: toStart,
        route: widget.route,
        routePath: _pathPoints,
        stepRanges: [
          for (final r in _stepRanges()) (start: r.start, end: r.end),
        ],
      );
      if (!mounted) return;
      closeLoading();
      final route = widget.route;
      MapTabController.instance.showGenerated(
        trip,
        originName: TripJoiner.title(
          firstFrom: best.plan.legs.first.boardStopName,
          route: route,
        ),
        destinationName: route.endLocation,
        // Back returns to the rider route on its own.
        onBack: (context) => MapTabController.openRoute(context, route),
      );
    } catch (e) {
      debugPrint('[WayToStart] Failed: $e');
      if (!mounted) return;
      closeLoading();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't find a way to ${widget.route.startLocation}. "
            'Check your connection.',
          ),
        ),
      );
    }
  }
}
