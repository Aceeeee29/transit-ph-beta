import 'package:transitph_beta/models/route.dart' as route_model;

/// Turns rows from the Supabase `transit_routes` table into the app's routes.
///
/// A route's details live in the row's `data` column. The other columns belong
/// to the server, so they replace anything saved under the same name in `data`.
class RouteRows {
  RouteRows._();

  static route_model.Route toRoute(Map<String, dynamic> row) {
    final data = row['data'];
    final status = row['status'] as String?;
    return route_model.Route.fromJson({
      if (data is Map) ...Map<String, dynamic>.from(data),
      'id': row['id'],
      'contributorId': row['contributor_id'],
      'contributorName': row['contributor_name'],
      'views': row['views'],
      'upvotes': row['upvotes'],
      'downvotes': row['downvotes'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      // Screens already know "approved", so "published" stays a server word.
      'approvalStatus': status == 'published' ? 'approved' : status,
      'verification': row['verification'],
      'revision': row['revision'],
      'correctionOf': row['correction_of'],
      'latestDecision': row['latest_decision'],
      'latestChecks': row['latest_checks'],
    });
  }

  static Map<String, int> feedbackSummary(Map<String, dynamic> row) {
    final saved = row['feedback_summary'];
    final summary = saved is Map ? saved : const {};
    return {
      for (final key in const [
        'fareAccurateYes',
        'fareAccurateNo',
        'scheduleAccurateYes',
        'scheduleAccurateNo',
        'stillOperatingYes',
        'stillOperatingNo',
      ])
        key: (summary[key] as num?)?.toInt() ?? 0,
    };
  }
}
