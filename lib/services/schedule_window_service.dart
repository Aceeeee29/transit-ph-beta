import '../models/route.dart' as route_model;

enum ScheduleWindowState {
  live,
  stale,
  scheduled,
  estimated,
  unavailable,
}

class StepScheduleView {
  final int stepIndex;
  final ScheduleWindowState state;
  final String displayText;

  const StepScheduleView({
    required this.stepIndex,
    required this.state,
    required this.displayText,
  });
}

class RouteScheduleSnapshot {
  final ScheduleWindowState state;
  final DateTime? lastUpdated;
  final String summaryText;
  final List<StepScheduleView> steps;

  const RouteScheduleSnapshot({
    required this.state,
    required this.summaryText,
    required this.steps,
    this.lastUpdated,
  });
}

class ScheduleWindowService {
  static const int _routeFreshnessHours = 72;

  static Future<RouteScheduleSnapshot> getRouteScheduleSnapshot(
    route_model.Route route,
  ) async {
    final updatedAt = route.updatedAt ?? route.createdAt;
    final now = DateTime.now();
    final isRouteFresh =
        updatedAt != null &&
        now.difference(updatedAt).inHours <= _routeFreshnessHours;

    var hasAnyWindowActive = false;
    var hasAnyFutureWindow = false;
    var hasAnyWindowEnded = false;
    var hasAnyEstimated = false;
    var hasAnyAlternate = false;

    final stepViews = <StepScheduleView>[];
    for (var i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
      if (step.mode == 'Walk') {
        continue;
      }

      final scheduled = _stepScheduledText(step);
      final estimated = _stepEstimatedText(i, route.steps.length);
      final alternate = step.alternateRouteSuggestion?.trim();
      if (alternate != null && alternate.isNotEmpty) {
        hasAnyAlternate = true;
      }

      if (scheduled == null && estimated != null) {
        hasAnyEstimated = true;
      }

      final status = _windowStatusForStep(step, now);
      if (status == _WindowStatus.active && scheduled != null) {
        stepViews.add(
          StepScheduleView(
            stepIndex: i,
            state: ScheduleWindowState.live,
            displayText: 'Live now by schedule: $scheduled',
          ),
        );
        hasAnyWindowActive = true;
        continue;
      }

      if (status == _WindowStatus.beforeStart && scheduled != null) {
        stepViews.add(
          StepScheduleView(
            stepIndex: i,
            state: ScheduleWindowState.scheduled,
            displayText: 'Starts later: $scheduled',
          ),
        );
        hasAnyFutureWindow = true;
        continue;
      }

      if (status == _WindowStatus.ended && scheduled != null) {
        final suffix =
            (alternate != null && alternate.isNotEmpty)
                ? ' | Alt: $alternate'
                : '';
        stepViews.add(
          StepScheduleView(
            stepIndex: i,
            state: ScheduleWindowState.stale,
            displayText: 'Service ended today: $scheduled$suffix',
          ),
        );
        hasAnyWindowEnded = true;
        continue;
      }

      if (scheduled != null) {
        stepViews.add(
          StepScheduleView(
            stepIndex: i,
            state: ScheduleWindowState.scheduled,
            displayText: 'Scheduled: $scheduled',
          ),
        );
      } else if (estimated != null) {
        stepViews.add(
          StepScheduleView(
            stepIndex: i,
            state: ScheduleWindowState.estimated,
            displayText: 'Estimated: $estimated',
          ),
        );
      } else {
        stepViews.add(
          StepScheduleView(
            stepIndex: i,
            state: ScheduleWindowState.unavailable,
            displayText: 'Schedule unavailable',
          ),
        );
      }
    }

    if (hasAnyWindowActive) {
      final freshness =
          updatedAt == null ? 'unknown route timestamp' : _ageText(updatedAt, now);
      final summary = isRouteFresh
          ? 'Live now by schedule window (route updated $freshness)'
          : 'Live now by timetable window (route data is older: $freshness)';
      return RouteScheduleSnapshot(
        state: ScheduleWindowState.live,
        lastUpdated: updatedAt,
        summaryText: summary,
        steps: stepViews,
      );
    }

    if (hasAnyWindowEnded) {
      final summary = hasAnyAlternate
          ? 'Outside operating hours. Alternate route suggestions are available.'
          : 'Outside operating hours for this route.';
      return RouteScheduleSnapshot(
        state: ScheduleWindowState.stale,
        lastUpdated: updatedAt,
        summaryText: summary,
        steps: stepViews,
      );
    }

    if (hasAnyFutureWindow) {
      return RouteScheduleSnapshot(
        state: ScheduleWindowState.scheduled,
        summaryText: 'Using timetable schedule. Service has not started yet.',
        steps: stepViews,
      );
    }

    if (hasAnyEstimated) {
      return RouteScheduleSnapshot(
        state: ScheduleWindowState.estimated,
        summaryText: 'Using estimated schedule windows',
        steps: stepViews,
      );
    }

    return RouteScheduleSnapshot(
      state: ScheduleWindowState.unavailable,
      summaryText: hasAnyAlternate
          ? 'No schedule data. Alternate route notes are available.'
          : 'No schedule data available yet.',
      steps: stepViews,
    );
  }

  static StepScheduleView? findStepView(
    RouteScheduleSnapshot? snapshot,
    int stepIndex,
  ) {
    if (snapshot == null) return null;
    for (final item in snapshot.steps) {
      if (item.stepIndex == stepIndex) return item;
    }
    return null;
  }

  static String? _stepScheduledText(route_model.Step step) {
    if (step.is24_7) return '24/7';
    final start = step.startTime?.trim();
    final end = step.endTime?.trim();
    if (start == null || start.isEmpty || end == null || end.isEmpty) {
      return null;
    }
    return '$start-$end';
  }

  static _WindowStatus _windowStatusForStep(route_model.Step step, DateTime now) {
    if (step.is24_7) return _WindowStatus.active;

    final start = _parseMinuteOfDay(step.startTime);
    final end = _parseMinuteOfDay(step.endTime);
    if (start == null || end == null) return _WindowStatus.unknown;

    final nowMinute = now.hour * 60 + now.minute;
    if (end < start) {
      // Overnight window, e.g. 22:00-04:00
      final active = nowMinute >= start || nowMinute <= end;
      return active ? _WindowStatus.active : _WindowStatus.beforeStart;
    }

    if (nowMinute < start) return _WindowStatus.beforeStart;
    if (nowMinute > end) return _WindowStatus.ended;
    return _WindowStatus.active;
  }

  static int? _parseMinuteOfDay(String? raw) {
    final clean = raw?.trim();
    if (clean == null || clean.isEmpty) return null;
    final parts = clean.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  static String _ageText(DateTime timestamp, DateTime now) {
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hr ago';
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }

  static String? _stepEstimatedText(int stepIndex, int totalSteps) {
    if (totalSteps <= 0) return null;
    final startHour = 6 + (stepIndex * 2);
    final endHour = startHour + 2;
    final safeStart = startHour.clamp(0, 23).toString().padLeft(2, '0');
    final safeEnd = endHour.clamp(0, 23).toString().padLeft(2, '0');
    return '$safeStart:00-$safeEnd:00';
  }
}

enum _WindowStatus {
  active,
  beforeStart,
  ended,
  unknown,
}
