import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/models/route_rejection_reason.dart';
import 'package:transitph_beta/services/route_rows.dart';

/// A row as Supabase returns it. Each test changes only what it's about.
Map<String, dynamic> row({
  String status = 'published',
  Map<String, dynamic>? data,
  Map<String, dynamic> extra = const {},
}) => {
  'id': 'r1',
  'source': 'rider',
  'contributor_id': 'uid-1',
  'contributor_name': 'Rider One',
  'status': status,
  'verification': 'unverified',
  'correction_of': null,
  'data':
      data ??
      {
        'id': 'r1',
        'startLocation': 'Monumento',
        'endLocation': 'Malabon',
        'shortDescription': 'Jeep',
        'steps': [
          {'mode': 'Jeepney', 'instruction': 'Ride', 'details': ''},
        ],
        'pathPoints': [
          {'lat': 14.65, 'lng': 120.98},
          {'lat': 14.66, 'lng': 120.99},
        ],
        'reports': <dynamic>[],
      },
  'views': 7,
  'upvotes': 3,
  'downvotes': 1,
  'feedback_summary': {'fareAccurateYes': 4, 'stillOperatingNo': 2},
  'revision': 2,
  'created_at': '2026-11-01T02:00:00.000Z',
  'updated_at': '2026-11-02T02:00:00.000Z',
  'published_at': '2026-11-02T02:00:00.000Z',
  'rejected_at': null,
  ...extra,
};

