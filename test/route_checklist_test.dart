import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/fare_matrix.dart';
import 'package:transitph_beta/services/route_rows.dart';
import 'package:transitph_beta/services/route_service.dart';
import 'package:transitph_beta/services/routes_api.dart';
import 'package:transitph_beta/widgets/moderation/approve_note_dialog.dart';
import 'package:transitph_beta/widgets/moderation/route_checklist.dart';

const failed = route_model.RouteCheck(
  code: 'H_FARE_IMPOSSIBLE',
  result: 'fail',
  message: 'The fare is too high',
);
const flagged = route_model.RouteCheck(
  code: 'S_NEW_CONTRIBUTOR',
  result: 'flag',
  message: 'New contributor',
);
const passed = route_model.RouteCheck(
  code: 'H_COORDS',
  result: 'pass',
  message: 'Every point is in the Philippines',
);
const skipped = route_model.RouteCheck(
  code: 'H_TARGET',
  result: 'skip',
  message: "This isn't a correction",
);

route_model.Route sample() => route_model.Route(
  id: 'r1',
  startLocation: 'A',
  endLocation: 'B',
  shortDescription: '',
  steps: [route_model.Step(mode: 'Jeepney', instruction: 'Ride', details: '')],
);

void main() {
  group('RouteRows and checks', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
      'id': 'r1',
      'status': 'published',
      'verification': 'unverified',
      'data': sample().toJson(),
      ...extra,
    };

    test('checks come through, with their messages', () {
      final route = RouteRows.toRoute(
        row({
          'latest_checks': [
            {
              'code': 'S_AREA',
              'result': 'flag',
              'message': 'Outside',
              'detail': {},
            },
            {'code': 'H_COORDS', 'result': 'pass', 'message': 'Fine'},
          ],
        }),
      );
      expect(route.checks, hasLength(2));
      expect(route.flaggedChecks.single.message, 'Outside');
      expect(route.failedChecks, isEmpty);
    });

    test('public rows have no checks, and that is fine', () {
      expect(RouteRows.toRoute(row({})).checks, isEmpty);
    });

    test('a live unverified route is marked', () {
      expect(RouteRows.toRoute(row({})).isUnverified, isTrue);
      expect(
        RouteRows.toRoute(row({'verification': 'verified'})).isUnverified,
        isFalse,
      );
    });

    test('a pending route is not called unverified', () {
      expect(
        RouteRows.toRoute(row({'status': 'pending'})).isUnverified,
        isFalse,
      );
    });

    test('routes saved before this have no flags and aren\'t unverified', () {
      final old = route_model.Route.fromJson({
        'id': 'r1',
        'approvalStatus': 'approved',
      });
      expect(old.checks, isEmpty);
      expect(old.isUnverified, isFalse);
    });

    test('checks survive being saved on the phone', () {
      final saved = route_model.Route(
        id: 'r1',
        startLocation: 'A',
        endLocation: 'B',
        shortDescription: '',
        steps: const [],
        checks: const [flagged],
      );
      final back = route_model.Route.fromJson(saved.toJson());
      expect(back.flaggedChecks.single.message, 'New contributor');
    });
  });

  group('RouteSubmitResult', () {
    test('reads each outcome', () {
      expect(
        RouteSubmitResult.fromApi({'outcome': 'published'}).isLive,
        isTrue,
      );
      expect(
        RouteSubmitResult.fromApi({'outcome': 'rejected'}).isRejected,
        isTrue,
      );
      expect(
        RouteSubmitResult.fromApi({'outcome': 'applied'}).isApplied,
        isTrue,
      );
      expect(
        RouteSubmitResult.fromApi({'outcome': 'pending'}).isWaiting,
        isTrue,
      );
    });

    test('an answer it can\'t read says waiting, never live', () {
      expect(RouteSubmitResult.fromApi(null).isWaiting, isTrue);
      expect(RouteSubmitResult.fromApi({'id': 'r1'}).isLive, isFalse);
    });

    test('sorts the checks that matter', () {
      final result = RouteSubmitResult.fromApi({
        'outcome': 'rejected',
        'checks': [
          {'code': 'A', 'result': 'fail', 'message': 'bad'},
          {'code': 'B', 'result': 'flag', 'message': 'look'},
          {'code': 'C', 'result': 'pass', 'message': 'ok'},
        ],
      });
      expect(result.failed.single.code, 'A');
      expect(result.flagged.single.code, 'B');
    });
  });

  group('RouteService with outcomes', () {
    late List<String> stats;
    late List<Map> bodies;
    late Object? Function() answer;

    setUp(() {
      stats = [];
      bodies = [];
      RouteService.resetForTesting();
      RouteService.statsHook = (uid) async => stats.add(uid);
      RouteService.notifyHook = (_) async {};
      RouteService.currentUidHook = () => 'me';
      RoutesApi.tokenSource = (_) async => 'token';
      RoutesApi.invoker = (action, body, token) async {
        bodies.add(body);
        return (status: 200, data: {'ok': true, 'data': answer()});
      };
    });

    tearDown(() {
      RoutesApi.invoker = null;
      RoutesApi.tokenSource = null;
      RouteService.resetForTesting();
    });

    test('a route the checks publish earns the contribution credit', () async {
      answer = () => {'outcome': 'published'};
      final result = await RouteService.saveRoute(sample());
      expect(result.isLive, isTrue);
      expect(stats, ['me']);
    });

    test('a waiting or rejected route earns nothing yet', () async {
      for (final outcome in ['pending', 'rejected', 'applied']) {
        answer = () => {'outcome': outcome};
        await RouteService.saveRoute(sample());
      }
      expect(stats, isEmpty);
    });

    test('editing a route never earns it again', () async {
      answer = () => {'outcome': 'published'};
      final result = await RouteService.updateRoute(sample());
      expect(result.isLive, isTrue);
      expect(stats, isEmpty);
    });

    test('approving sends the moderator\'s note', () async {
      answer = () => {'route': {}, 'contributorId': null, 'title': 'A to B'};
      await RouteService.approveRoute('r1', note: '  Checked it  ');
      expect(bodies.single, {
        'routeId': 'r1',
        'decision': 'approve',
        'note': 'Checked it',
      });
    });

    test('verifying and unverifying send the right decision', () async {
      answer = () => {'route': {}};
      await RouteService.setVerified('r1', true);
      await RouteService.setVerified('r1', false);
      expect(bodies.map((b) => b['decision']), ['verify', 'unverify']);
    });
  });

  group('PhFareCalculator.applyRules', () {
    late FareRule jeepney;
    late FareRule busOrdinary;
    late FareRule busAircon;

    setUp(() {
      jeepney = PhFareCalculator.jeepney;
      busOrdinary = PhFareCalculator.busOrdinary;
      busAircon = PhFareCalculator.busAircon;
    });

    tearDown(() {
      PhFareCalculator.jeepney = jeepney;
      PhFareCalculator.busOrdinary = busOrdinary;
      PhFareCalculator.busAircon = busAircon;
    });

    test('the server\'s rates change what riders see', () {
      PhFareCalculator.applyRules([
        {'mode': 'jeepney', 'base': 15, 'base_km': 4, 'per_km': 2},
        {'mode': 'bus', 'base': 20, 'base_km': 5, 'per_km': 2.5},
      ]);
      expect(PhFareCalculator.compute('Jeepney', 4000), 15);
      expect(PhFareCalculator.compute('Jeepney', 5000), 17);
      expect(PhFareCalculator.compute('Bus', 5000), 20);
    });

    test('the first row for a mode is the newest, so it wins', () {
      PhFareCalculator.applyRules([
        {'mode': 'jeepney', 'base': 15, 'base_km': 4, 'per_km': 2},
        {'mode': 'jeepney', 'base': 99, 'base_km': 4, 'per_km': 2},
      ]);
      expect(PhFareCalculator.jeepney.base, 15);
    });

    test('the display range keeps its typical ride length', () {
      final typical = PhFareCalculator.jeepney.typicalKm;
      PhFareCalculator.applyRules([
        {'mode': 'jeepney', 'base': 15, 'base_km': 4, 'per_km': 2},
      ]);
      expect(PhFareCalculator.jeepney.typicalKm, typical);
    });

    test('bad rows and missing modes keep the fare already in use', () {
      PhFareCalculator.applyRules([
        {'mode': 'jeepney', 'base': 0, 'base_km': 4, 'per_km': 2},
        {'mode': 'helicopter', 'base': 500, 'base_km': 1, 'per_km': 1},
      ]);
      expect(PhFareCalculator.jeepney.base, jeepney.base);
      expect(PhFareCalculator.busAircon.base, busAircon.base);
    });

    test('an empty answer changes nothing', () {
      PhFareCalculator.applyRules(const []);
      expect(PhFareCalculator.jeepney.base, jeepney.base);
    });
  });

  group('RouteChecklist', () {
    Future<void> show(
      WidgetTester tester,
      List<route_model.RouteCheck> checks,
    ) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: RouteChecklist(checks: checks)),
          ),
        ),
      );
    }

    testWidgets('problems show straight away, in order of seriousness', (
      tester,
    ) async {
      await show(tester, const [flagged, passed, failed]);
      expect(find.text('The fare is too high'), findsOneWidget);
      expect(find.text('New contributor'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('The fare is too high')).dy,
        lessThan(tester.getTopLeft(find.text('New contributor')).dy),
      );
    });

    testWidgets('passed checks are folded away until opened', (tester) async {
      await show(tester, const [passed, flagged]);
      expect(find.text('1 checks passed'), findsOneWidget);
      expect(find.text('Every point is in the Philippines'), findsNothing);
      await tester.tap(find.text('1 checks passed'));
      await tester.pumpAndSettle();
      expect(find.text('Every point is in the Philippines'), findsOneWidget);
    });

    testWidgets('checks that didn\'t apply aren\'t shown', (tester) async {
      await show(tester, const [skipped, passed]);
      expect(find.text("This isn't a correction"), findsNothing);
    });
  });

  group('Approve note dialog', () {
    late String? result;
    late bool closed;

    Future<void> open(WidgetTester tester) async {
      result = null;
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await showApproveNoteDialog(
                        context,
                        flagged: const [flagged],
                      );
                      closed = true;
                    },
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    bool canApprove(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed !=
        null;

    testWidgets('shows what was flagged', (tester) async {
      await open(tester);
      expect(find.text('New contributor'), findsOneWidget);
    });

    testWidgets('needs a real note', (tester) async {
      await open(tester);
      expect(canApprove(tester), isFalse);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(canApprove(tester), isFalse);
      await tester.enterText(find.byType(TextField), ' Checked it ');
      await tester.pump();
      expect(canApprove(tester), isTrue);
    });

    testWidgets('returns the trimmed note', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), ' Checked it ');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result, 'Checked it');
    });

    testWidgets('cancel returns null', (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });
  });

  group('Sending a route again after the checks rejected it', () {
    late List<String> actions;

    route_model.Route draft(String id) => route_model.Route(
      id: id,
      startLocation: 'A',
      endLocation: 'B',
      shortDescription: '',
      steps: const [],
    );

    /// The server answers these outcomes in order and records each action.
    void serverDecides(List<String> outcomes) {
      final remaining = [...outcomes];
      RoutesApi.tokenSource = (_) async => 'token';
      RoutesApi.invoker = (action, body, token) async {
        actions.add(action);
        return (
          status: 200,
          data: {
            'ok': true,
            'data': {'outcome': remaining.removeAt(0)},
          },
        );
      };
    }

    setUp(() => actions = []);
    tearDown(() {
      RoutesApi.invoker = null;
      RoutesApi.tokenSource = null;
    });

    test('updates the rejected route instead of making a new one', () async {
      serverDecides(['rejected', 'pending']);
      expect((await RouteService.saveRoute(draft('r1'))).isRejected, isTrue);
      expect((await RouteService.saveRoute(draft('r1'))).isWaiting, isTrue);
      expect(actions, ['submit', 'resubmit']);
    });

    test('keeps updating while it is still rejected', () async {
      serverDecides(['rejected', 'rejected', 'pending']);
      await RouteService.saveRoute(draft('r2'));
      await RouteService.saveRoute(draft('r2'));
      await RouteService.saveRoute(draft('r2'));
      expect(actions, ['submit', 'resubmit', 'resubmit']);
    });

    test('a different route is still a new one', () async {
      serverDecides(['rejected', 'pending']);
      await RouteService.saveRoute(draft('r3'));
      await RouteService.saveRoute(draft('r4'));
      expect(actions, ['submit', 'submit']);
    });
  });
}
