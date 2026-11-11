import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'routes_api.dart';

/// What a rider can say is wrong with a route's details. Road conditions
/// (traffic, floods) are a different report, in RouteReportService.
enum RouteIssueType {
  wrongFare(
    'wrong_fare',
    'Wrong fare',
    'The fare is different from what I paid',
  ),
  wrongPath('wrong_path', 'Wrong path', 'The vehicle goes a different way'),
  notOperating('not_operating', 'Not running anymore', 'This route stopped'),
  wrongSchedule(
    'wrong_schedule',
    'Wrong schedule',
    'The hours or frequency are wrong',
  ),
  wrongStop('wrong_stop', 'Wrong stop', 'A stop or terminal is wrong'),
  other('other', 'Something else', 'Tell us what is wrong');

  final String code;
  final String label;
  final String hint;

  const RouteIssueType(this.code, this.label, this.hint);

  static RouteIssueType? fromCode(String? code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// A route riders say may be out of date. Search avoids it and warns.
class OutdatedLabel {
  final String routeKey;
  final List<RouteIssueType> types;
  final int riders;
  final DateTime? updatedAt;

  const OutdatedLabel({
    required this.routeKey,
    required this.types,
    required this.riders,
    this.updatedAt,
  });

  factory OutdatedLabel.fromRow(Map<String, dynamic> row) => OutdatedLabel(
    routeKey: row['route_key'] as String? ?? '',
    types: [
      for (final code in row['types'] as List? ?? const [])
        if (RouteIssueType.fromCode(code?.toString()) case final type?) type,
    ],
    riders: (row['riders'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
  );

  /// A label counts for as long as the reports behind it, 30 days.
  bool isCurrent([DateTime? now]) {
    final updated = updatedAt;
    if (types.isEmpty || updated == null) return false;
    return (now ?? DateTime.now()).difference(updated) <
        const Duration(days: 30);
  }

  /// "Riders say: Wrong fare, Not running anymore".
  String get summary =>
      'Riders say: ${types.map((type) => type.label).join(', ')}';
}

/// What the server did with a report.
class RouteIssueResult {
  /// The report pushed the route over the limit, so it's now "Possibly
  /// outdated".
  final bool outdated;

  /// Enough riders agreed on the fare, so it was changed.
  final bool fareChanged;

  const RouteIssueResult({this.outdated = false, this.fareChanged = false});
}

/// Rider reports about a route's details, and the "Possibly outdated" labels
/// they lead to.
///
/// A report's route key is the route's id for rider and OpenStreetMap routes,
/// or `gtfs:<route_id>` for the DOTC 2013 feed.
class RouteIssueService {
  RouteIssueService._();

  static const _refreshAfter = Duration(minutes: 5);

  static Map<String, OutdatedLabel> _labels = const {};
  static DateTime _loadedAt = DateTime(0);

  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function()? outdatedReader;

  @visibleForTesting
  static void resetForTesting({Map<String, OutdatedLabel> labels = const {}}) {
    outdatedReader = null;
    _labels = labels;
    _loadedAt = labels.isEmpty ? DateTime(0) : DateTime.now();
  }

  /// The label for [routeKey], if riders say it may be out of date. Uses what
  /// was last loaded, so it's safe to call while drawing.
  static OutdatedLabel? labelFor(String routeKey) {
    final label = _labels[routeKey];
    return label != null && label.isCurrent() ? label : null;
  }

  static bool isOutdated(String routeKey) => labelFor(routeKey) != null;

  /// Loads the labels. A failure keeps the last ones, since missing a warning
  /// is better than losing every route.
  static Future<void> refreshOutdated({bool force = false}) async {
    if (!force && DateTime.now().difference(_loadedAt) < _refreshAfter) return;
    try {
      final rows = await (outdatedReader ?? _readOutdated)();
      _labels = {
        for (final row in rows)
          if (OutdatedLabel.fromRow(row) case final label
              when label.routeKey.isNotEmpty)
            label.routeKey: label,
      };
      _loadedAt = DateTime.now();
    } catch (e) {
      debugPrint('[RouteIssues] Could not load outdated labels: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> _readOutdated() async {
    final rows = await Supabase.instance.client
        .from('route_outdated')
        .select('route_key,types,riders,updated_at')
        .timeout(const Duration(seconds: 15));
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  /// Sends a report. Throws a [RoutesApiException]: `already_reported` when
  /// this rider already has an open one of this type, `report_limit` after 20
  /// in a day, `not_live` when the route isn't published.
  static Future<RouteIssueResult> report({
    required String routeKey,
    required RouteIssueType type,
    double? farePaid,
    int? stepIndex,
    String? note,
    String? correctionId,
  }) async {
    final trimmed = note?.trim();
    final result = await RoutesApi.call('report_issue', {
      'routeId': routeKey,
      'type': type.code,
      if (farePaid != null) 'farePaid': farePaid,
      if (stepIndex != null) 'stepIndex': stepIndex,
      if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
      if (correctionId != null) 'correctionId': correctionId,
    });
    final map = result is Map ? result : const {};
    final outcome = RouteIssueResult(
      outdated: map['outdated'] == true,
      fareChanged: map['fareChanged'] == true,
    );
    // The label or the fare changed, so the next screen should show it.
    if (outcome.outdated || outcome.fareChanged) {
      await refreshOutdated(force: true);
    }
    return outcome;
  }

  /// What to tell the rider when a report wasn't taken.
  static String messageFor(Object error) {
    if (error is RoutesApiException) {
      switch (error.code) {
        case 'already_reported':
          return 'You already reported this. Thanks, it still counts.';
        case 'report_limit':
          return "You've sent a lot of reports today. Try again tomorrow.";
        case 'not_live':
        case 'not_found':
          return "This route can't be reported right now.";
        case 'blocked':
          return "Your account can't send reports right now.";
      }
    }
    return "Couldn't send the report. Check your connection.";
  }

  // Moderators

  /// Routes with open reports, the possibly outdated ones first.
  static Future<List<RouteProblem>> issueQueue() async {
    final rows = await RoutesApi.call('issue_queue') as List<dynamic>;
    return [
      for (final row in rows)
        if (row is Map) RouteProblem.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// [resolution] is `resolved` (fixed, or right after all) or `dismissed`
  /// (the reports were wrong). Either clears the label.
  static Future<void> settle(
    String routeKey, {
    required String resolution,
    String? note,
  }) async {
    final trimmed = note?.trim();
    await RoutesApi.call('settle_issues', {
      'routeId': routeKey,
      'resolution': resolution,
      if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
    });
    await refreshOutdated(force: true);
  }
}

/// One route on the moderators' Route problems list.
class RouteProblem {
  final String routeKey;
  final String title;

  /// 'rider', 'osm' or 'gtfs'.
  final String? source;
  final bool outdated;

  /// Different riders per report type.
  final Map<RouteIssueType, int> counts;
  final List<RouteIssue> issues;

  const RouteProblem({
    required this.routeKey,
    required this.title,
    this.source,
    this.outdated = false,
    this.counts = const {},
    this.issues = const [],
  });

  factory RouteProblem.fromJson(Map<String, dynamic> json) {
    final counts = <RouteIssueType, int>{};
    final rawCounts = json['counts'];
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        final type = RouteIssueType.fromCode(entry.key.toString());
        if (type != null && entry.value is num) {
          counts[type] = (entry.value as num).toInt();
        }
      }
    }
    return RouteProblem(
      routeKey: json['routeKey'] as String? ?? '',
      title: json['title'] as String? ?? '',
      source: json['source'] as String?,
      outdated: json['outdated'] is Map,
      counts: counts,
      issues: [
        for (final issue in json['issues'] as List? ?? const [])
          if (issue is Map)
            RouteIssue.fromJson(Map<String, dynamic>.from(issue)),
      ],
    );
  }
}

class RouteIssue {
  final RouteIssueType type;
  final double? farePaid;
  final int? stepIndex;
  final String? note;
  final String? correctionId;
  final DateTime? createdAt;

  const RouteIssue({
    required this.type,
    this.farePaid,
    this.stepIndex,
    this.note,
    this.correctionId,
    this.createdAt,
  });

  factory RouteIssue.fromJson(Map<String, dynamic> json) => RouteIssue(
    type:
        RouteIssueType.fromCode(json['type'] as String?) ??
        RouteIssueType.other,
    farePaid: (json['fare_paid'] as num?)?.toDouble(),
    stepIndex: (json['step_index'] as num?)?.toInt(),
    note: json['note'] as String?,
    correctionId: json['correction_id'] as String?,
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
  );
}