void main() {
  group('RouteRows.toRoute', () {
    test('a published row is an approved route', () {
      final route = RouteRows.toRoute(row());
      expect(route.approvalStatus, route_model.RouteApprovalStatus.approved);
      expect(route.isApproved, isTrue);
      expect(route.verification, route_model.RouteVerification.unverified);
      expect(route.revision, 2);
      expect(route.contributorId, 'uid-1');
      expect(route.contributorName, 'Rider One');
      expect(route.pathPoints, const [
        LatLng(14.65, 120.98),
        LatLng(14.66, 120.99),
      ]);
    });

    test('the row wins over what is saved inside data', () {
      final route = RouteRows.toRoute(
        row(
          data: {
            'id': 'other',
            'startLocation': 'A',
            'endLocation': 'B',
            'shortDescription': '',
            'steps': <dynamic>[],
            'contributorId': 'someone-else',
            'approvalStatus': 'approved',
            'views': 999,
            'upvotes': 999,
            'downvotes': 999,
          },
          status: 'pending',
        ),
      );
      expect(route.id, 'r1');
      expect(route.contributorId, 'uid-1');
      expect(route.approvalStatus, route_model.RouteApprovalStatus.pending);
      expect(route.views, 7);
      expect(route.upvotes, 3);
      expect(route.downvotes, 1);
    });

    test('dates come from the row', () {
      final route = RouteRows.toRoute(row());
      expect(route.createdAt, DateTime.utc(2026, 11, 1, 2).toLocal());
      expect(route.updatedAt, DateTime.utc(2026, 11, 2, 2).toLocal());
    });

    test('a rejected row carries its reasons and note', () {
      final route = RouteRows.toRoute(
        row(
          status: 'rejected',
          extra: {
            'latest_decision': {
              'decision': 'rejected',
              'reason_codes': ['wrong_fare', 'other'],
              'note': 'The fare is 13',
              'actor': 'mod-1',
              'created_at': '2026-11-03T02:00:00.000Z',
            },
          },
        ),
      );
      expect(route.approvalStatus, route_model.RouteApprovalStatus.rejected);
      final decision = route.latestDecision!;
      expect(decision.decision, 'rejected');
      expect(decision.reasonCodes, ['wrong_fare', 'other']);
      expect(decision.note, 'The fare is 13');
      expect(decision.actor, 'mod-1');
      expect(decision.createdAt, DateTime.utc(2026, 11, 3, 2).toLocal());
    });

    test('a withdrawn row keeps its status', () {
      final route = RouteRows.toRoute(row(status: 'withdrawn'));
      expect(route.approvalStatus, route_model.RouteApprovalStatus.withdrawn);
      expect(route.isApproved, isFalse);
    });

    test('a correction keeps what it corrects', () {
      final route = RouteRows.toRoute(
        row(extra: {'correction_of': 'gtfs:LTFRB_1'}),
      );
      expect(route.correctionOf, 'gtfs:LTFRB_1');
    });

    test('a Former rider route has no contributor id', () {
      final route = RouteRows.toRoute(
        row(
          extra: {'contributor_id': null, 'contributor_name': 'Former rider'},
        ),
      );
      expect(route.contributorId, isNull);
      expect(route.contributorName, 'Former rider');
    });

    test('old routes with fields missing still parse', () {
      // Firestore has routes from before these fields existed.
      final route = RouteRows.toRoute(
        row(
          data: {
            'startLocation': 'A',
            'endLocation': 'B',
            'shortDescription': 'Old',
            'steps': [
              {'mode': 'Ferry', 'instruction': 'Ride', 'details': ''},
            ],
          },
          extra: {'created_at': null, 'updated_at': null},
        ),
      );
      expect(route.createdAt, isNull);
      expect(route.updatedAt, isNull);
      expect(route.pathPoints, isEmpty);
      expect(route.reports, isEmpty);
      expect(route.stepBoundaries, isEmpty);
      expect(route.steps.single.mode, 'Boat');
    });

    test('a row with no data at all gives an empty route, not a crash', () {
      final route = RouteRows.toRoute(row(data: {}));
      expect(route.id, 'r1');
      expect(route.startLocation, '');
      expect(route.endLocation, '');
      expect(route.steps, isEmpty);
    });
  });

  group('RouteRows.feedbackSummary', () {
    test('gives all 6 counters, missing ones as 0', () {
      expect(RouteRows.feedbackSummary(row()), {
        'fareAccurateYes': 4,
        'fareAccurateNo': 0,
        'scheduleAccurateYes': 0,
        'scheduleAccurateNo': 0,
        'stillOperatingYes': 0,
        'stillOperatingNo': 2,
      });
    });

    test('handles no summary, and counters like 3.0', () {
      expect(
        RouteRows.feedbackSummary({'feedback_summary': null}).values.toSet(),
        {0},
      );
      expect(
        RouteRows.feedbackSummary({
          'feedback_summary': {'fareAccurateYes': 3.0},
        })['fareAccurateYes'],
        3,
      );
    });
  });

  group('Route.fromJson dates', () {
    Map<String, dynamic> withEditedAt(dynamic value) => {
      'id': 'r1',
      'startLocation': 'A',
      'endLocation': 'B',
      'shortDescription': '',
      'steps': <dynamic>[],
      'pathPoints': <dynamic>[],
      'reports': <dynamic>[],
      'editedAt': value,
    };
    final expected = DateTime.utc(2026, 9, 30, 6, 5).toLocal();

    test('accepts a Firestore Timestamp, ISO text, milliseconds or null', () {
      DateTime? read(dynamic value) =>
          route_model.Route.fromJson(withEditedAt(value)).editedAt;
      expect(read(Timestamp.fromDate(expected)), expected);
      expect(read('2026-09-30T06:05:00.000Z'), expected);
      expect(read(expected.millisecondsSinceEpoch), expected);
      expect(read(null), isNull);
    });

    test('text that is not a date is treated as no date', () {
      final route = route_model.Route.fromJson(withEditedAt('not a date'));
      expect(route.editedAt, isNull);
    });
  });

  group('Route.toJson', () {
    route_model.Route edited() => route_model.Route(
      id: 'r1',
      startLocation: 'A',
      endLocation: 'B',
      shortDescription: '',
      steps: [
        route_model.Step(mode: 'Jeepney', instruction: 'Ride', details: ''),
      ],
      isEdited: true,
      editedAt: DateTime.utc(2026, 9, 30, 6, 5),
      editCount: 2,
    );

    test('can be sent as plain JSON, even for an edited route', () {
      // routes-api gets it through jsonEncode. A Firestore Timestamp in here
      // used to make that throw.
      final sent = jsonDecode(jsonEncode(edited().toJson()));
      expect(sent['editedAt'], '2026-09-30T06:05:00.000Z');
    });

    test('survives a round trip', () {
      final back = route_model.Route.fromJson(
        jsonDecode(jsonEncode(edited().toJson())) as Map<String, dynamic>,
      );
      expect(back.editedAt, DateTime.utc(2026, 9, 30, 6, 5).toLocal());
      expect(back.editCount, 2);
      expect(back.verification, route_model.RouteVerification.verified);
      expect(back.revision, 1);
    });

    test('routes saved before these fields default to verified', () {
      final old = route_model.Route.fromJson({
        'id': 'r1',
        'startLocation': 'A',
        'endLocation': 'B',
        'shortDescription': '',
        'steps': <dynamic>[],
        'pathPoints': <dynamic>[],
        'reports': <dynamic>[],
      });
      expect(old.verification, route_model.RouteVerification.verified);
      expect(old.revision, 1);
      expect(old.latestDecision, isNull);
      expect(old.contributorName, isNull);
    });
  });

  group('RouteRejectionReason', () {
    test('has the 8 codes, in order, matching the server', () {
      expect(RouteRejectionReason.all.map((r) => r.code), [
        'incomplete',
        'outside_area',
        'wrong_path',
        'wrong_fare',
        'duplicate',
        'not_operating',
        'unsafe_or_spam',
        'other',
      ]);
    });

    test('only Other needs a note', () {
      expect(
        RouteRejectionReason.all.where((r) => r.needsNote).map((r) => r.code),
        ['other'],
      );
    });

    test('byCode finds a reason, and null for an unknown one', () {
      expect(RouteRejectionReason.byCode('wrong_fare')?.label, 'Fare is wrong');
      expect(RouteRejectionReason.byCode('made_up'), isNull);
    });
  });
}
