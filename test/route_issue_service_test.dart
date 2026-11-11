import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/ors_route_result.dart';
import 'package:transitph_beta/services/route_issue_service.dart';
import 'package:transitph_beta/services/routes_api.dart';
import 'package:transitph_beta/services/routing_service.dart';
import 'package:transitph_beta/services/supabase_route_service.dart';

void main() {
  tearDown(() {
    RouteIssueService.resetForTesting();
    RoutesApi.invoker = null;
    RoutesApi.tokenSource = null;
  });

  group('OutdatedLabel', () {
    test('reads a row and names the problems', () {
      final label = OutdatedLabel.fromRow({
        'route_key': 'gtfs:R1',
        'types': ['wrong_fare', 'not_operating', 'nonsense'],
        'riders': 6,
        'updated_at': DateTime.now().toIso8601String(),
      });
      expect(label.types, [
        RouteIssueType.wrongFare,
        RouteIssueType.notOperating,
      ]);
      expect(label.riders, 6);
      expect(label.isCurrent(), isTrue);
      expect(label.summary, 'Riders say: Wrong fare, Not running anymore');
    });

    test('a label nobody touched in 30 days no longer counts', () {
      final now = DateTime(2026, 11, 10);
      OutdatedLabel at(DateTime updated) => OutdatedLabel(
        routeKey: 'r1',
        types: const [RouteIssueType.wrongStop],
        riders: 5,
        updatedAt: updated,
      );
      expect(at(now.subtract(const Duration(days: 29))).isCurrent(now), isTrue);
      expect(
        at(now.subtract(const Duration(days: 31))).isCurrent(now),
        isFalse,
      );
      expect(
        const OutdatedLabel(routeKey: 'r1', types: [], riders: 0).isCurrent(),
        isFalse,
      );
    });
  });

  group('RouteIssueService labels', () {
    test('loads labels and answers by route key', () async {
      RouteIssueService.outdatedReader =
          () async => [
            {
              'route_key': 'r1',
              'types': ['wrong_path'],
              'riders': 5,
              'updated_at': DateTime.now().toIso8601String(),
            },
          ];
      await RouteIssueService.refreshOutdated(force: true);
      expect(RouteIssueService.isOutdated('r1'), isTrue);
      expect(RouteIssueService.isOutdated('r2'), isFalse);
    });

    test('a failed load keeps the last labels', () async {
      RouteIssueService.resetForTesting(
        labels: {
          'r1': OutdatedLabel(
            routeKey: 'r1',
            types: const [RouteIssueType.wrongPath],
            riders: 5,
            updatedAt: DateTime.now(),
          ),
        },
      );
      RouteIssueService.outdatedReader = () async => throw Exception('down');
      await RouteIssueService.refreshOutdated(force: true);
      expect(RouteIssueService.isOutdated('r1'), isTrue);
    });
  });

  group('RouteIssueService.report', () {
    late List<({String action, Map body})> calls;

    setUp(() {
      calls = [];
      RoutesApi.tokenSource = (_) async => 'token';
      RouteIssueService.outdatedReader = () async => const [];
    });

    void answer(Map<String, dynamic> body, {int status = 200}) {
      RoutesApi.invoker = (action, sent, token) async {
        calls.add((action: action, body: sent));
        return (status: status, data: body);
      };
    }

    test('sends only what the rider filled in', () async {
      answer({
        'ok': true,
        'data': {'id': 1, 'outdated': false, 'fareChanged': true},
      });
      final result = await RouteIssueService.report(
        routeKey: 'r1',
        type: RouteIssueType.wrongFare,
        farePaid: 15,
        stepIndex: 0,
        note: '  ',
      );
      expect(result.fareChanged, isTrue);
      expect(calls.single.action, 'report_issue');
      expect(calls.single.body, {
        'routeId': 'r1',
        'type': 'wrong_fare',
        'farePaid': 15.0,
        'stepIndex': 0,
      });
    });

    test('a refused report has a plain message', () async {
      answer({'ok': false, 'error': 'already_reported'}, status: 409);
      Object? error;
      try {
        await RouteIssueService.report(
          routeKey: 'r1',
          type: RouteIssueType.wrongStop,
        );
      } catch (e) {
        error = e;
      }
      expect(error, isA<RoutesApiException>());
      expect(
        RouteIssueService.messageFor(error!),
        'You already reported this. Thanks, it still counts.',
      );
      expect(
        RouteIssueService.messageFor(Exception('offline')),
        "Couldn't send the report. Check your connection.",
      );
    });
  });

  group('search weights', () {
    CommunityRoute route(
      String id, {
      bool verified = true,
      bool outdated = false,
    }) => CommunityRoute(
      id: id,
      startLocation: 'A',
      endLocation: 'B',
      steps: const [],
      verified: verified,
      outdated: outdated,
    );

    test('trusted routes count as they are, others a bit more', () {
      expect(route('r1').weightFactor, 1.0);
      expect(route('osm-bus-1', verified: false).weightFactor, 1.0);
      expect(route('r2', verified: false).weightFactor, 1.15);
      expect(route('r3', outdated: true).weightFactor, 1.5);
      expect(route('osm-bus-2', outdated: true).weightFactor, 1.5);
    });
  });

  group('reportTargetOf', () {
    TransitLeg leg({required String tripId, required String routeId}) =>
        TransitLeg(
          tripId: tripId,
          routeId: routeId,
          boardStopId: 'a',
          alightStopId: 'b',
          boardStopName: 'A',
          alightStopName: 'B',
          boardLat: 14.6,
          boardLon: 121.0,
          alightLat: 14.61,
          alightLon: 121.01,
        );

    test('a rider route ride, forwards or backwards', () {
      const id = '2026-11-09 17:06:38.655619';
      final forward = RoutingService.reportTargetOf(
        leg(tripId: 'community|$id|2', routeId: 'COMMUNITY'),
      );
      expect(forward?.key, id);
      expect(forward?.step, 2);
      final backward = RoutingService.reportTargetOf(
        leg(tripId: 'community|osm-jeep-5|0|rev', routeId: 'COMMUNITY'),
      );
      expect(backward?.key, 'osm-jeep-5');
      expect(backward?.step, 0);
    });

    test('a GTFS line', () {
      final target = RoutingService.reportTargetOf(
        leg(tripId: 'T1', routeId: 'ROUTE_9'),
      );
      expect(target?.key, 'gtfs:ROUTE_9');
      expect(target?.step, isNull);
    });

    test('a ride it cannot trace', () {
      expect(
        RoutingService.reportTargetOf(leg(tripId: 'odd', routeId: 'COMMUNITY')),
        isNull,
      );
    });
  });

  test('a trip step keeps its route through saving', () {
    const step = OrsStep(
      instruction: 'Ride',
      distanceMeters: 1000,
      durationSeconds: 300,
      routeKey: 'gtfs:R1',
      routeStepIndex: 1,
    );
    final copy = OrsStep.fromJson(step.toJson());
    expect(copy.routeKey, 'gtfs:R1');
    expect(copy.routeStepIndex, 1);
    expect(
      OrsStep.fromJson(
        const OrsStep(
          instruction: 'Walk',
          distanceMeters: 10,
          durationSeconds: 10,
        ).toJson(),
      ).routeKey,
      isNull,
    );
  });
}
