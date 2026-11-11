import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../models/notification.dart';
import '../models/route.dart' as route_model;
import '../models/route_rejection_reason.dart';
import '../services/notifications_service.dart';
import 'route_issue_service.dart';
import 'route_rows.dart';
import 'routes_api.dart';

/// The rider already has [RouteService.maxPendingRoutesPerUser] routes
/// waiting for review. Its text is shown to them as is.
class PendingRouteLimitException implements Exception {
  const PendingRouteLimitException();

  @override
  String toString() =>
      'You already have ${RouteService.maxPendingRoutesPerUser} routes '
      'waiting for review. You can send more once a moderator reviews them.';
}

/// What the automatic checks decided about a route that was just sent.
class RouteSubmitResult {
  /// 'published', 'pending', 'rejected', or 'applied' for a fare correction
  /// that went straight into the route it corrects.
  final String outcome;
  final List<route_model.RouteCheck> checks;

  const RouteSubmitResult({required this.outcome, this.checks = const []});

  factory RouteSubmitResult.fromApi(dynamic data) {
    final map = data is Map ? data : const {};
    return RouteSubmitResult(
      // Waiting for a person is the safe thing to say if we can't tell.
      outcome: map['outcome'] as String? ?? 'pending',
      checks: route_model.RouteCheck.listFromJson(map['checks']),
    );
  }

  bool get isLive => outcome == 'published';
  bool get isRejected => outcome == 'rejected';
  bool get isApplied => outcome == 'applied';
  bool get isWaiting => outcome == 'pending';

  List<route_model.RouteCheck> get failed =>
      checks.where((c) => c.failed).toList();
  List<route_model.RouteCheck> get flagged =>
      checks.where((c) => c.flagged).toList();
}

typedef PublishedRowsReader =
    Future<List<Map<String, dynamic>>> Function({
      String? contributorId,
      String? routeId,
    });

