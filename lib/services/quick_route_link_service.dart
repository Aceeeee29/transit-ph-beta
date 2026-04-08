import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/route.dart' as route_model;

class QuickRouteLinkPayload {
  final String token;
  final route_model.Route draftRoute;
  final DateTime expiresAt;

  const QuickRouteLinkPayload({
    required this.token,
    required this.draftRoute,
    required this.expiresAt,
  });
}

class QuickRouteLinkService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _ttl = Duration(hours: 24);
  static const _linksCollection = 'quick_route_links';
  static const _quickRoutesCollection = 'quick_routes';

  static String _generateToken() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String buildShareUrl(String token) {
    final base = Config.quickRouteBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/q/$token';
  }

  static Future<String> createLink({
    required route_model.Route draftRoute,
    required String ownerId,
  }) async {
    final token = _generateToken();
    final expiresAt = DateTime.now().toUtc().add(_ttl);

    await _firestore.collection(_linksCollection).doc(token).set({
      'token': token,
      'ownerId': ownerId,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'draftRoute': draftRoute.toJson(),
      'isQuickRoute': true,
    });

    return token;
  }

  static Future<QuickRouteLinkPayload?> getValidLink(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;

    final doc = await _firestore.collection(_linksCollection).doc(trimmed).get();
    if (!doc.exists) return null;

    final data = doc.data();
    if (data == null) return null;

    final expiresAtRaw = data['expiresAt'];
    final expiresAt = expiresAtRaw is Timestamp ? expiresAtRaw.toDate() : null;
    if (expiresAt == null || expiresAt.isBefore(DateTime.now().toUtc())) {
      return null;
    }

    final draft = data['draftRoute'];
    if (draft is! Map) return null;
    final draftMap = Map<String, dynamic>.from(draft);

    return QuickRouteLinkPayload(
      token: trimmed,
      draftRoute: route_model.Route.fromJson(draftMap),
      expiresAt: expiresAt,
    );
  }

  static Future<void> createQuickRouteFromLink({
    required String token,
    required route_model.Route route,
    required String creatorId,
  }) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw StateError('Missing quick link token.');
    }

    final linkRef = _firestore.collection(_linksCollection).doc(normalizedToken);
    final quickRouteRef = _firestore.collection(_quickRoutesCollection).doc();

    await _firestore.runTransaction((tx) async {
      final linkSnap = await tx.get(linkRef);
      if (!linkSnap.exists) {
        throw StateError('This quick link no longer exists.');
      }

      final data = linkSnap.data() ?? <String, dynamic>{};
      final expiresAtRaw = data['expiresAt'];
      final expiresAt = expiresAtRaw is Timestamp ? expiresAtRaw.toDate() : null;
      if (expiresAt == null || expiresAt.isBefore(DateTime.now().toUtc())) {
        throw StateError('This quick link has expired.');
      }

      final routeTtl = DateTime.now().toUtc().add(_ttl);
      final payload = <String, dynamic>{
        ...route.toJson(),
        'sourceToken': normalizedToken,
        'creatorId': creatorId,
        'isQuickRoute': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(routeTtl),
      };

      tx.set(quickRouteRef, payload);
    });
  }
}
