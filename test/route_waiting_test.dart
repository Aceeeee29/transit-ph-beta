import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/widgets/profile/route_contribution_card.dart';

route_model.RouteCheck flag(String code, {bool unanswered = false}) =>
    route_model.RouteCheck(
      code: code,
      result: 'flag',
      message: code,
      unanswered: unanswered,
    );

final now = DateTime.utc(2026, 11, 12, 12);

route_model.Route waiting({
  int? daysAgo = 2,
  List<route_model.RouteCheck> checks = const [],
  route_model.RouteApprovalStatus status =
      route_model.RouteApprovalStatus.pending,
  String? correctionOf,
}) => route_model.Route(
  id: 'r1',
  startLocation: 'Monumento',
  endLocation: 'Malabon',
  shortDescription: '',
  steps: [route_model.Step(mode: 'Jeepney', instruction: 'Ride', details: '')],
  approvalStatus: status,
  correctionOf: correctionOf,
  checks: checks,
  latestDecision:
      daysAgo == null
          ? null
          : route_model.RouteDecision(
            decision: 'flagged',
            createdAt: now.subtract(Duration(days: daysAgo, hours: 1)),
          ),
);

void main() {
  group('What a rider can do about a flag', () {
    test('names, straight gaps and fares are the rider\'s to fix', () {
      for (final code in ['S_NAMES', 'S_DRAWN_GAPS', 'S_FARE_RANGE']) {
        expect(flag(code).riderCanFix, isTrue, reason: code);
        expect(flag(code).riderNextStep, startsWith('You can fix this'));
      }
    });

    test('the rest, and checks the server could not answer, mean waiting', () {
      for (final check in [
        flag('S_NEW_CONTRIBUTOR'),
        flag('S_AREA'),
        flag('S_OVERLAP'),
        flag('S_CORRECTION_SIZE'),
        flag('S_FARE_RANGE', unanswered: true),
      ]) {
        expect(check.riderCanFix, isFalse, reason: check.code);
        expect(
          check.riderNextStep,
          'Nothing to do. A moderator will check this.',
        );
      }
    });

    test('"unanswered" comes from the check\'s detail', () {
      final check = route_model.RouteCheck.fromJson({
        'code': 'S_AREA',
        'result': 'flag',
        'message': "Couldn't check",
        'detail': {'unanswered': true},
      });
      expect(check.unanswered, isTrue);
      expect(
        route_model.RouteCheck.fromJson(check.toJson()).unanswered,
        isTrue,
      );
    });
  });

  group('Waiting for review', () {
    test('days count from the decision that put it in the queue', () {
      expect(waiting(daysAgo: 0).daysWaiting(now), 0);
      expect(waiting(daysAgo: 3).daysWaiting(now), 3);
      expect(waiting(daysAgo: 6).isOverdue(now), isFalse);
      expect(waiting(daysAgo: 7).isOverdue(now), isTrue);
    });

    test('only pending routes wait', () {
      final live = waiting(
        daysAgo: 9,
        status: route_model.RouteApprovalStatus.approved,
      );
      expect(live.daysWaiting(now), 0);
      expect(live.isOverdue(now), isFalse);
    });

    test('the Profile label', () {
      expect(
        waitingLabel(waiting(daysAgo: 0), now),
        'Waiting for review · since today',
      );
      expect(
        waitingLabel(waiting(daysAgo: 1), now),
        'Waiting for review · 1 day',
      );
      expect(
        waitingLabel(waiting(daysAgo: 4), now),
        'Waiting for review · 4 days',
      );
    });

    test('only a lone "new contributor" flag goes live after the wait', () {
      expect(
        waiting(checks: [flag('S_NEW_CONTRIBUTOR')]).goesLiveWhenWaited,
        isTrue,
      );
      expect(
        waiting(
          checks: [flag('S_NEW_CONTRIBUTOR'), flag('S_AREA')],
        ).goesLiveWhenWaited,
        isFalse,
      );
      expect(waiting(checks: [flag('S_AREA')]).goesLiveWhenWaited, isFalse);
      // A correction changes another route, so a moderator always decides.
      expect(
        waiting(
          checks: [flag('S_NEW_CONTRIBUTOR')],
          correctionOf: 'r0',
        ).goesLiveWhenWaited,
        isFalse,
      );
      // Staff routes have no flags and wait for a person.
      expect(waiting().goesLiveWhenWaited, isFalse);
    });
  });
}