/// Rider and OpenStreetMap routes live in Supabase. Anyone can read published
/// ones directly, and every change goes through the `routes-api` server
/// function, so a modified app can't skip its rules.
///
/// Notifications and contribution stats stay in Firestore. The moderator's app
/// writes those after a decision succeeds.
class RouteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// How many routes one rider may have waiting for review at once. The server
  /// enforces it. This is only for the message.
  static const maxPendingRoutesPerUser = 3;

  // Leaves out the geometry columns. The path is already in data.
  static const _rowColumns =
      'id,source,contributor_id,contributor_name,status,verification,'
      'correction_of,data,views,upvotes,downvotes,feedback_summary,revision,'
      'created_at,updated_at,published_at,rejected_at';

  // Supabase returns at most this many rows per request.
  static const _pageSize = 1000;
  static const _readTimeout = Duration(seconds: 20);
  static const _cacheFileName = 'published_routes.json';

  // Opening one route asks for its vote, feedback and summary separately, and
  // a route list asks for every card's summary. These keep that to one call.
  static const _rememberFor = Duration(seconds: 60);
  static final _openResults =
      <String, ({DateTime at, Future<Map<String, dynamic>> result})>{};
  static final _summaries =
      <String, ({DateTime at, Map<String, int> summary})>{};

  @visibleForTesting
  static Future<void> Function(NotificationModel)? notifyHook;
  @visibleForTesting
  static Future<void> Function(String uid)? statsHook;
  @visibleForTesting
  static String? Function()? currentUidHook;
  @visibleForTesting
  static Future<File> Function()? cacheFileHook;
  @visibleForTesting
  static PublishedRowsReader? publishedReader;

  @visibleForTesting
  static void resetForTesting() {
    notifyHook = null;
    statsHook = null;
    currentUidHook = null;
    cacheFileHook = null;
    publishedReader = null;
    _openResults.clear();
    _summaries.clear();
  }

  static String? _currentUid() =>
      (currentUidHook ?? () => FirebaseAuth.instance.currentUser?.uid)();

  // Reading routes

  static Future<List<Map<String, dynamic>>> _readPublished({
    String? contributorId,
    String? routeId,
  }) {
    final reader = publishedReader ?? _readPublishedFromSupabase;
    return reader(
      contributorId: contributorId,
      routeId: routeId,
    ).timeout(_readTimeout);
  }

  static Future<List<Map<String, dynamic>>> _readPublishedFromSupabase({
    String? contributorId,
    String? routeId,
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (var from = 0; ; from += _pageSize) {
      var query = Supabase.instance.client
          .from('transit_routes')
          .select(_rowColumns)
          .eq('status', 'published');
      if (contributorId != null) {
        query = query.eq('contributor_id', contributorId);
      }
      if (routeId != null) query = query.eq('id', routeId);
      // The id keeps the order fixed between pages when dates are equal.
      final page = await query
          .order('created_at', ascending: false, nullsFirst: false)
          .order('id')
          .range(from, from + _pageSize - 1);
      rows.addAll(page);
      if (page.length < _pageSize) return rows;
    }
  }

  /// One bad row must not lose every other route.
  static List<route_model.Route> _routesFrom(Iterable<dynamic> rows) {
    final routes = <route_model.Route>[];
    for (final row in rows) {
      try {
        routes.add(RouteRows.toRoute(Map<String, dynamic>.from(row as Map)));
      } catch (e) {
        debugPrint('[RouteService] Skipped a route that would not parse: $e');
      }
    }
    return routes;
  }

  static Future<File> _cacheFile() async {
    final hook = cacheFileHook;
    if (hook != null) return hook();
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_cacheFileName');
  }

  static Future<void> _saveToPhone(List<Map<String, dynamic>> rows) async {
    try {
      await (await _cacheFile()).writeAsString(jsonEncode(rows));
    } catch (e) {
      debugPrint('[RouteService] Could not save routes for offline: $e');
    }
  }

  static Future<List<dynamic>> _loadFromPhone() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return const [];
      return jsonDecode(await file.readAsString()) as List<dynamic>;
    } catch (e) {
      debugPrint('[RouteService] Could not read saved routes: $e');
      return const [];
    }
  }

  /// Published routes, the ones regular users see. Firestore used to keep an
  /// offline copy by itself and Supabase doesn't, so the last list is saved on
  /// the phone. Without that, a bad connection would empty search's rider
  /// routes.
  static Future<List<route_model.Route>> getAllRoutes() async {
    // The "Possibly outdated" labels load alongside, so lists and search can
    // show them. A failure there keeps the last ones and never stops routes.
    final labels = RouteIssueService.refreshOutdated();
    try {
      final rows = await _readPublished();
      await labels;
      for (final row in rows) {
        _rememberSummary(row['id'] as String, RouteRows.feedbackSummary(row));
      }
      await _saveToPhone(rows);
      return _routesFrom(rows);
    } catch (e) {
      debugPrint('[RouteService] Using saved routes: $e');
      return _routesFrom(await _loadFromPhone());
    }
  }

  /// The moderator queue, newest first. A failure throws, so the screen can
  /// keep what it has instead of showing an empty queue.
  static Future<List<route_model.Route>> getPendingRoutes() async {
    return _routesFrom(await RoutesApi.call('queue') as List<dynamic>);
  }

  /// Your own routes at any status, or someone else's published ones.
  ///
  /// A failure throws. Returning an empty list would look like "no routes", and
  /// recalculateUserStats would then save zeroed stats.
  static Future<List<route_model.Route>> getRoutesByUser(
    String userId, {
    String? userEmail,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return [];
    if (uid == _currentUid()) {
      return _routesFrom(await RoutesApi.call('my_routes') as List<dynamic>);
    }
    return _routesFrom(await _readPublished(contributorId: uid));
  }

  /// A published route, or one of your own at any status. A rejected route's
  /// notification opens it, and riders can't read those directly.
  static Future<route_model.Route?> getRouteById(String routeId) async {
    try {
      final published = _routesFrom(await _readPublished(routeId: routeId));
      if (published.isNotEmpty) return published.first;
      if (_currentUid() == null) return null;
      final mine = _routesFrom(
        await RoutesApi.call('my_routes') as List<dynamic>,
      );
      for (final route in mine) {
        if (route.id == routeId) return route;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Sending routes

  /// Routes the checks rejected while their editor may still be open. The
  /// server keeps a rejected route, so sending it again must update that one.
  /// A fresh submit would leave the rejected copy behind in Profile.
  static final Set<String> _rejectedOnSend = {};

  /// Sends a new route through the automatic checks. Failures reach the screen,
  /// which keeps the rider's drawing. Sending a route again after the checks
  /// rejected it updates the same route.
  static Future<RouteSubmitResult> saveRoute(route_model.Route route) async {
    final resend = _rejectedOnSend.contains(route.id);
    final result = RouteSubmitResult.fromApi(
      await RoutesApi.call(resend ? 'resubmit' : 'submit', {
        'route': route.toJson(),
      }),
    );
    if (result.isRejected) {
      _rejectedOnSend.add(route.id);
    } else {
      _rejectedOnSend.remove(route.id);
    }
    // No moderator is involved when the checks publish it, so the credit a
    // moderator's approval would have given has to be added here.
    if (result.isLive) {
      final uid = _currentUid();
      if (uid != null) await _addStats(uid);
    }
    return result;
  }

  /// Updates an existing route. Any edit is checked again.
  static Future<RouteSubmitResult> updateRoute(route_model.Route route) async {
    return RouteSubmitResult.fromApi(
      await RoutesApi.call('resubmit', {'route': route.toJson()}),
    );
  }

  static Future<void> deleteRoute(String routeId) async {
    await RoutesApi.call('delete', {'routeId': routeId});
  }

  // Moderator decisions

  /// Sends a decision. Returns null when someone already decided, or removed
  /// the route. That's a double tap or two moderators at once, so it isn't an
  /// error, and nobody should be notified a second time.
  static Future<Map<String, dynamic>?> _decide(
    Map<String, dynamic> body,
  ) async {
    try {
      final result = await RoutesApi.call('decide', body);
      return Map<String, dynamic>.from(result as Map);
    } on RoutesApiException catch (e) {
      if (e.code == 'conflict' || e.code == 'not_found') return null;
      rethrow;
    }
  }

  static Future<void> _notify(NotificationModel notification) async {
    try {
      await (notifyHook ?? NotificationsService.addNotification)(notification);
    } catch (e) {
      // The decision is already saved. A failed notice must not undo it.
      debugPrint('[RouteService] Notification failed: $e');
    }
  }

  static Future<void> _addStats(String uid) async {
    try {
      await (statsHook ?? _incrementApprovedContributionStats)(uid);
    } catch (e) {
      debugPrint('[RouteService] Contribution stats failed: $e');
    }
  }

  /// A person vouching for a live route, or taking that back. It stays live.
  static Future<void> setVerified(String routeId, bool verified) async {
    await _decide({
      'routeId': routeId,
      'decision': verified ? 'verify' : 'unverify',
    });
  }

  /// Approve a route. Only moderators call this, and the server checks. Going
  /// against a flagged check needs a [note] saying why.
  static Future<void> approveRoute(String routeId, {String? note}) async {
    final trimmedNote = note?.trim();
    final result = await _decide({
      'routeId': routeId,
      'decision': 'approve',
      if (trimmedNote != null && trimmedNote.isNotEmpty) 'note': trimmedNote,
    });
    if (result == null) return;

    final recipientId = await _resolveNotificationRecipientId(
      result['contributorId'] as String?,
    );
    if (recipientId == null || recipientId.isEmpty) return;

    await _addStats(recipientId);

    final title = result['title'] as String? ?? 'your submitted route';
    final mergedInto = result['mergedInto'] as String?;
    await _notify(
      NotificationModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: recipientId,
        type: 'route_approved',
        routeId: mergedInto ?? routeId,
        timestamp: DateTime.now(),
        message:
            mergedInto != null
                ? 'Your correction to $title was approved and is now live.'
                : 'Your submitted route ($title) was approved and is now live.',
      ),
    );
  }

  /// Reject a route. The server keeps it, so the contributor can read why and
  /// resubmit.
  static Future<void> rejectRoute(
    String routeId, {
    required List<String> reasonCodes,
    String? note,
  }) async {
    final trimmedNote = note?.trim();
    final hasNote = trimmedNote != null && trimmedNote.isNotEmpty;
    final result = await _decide({
      'routeId': routeId,
      'decision': 'reject',
      'reasonCodes': reasonCodes,
      if (hasNote) 'note': trimmedNote,
    });
    if (result == null) return;

    final recipientId = await _resolveNotificationRecipientId(
      result['contributorId'] as String?,
    );
    if (recipientId == null || recipientId.isEmpty) return;

    final title = result['title'] as String? ?? 'your submitted route';
    final reasons = reasonCodes
        .map((code) => RouteRejectionReason.byCode(code)?.label ?? code)
        .join(', ');
    await _notify(
      NotificationModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: recipientId,
        type: 'route_rejected',
        routeId: routeId,
        timestamp: DateTime.now(),
        message:
            'Your route ($title) was rejected: $reasons.'
            '${hasNote ? ' Note: $trimmedNote' : ''}',
      ),
    );
  }

  /// Older routes can hold an email instead of a uid.
  static Future<String?> _resolveNotificationRecipientId(
    String? contributorId,
  ) async {
    final raw = contributorId?.trim();
    if (raw == null || raw.isEmpty) return null;

    if (!raw.contains('@')) {
      return raw;
    }

    try {
      final userByEmail =
          await _firestore
              .collection('users')
              .where('email', isEqualTo: raw)
              .limit(1)
              .get();
      if (userByEmail.docs.isNotEmpty) {
        final data = userByEmail.docs.first.data();
        final uidFromField = (data['uid'] as String?)?.trim();
        if (uidFromField != null && uidFromField.isNotEmpty) {
          return uidFromField;
        }
        return userByEmail.docs.first.id;
      }
    } catch (_) {}

    return null;
  }

  static Future<void> _incrementApprovedContributionStats(
    String contributorUid,
  ) async {
    final uid = contributorUid.trim();
    if (uid.isEmpty) return;

    final userRef = _firestore.collection('users').doc(uid);
    await userRef.set({
      'routesContributed': FieldValue.increment(1),
      'contributionCount': FieldValue.increment(1),
    }, SetOptions(merge: true));

    final userSnap = await userRef.get();
    if (!userSnap.exists) return;

    final data = userSnap.data() ?? const <String, dynamic>{};
    final routesContributed =
        (data['routesContributed'] as num?)?.toInt() ??
        (data['contributionCount'] as num?)?.toInt() ??
        0;
    final unlockedAchievements = List<String>.from(
      data['achievements'] ?? const <String>[],
    );
    final unlockedBadges = List<String>.from(
      data['badges'] ?? const <String>[],
    );

    final pioneerUnlocked = routesContributed >= 10;
    final heroUnlocked = routesContributed >= 50;
    final contributorBadgeUnlocked = routesContributed >= 10;

    final newlyUnlockedAchievements = <String>[];
    final newlyUnlockedBadges = <String>[];

    if (pioneerUnlocked && !unlockedAchievements.contains('route_pioneer')) {
      newlyUnlockedAchievements.add('route_pioneer');
    }
    if (heroUnlocked && !unlockedAchievements.contains('community_hero')) {
      newlyUnlockedAchievements.add('community_hero');
    }
    if (contributorBadgeUnlocked && !unlockedBadges.contains('contributor')) {
      newlyUnlockedBadges.add('contributor');
    }

    await userRef.collection('achievements').doc('route_pioneer').set({
      'id': 'route_pioneer',
      'progress': routesContributed,
      'isUnlocked': pioneerUnlocked,
      if (newlyUnlockedAchievements.contains('route_pioneer'))
        'unlockedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await userRef.collection('achievements').doc('community_hero').set({
      'id': 'community_hero',
      'progress': routesContributed,
      'isUnlocked': heroUnlocked,
      if (newlyUnlockedAchievements.contains('community_hero'))
        'unlockedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await userRef.collection('badges').doc('contributor').set({
      'id': 'contributor',
      'isUnlocked': contributorBadgeUnlocked,
      if (newlyUnlockedBadges.contains('contributor'))
        'earnedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final userUpdates = <String, dynamic>{};
    if (newlyUnlockedAchievements.isNotEmpty) {
      userUpdates['achievements'] = FieldValue.arrayUnion(
        newlyUnlockedAchievements,
      );
    }
    if (newlyUnlockedBadges.isNotEmpty) {
      userUpdates['badges'] = FieldValue.arrayUnion(newlyUnlockedBadges);
    }

    if (userUpdates.isNotEmpty) {
      await userRef.set(userUpdates, SetOptions(merge: true));
    }
  }

  // Opening a route: views, votes and feedback

  /// One server call per route per minute, however many reads ask for it.
  /// Calls at the same moment share it too, because the screen loads its parts
  /// side by side.
  static Future<Map<String, dynamic>> _openRoute(String routeId) {
    final saved = _openResults[routeId];
    if (saved != null && DateTime.now().difference(saved.at) < _rememberFor) {
      return saved.result;
    }

    final result = RoutesApi.call('open_route', {'routeId': routeId}).then((
      data,
    ) {
      final opened = Map<String, dynamic>.from(data as Map);
      final summary = opened['summary'];
      if (summary is Map) {
        _rememberSummary(
          routeId,
          RouteRows.feedbackSummary({'feedback_summary': summary}),
        );
      }
      return opened;
    });
    _openResults[routeId] = (at: DateTime.now(), result: result);
    // A failure shouldn't be remembered, so the next read tries again.
    result.then(
      (_) {},
      onError: (_) {
        _openResults.remove(routeId);
      },
    );
    return result;
  }

  /// Counts a view once per user. The server knows who's calling, so [userId]
  /// isn't sent.
  static Future<void> incrementViewForUser(
    String routeId,
    String userId,
  ) async {
    await _openRoute(routeId);
  }

  /// Returns true for upvote, false for downvote, null if no vote
  static Future<bool?> getUserVote(String routeId, String userId) async {
    try {
      final vote = (await _openRoute(routeId))['vote'] as String?;
      if (vote == 'up') return true;
      if (vote == 'down') return false;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Applies an up/down vote. Tapping the same vote again removes it, and
  /// switching needs removing it first (a StateError the screen handles).
  static Future<bool?> setUserVote({
    required String routeId,
    required String userId,
    required bool isUpvote,
  }) async {
    final result = await RoutesApi.call('vote', {
      'routeId': routeId,
      'up': isUpvote,
    });
    _openResults.remove(routeId);
    final vote = (result as Map)['vote'] as String?;
    return vote == null ? null : vote == 'up';
  }

  static Future<void> submitRouteQualityFeedback({
    required String routeId,
    required String userId,
    required bool fareAccurate,
    required bool scheduleAccurate,
    required bool stillOperating,
  }) async {
    await RoutesApi.call('quality_feedback', {
      'routeId': routeId,
      'fareAccurate': fareAccurate,
      'scheduleAccurate': scheduleAccurate,
      'stillOperating': stillOperating,
    });
    _openResults.remove(routeId);
    _summaries.remove(routeId);
  }

  static Future<Map<String, bool>?> getUserRouteQualityFeedback({
    required String routeId,
    required String userId,
  }) async {
    try {
      final feedback = (await _openRoute(routeId))['feedback'];
      if (feedback is! Map) return null;
      return {
        'fareAccurate': feedback['fareAccurate'] as bool? ?? true,
        'scheduleAccurate': feedback['scheduleAccurate'] as bool? ?? true,
        'stillOperating': feedback['stillOperating'] as bool? ?? true,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> getUserRouteFeedbackNextAllowedAt({
    required String routeId,
    required String userId,
  }) async {
    try {
      final next = (await _openRoute(routeId))['nextFeedbackAt'] as String?;
      return next == null ? null : DateTime.tryParse(next)?.toLocal();
    } catch (_) {
      return null;
    }
  }

  static void _rememberSummary(String routeId, Map<String, int> summary) {
    _summaries[routeId] = (at: DateTime.now(), summary: summary);
  }

  static Future<Map<String, int>> getRouteFeedbackSummary(
    String routeId,
  ) async {
    final saved = _summaries[routeId];
    if (saved != null && DateTime.now().difference(saved.at) < _rememberFor) {
      return saved.summary;
    }
    try {
      final rows = await _readPublished(routeId: routeId);
      final summary = RouteRows.feedbackSummary(
        rows.isEmpty ? const {} : rows.first,
      );
      if (rows.isNotEmpty) _rememberSummary(routeId, summary);
      return summary;
    } catch (_) {
      return RouteRows.feedbackSummary(const {});
    }
  }

  static Stream<Map<String, int>> watchRouteFeedbackSummary(String routeId) {
    return Stream.fromFuture(getRouteFeedbackSummary(routeId));
  }
}
