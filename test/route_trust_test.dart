import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/route_trust_service.dart';

void main() {
  final now = DateTime(2026, 11, 7);

  route_model.Route route({DateTime? updatedAt}) => route_model.Route(
    id: 'r1',
    startLocation: 'A',
    endLocation: 'B',
    shortDescription: '',
    steps: const [],
    approvalStatus: route_model.RouteApprovalStatus.approved,
    updatedAt: updatedAt,
  );

  Map<String, int> votes(int yes, int no) => {
    'fareAccurateYes': yes,
    'fareAccurateNo': no,
    'scheduleAccurateYes': yes,
    'scheduleAccurateNo': no,
    'stillOperatingYes': yes,
    'stillOperatingNo': no,
  };

  int score(Map<String, int> summary, {DateTime? updatedAt}) =>
      RouteTrustService.computeConfidence(
        route: route(updatedAt: updatedAt),
        feedbackSummary: summary,
        now: now,
      ).total;

  test('a fresh route every rider agrees on reaches 100', () {
    expect(score(votes(5, 0), updatedAt: now), 100);
  });

  test('an older well-confirmed route can still be High trust', () {
    final old = now.subtract(const Duration(days: 200));
    expect(score(votes(5, 0), updatedAt: old), 85);
    expect(RouteTrustService.confidenceLabel(85), 'High trust');
  });

  test('one rider alone moves the score only a little', () {
    // 1 vote of 5 is a fifth of the weight: 4 + 4 + 4 on top of 20 + 15.
    expect(score(votes(1, 0), updatedAt: now), 47);
    expect(score(votes(0, 1), updatedAt: now), 23);
  });

  test('no votes keeps a route at base plus freshness', () {
    expect(score(votes(0, 0), updatedAt: now), 35);
  });

  // The server copies this score to verify routes by itself
  // (supabase/functions/routes-api/reports.ts). These are the same cases as
  // its trustScore tests, so the two can't drift apart.
  group('matches the server', () {
    test('three riders agreeing on everything, recently', () {
      final summary = {
        'fareAccurateYes': 3,
        'scheduleAccurateYes': 3,
        'stillOperatingYes': 3,
      };
      expect(
        score(summary, updatedAt: now.subtract(const Duration(days: 1))),
        74,
      );
    });

    test('mixed answers, a month and a half old, waiting for review', () {
      final summary = {
        'fareAccurateYes': 1,
        'fareAccurateNo': 1,
        'stillOperatingYes': 2,
        'stillOperatingNo': 3,
      };
      final pending = route_model.Route(
        id: 'r2',
        startLocation: 'A',
        endLocation: 'B',
        shortDescription: '',
        steps: const [],
        updatedAt: now.subtract(const Duration(days: 40)),
      );
      expect(
        RouteTrustService.computeConfidence(
          route: pending,
          feedbackSummary: summary,
          now: now,
        ).total,
        21,
      );
    });

    test('rounds halves away from zero', () {
      // -2/8 of 22 is -5.5, which rounds to -6.
      expect(score({'fareAccurateYes': 3, 'fareAccurateNo': 5}), 14);
    });
  });
}
