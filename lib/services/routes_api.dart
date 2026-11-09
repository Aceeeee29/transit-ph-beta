import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'route_service.dart' show PendingRouteLimitException;

class RoutesApiException implements Exception {
  final int status;
  final String code;
  final Map<String, dynamic> extra;

  const RoutesApiException(
    this.status,
    this.code, [
    this.extra = const <String, dynamic>{},
  ]);

  @override
  String toString() => 'RoutesApiException($status, $code)';
}

/// Sends route changes to the `routes-api` server function. The server checks
/// the rider's Firebase login and does the writing, so a modified app can't
/// skip its rules.
class RoutesApi {
  RoutesApi._();

  /// Long enough for a sleeping server to wake up. Without a limit, a screen
  /// could wait forever on a bad connection.
  static const _timeout = Duration(seconds: 30);

  @visibleForTesting
  static Future<({int status, dynamic data})> Function(
    String action,
    Map body,
    String token,
  )?
  invoker;

  @visibleForTesting
  static Future<String?> Function(bool forceRefresh)? tokenSource;

  /// Returns the server's data. Throws a [RoutesApiException], or the same
  /// errors the screens already handle. Network failures pass through as they
  /// are, so a screen can tell "offline" from "refused".
  static Future<dynamic> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    final send = invoker ?? _send;
    final getToken = tokenSource ?? _firebaseToken;

    final token = await getToken(false);
    if (token == null) throw const RoutesApiException(401, 'unauthenticated');
    var answer = await send(action, body, token);

    // A login token lasts about an hour, and the app can stay open longer.
    if (answer.status == 401) {
      final fresh = await getToken(true);
      if (fresh == null) throw const RoutesApiException(401, 'unauthenticated');
      answer = await send(action, body, fresh);
    }

    final data = answer.data;
    if (data is! Map) throw RoutesApiException(answer.status, 'bad_response');
    if (data['ok'] == true) return data['data'];
    final code = data['error'];
    if (code is! String)
      throw RoutesApiException(answer.status, 'bad_response');

    final extra =
        Map<String, dynamic>.from(data)
          ..remove('ok')
          ..remove('error');
    throw _toScreenError(answer.status, code, extra);
  }

  /// The screens were written for the errors RouteService used to throw, so
  /// these keep the same form.
  static Object _toScreenError(
    int status,
    String code,
    Map<String, dynamic> extra,
  ) {
    return switch (code) {
      'pending_limit' => const PendingRouteLimitException(),
      'remove_first' => StateError('remove_first'),
      'feedback_cooldown' => StateError(
        'feedback_cooldown:${extra['nextAllowedAt']}',
      ),
      _ => RoutesApiException(status, code, extra),
    };
  }

  static Future<String?> _firebaseToken(bool forceRefresh) async =>
      FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh);

  static Future<({int status, dynamic data})> _send(
    String action,
    Map body,
    String token,
  ) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke(
            'routes-api',
            body: {...body, 'action': action},
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
      return (status: response.status, data: response.data);
    } on FunctionException catch (e) {
      // Any answer outside 2xx lands here, and it holds our error code.
      return (status: e.status, data: e.details);
    }
  }
}
