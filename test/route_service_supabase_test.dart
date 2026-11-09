import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/notification.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/moderation_service.dart';
import 'package:transitph_beta/services/route_service.dart';
import 'package:transitph_beta/services/routes_api.dart';

route_model.Route sampleRoute([String id = 'r1']) => route_model.Route(
  id: id,
  startLocation: 'Monumento',
  endLocation: 'Malabon',
  shortDescription: 'Jeep',
  steps: [route_model.Step(mode: 'Jeepney', instruction: 'Ride', details: '')],
);

Map<String, dynamic> rowFor(
  String id, {
  String status = 'published',
  Map<String, dynamic> summary = const {'fareAccurateYes': 2},
}) => {
  'id': id,
  'source': 'rider',
  'contributor_id': 'uid-1',
  'status': status,
  'verification': 'verified',
  'data': sampleRoute(id).toJson(),
  'views': 5,
  'upvotes': 1,
  'downvotes': 0,
  'feedback_summary': summary,
  'revision': 1,
};

void main() {
  late List<({String action, Map body})> sent;
  late Map<String, Object? Function(Map body)> answers;
  late List<NotificationModel> notified;
  late List<String> statsFor;
  late Directory phoneStorage;

  /// Makes the server fail this action the way routes-api would.
  Object? Function(Map) refuses(int status, String code) =>
      (_) => throw RoutesApiException(status, code);

  setUp(() async {
    sent = [];
    answers = {};
    notified = [];
    statsFor = [];
    phoneStorage = await Directory.systemTemp.createTemp('route_cache_test');

    RoutesApi.tokenSource = (_) async => 'token';
    RoutesApi.invoker = (action, body, token) async {
      sent.add((action: action, body: body));
      final answer = answers[action];
      if (answer == null) fail('Unexpected call to $action');
      return (status: 200, data: {'ok': true, 'data': answer(body)});
    };
    RouteService.resetForTesting();
    RouteService.notifyHook = (n) async => notified.add(n);
    RouteService.statsHook = (uid) async => statsFor.add(uid);
    RouteService.currentUidHook = () => 'uid-1';
    RouteService.cacheFileHook =
        () async => File('${phoneStorage.path}/routes.json');
    RouteService.publishedReader =
        ({contributorId, routeId}) async => [rowFor('r1')];
  });

  tearDown(() async {
    RoutesApi.invoker = null;
    RoutesApi.tokenSource = null;
    RouteService.resetForTesting();
    ModerationService.pendingRoutesNotifier.value = [];
    await phoneStorage.delete(recursive: true);
  });

  group('sending routes', () {
    test('saveRoute sends submit with the route', () async {
      answers['submit'] = (_) => rowFor('r1', status: 'pending');
      final route = sampleRoute();

      await RouteService.saveRoute(route);

      expect(sent.single.action, 'submit');
      expect(sent.single.body['route']['id'], 'r1');
      expect(sent.single.body['route']['startLocation'], 'Monumento');
    });

    test('updateRoute sends resubmit', () async {
      answers['resubmit'] = (_) => rowFor('r1', status: 'pending');
      await RouteService.updateRoute(sampleRoute());
      expect(sent.single.action, 'resubmit');
    });

    test('an edited route can be sent', () async {
      // It used to hold a Firestore Timestamp, which can't become JSON.
      answers['resubmit'] = (_) => rowFor('r1', status: 'pending');
      final edited = route_model.Route(
        id: 'r1',
        startLocation: 'A',
        endLocation: 'B',
        shortDescription: '',
        steps: const [],
        isEdited: true,
        editedAt: DateTime(2026, 11, 1),
      );
      await RouteService.updateRoute(edited);
      expect(sent.single.body['route']['editedAt'], isA<String>());
    });

    test(
      'a refused route reaches the screen, so the drawing is kept',
      () async {
        answers['submit'] = refuses(400, 'invalid');
        await expectLater(
          RouteService.saveRoute(sampleRoute()),
          throwsA(isA<RoutesApiException>()),
        );
      },
    );

    test('deleteRoute sends delete', () async {
      answers['delete'] = (_) => <String, dynamic>{};
      await RouteService.deleteRoute('r1');
      expect(sent.single.body, {'routeId': 'r1'});
    });
  });

  group('approving', () {
    Map<String, dynamic> decided({String? mergedInto, String? contributor}) => {
      'route': rowFor('r1'),
      'contributorId': contributor,
      'title': 'Monumento to Malabon',
      if (mergedInto != null) 'mergedInto': mergedInto,
    };

    test('sends decide, notifies the contributor and adds a stat', () async {
      answers['decide'] = (_) => decided(contributor: 'rider-1');

      await RouteService.approveRoute('r1');

      expect(sent.single.body, {'routeId': 'r1', 'decision': 'approve'});
      expect(statsFor, ['rider-1']);
      final message = notified.single;
      expect(message.userId, 'rider-1');
      expect(message.type, 'route_approved');
      expect(message.routeId, 'r1');
      expect(message.message, contains('Monumento to Malabon'));
      expect(message.message, contains('approved'));
    });

    test('a merged correction says so and points to the target', () async {
      answers['decide'] =
          (_) => decided(contributor: 'fixer', mergedInto: 'target');

      await RouteService.approveRoute('fix');

      expect(notified.single.routeId, 'target');
      expect(notified.single.message, contains('Your correction'));
      expect(statsFor, ['fixer']);
    });

    test('a Former rider route notifies nobody', () async {
      answers['decide'] = (_) => decided();
      await RouteService.approveRoute('r1');
      expect(notified, isEmpty);
      expect(statsFor, isEmpty);
    });

    test('a double tap sends no second notification or stat', () async {
      answers['decide'] = refuses(409, 'conflict');
      await RouteService.approveRoute('r1');
      expect(notified, isEmpty);
      expect(statsFor, isEmpty);
    });

    test('a route already removed by someone else is not an error', () async {
      answers['decide'] = refuses(404, 'not_found');
      await RouteService.approveRoute('r1');
      expect(notified, isEmpty);
    });

    test('a failed notification does not undo the approval', () async {
      answers['decide'] = (_) => decided(contributor: 'rider-1');
      RouteService.notifyHook = (_) async => throw StateError('offline');
      await RouteService.approveRoute('r1');
      expect(statsFor, ['rider-1']);
    });

    test('a real failure reaches the moderator', () async {
      answers['decide'] = refuses(500, 'internal');
      await expectLater(
        RouteService.approveRoute('r1'),
        throwsA(isA<RoutesApiException>()),
      );
    });
  });

  group('rejecting', () {
    Map<String, dynamic> rejected(String? contributor) => {
      'route': rowFor('r1', status: 'rejected'),
      'contributorId': contributor,
      'title': 'Monumento to Malabon',
    };

    test('sends the reasons and note', () async {
      answers['decide'] = (_) => rejected('rider-1');

      await RouteService.rejectRoute(
        'r1',
        reasonCodes: ['wrong_fare', 'other'],
        note: 'The fare is 13',
      );

      expect(sent.single.body, {
        'routeId': 'r1',
        'decision': 'reject',
        'reasonCodes': ['wrong_fare', 'other'],
        'note': 'The fare is 13',
      });
    });

    test('the notification spells out the reasons and note', () async {
      answers['decide'] = (_) => rejected('rider-1');

      await RouteService.rejectRoute(
        'r1',
        reasonCodes: ['wrong_fare', 'duplicate'],
        note: 'The fare is 13',
      );

      final message = notified.single;
      expect(message.type, 'route_rejected');
      expect(
        message.message,
        'Your route (Monumento to Malabon) was rejected: Fare is wrong, '
        'Already exists. Note: The fare is 13',
      );
      expect(statsFor, isEmpty);
    });

    test('no note means no "Note:" in the message', () async {
      answers['decide'] = (_) => rejected('rider-1');
      await RouteService.rejectRoute('r1', reasonCodes: ['wrong_fare']);
      expect(notified.single.message, isNot(contains('Note:')));
      expect(sent.single.body.containsKey('note'), isFalse);
    });

    test('a double tap sends no second notification', () async {
      answers['decide'] = refuses(409, 'conflict');
      await RouteService.rejectRoute('r1', reasonCodes: ['wrong_fare']);
      expect(notified, isEmpty);
    });
  });

  group('reading routes', () {
    test('getAllRoutes returns the published routes', () async {
      final routes = await RouteService.getAllRoutes();
      expect(routes.single.id, 'r1');
      expect(routes.single.isApproved, isTrue);
    });

    test('offline, it falls back to the last routes it saw', () async {
      await RouteService.getAllRoutes();
      RouteService.publishedReader =
          ({contributorId, routeId}) async => throw const SocketException('x');

      final routes = await RouteService.getAllRoutes();

      expect(routes.single.id, 'r1');
    });

    test('offline with nothing saved gives an empty list', () async {
      RouteService.publishedReader =
          ({contributorId, routeId}) async => throw const SocketException('x');
      expect(await RouteService.getAllRoutes(), isEmpty);
    });

    test('a damaged saved file gives an empty list, not a crash', () async {
      await File('${phoneStorage.path}/routes.json').writeAsString('{broken');
      RouteService.publishedReader =
          ({contributorId, routeId}) async => throw const SocketException('x');
      expect(await RouteService.getAllRoutes(), isEmpty);
    });

    test('an empty answer from the server replaces the saved routes', () async {
      await RouteService.getAllRoutes();
      RouteService.publishedReader = ({contributorId, routeId}) async => [];
      expect(await RouteService.getAllRoutes(), isEmpty);
    });

    test('one bad row does not lose the other routes', () async {
      RouteService.publishedReader =
          ({contributorId, routeId}) async => [
            {
              ...rowFor('bad'),
              'data': {'steps': 'not a list'},
            },
            rowFor('good'),
          ];
      final routes = await RouteService.getAllRoutes();
      expect(routes.single.id, 'good');
    });
  });

  group('routes by user', () {
    test('your own routes come from my_routes, at any status', () async {
      answers['my_routes'] = (_) => [rowFor('mine', status: 'rejected')];

      final routes = await RouteService.getRoutesByUser('uid-1');

      expect(sent.single.action, 'my_routes');
      expect(routes.single.id, 'mine');
      expect(
        routes.single.approvalStatus,
        route_model.RouteApprovalStatus.rejected,
      );
    });

    test('someone else\'s routes are published ones only', () async {
      String? askedFor;
      RouteService.publishedReader = ({contributorId, routeId}) async {
        askedFor = contributorId;
        return [rowFor('theirs')];
      };

      final routes = await RouteService.getRoutesByUser('other-uid');

      expect(sent, isEmpty);
      expect(askedFor, 'other-uid');
      expect(routes.single.id, 'theirs');
    });

    test('a failure is reported, not turned into "no routes"', () async {
      // recalculateUserStats would otherwise save zeroed stats.
      answers['my_routes'] = refuses(500, 'internal');
      await expectLater(
        RouteService.getRoutesByUser('uid-1'),
        throwsA(isA<RoutesApiException>()),
      );
    });
  });

  group('getRouteById', () {
    test('finds a published route', () async {
      String? askedFor;
      RouteService.publishedReader = ({contributorId, routeId}) async {
        askedFor = routeId;
        return [rowFor('r1')];
      };
      expect((await RouteService.getRouteById('r1'))?.id, 'r1');
      expect(askedFor, 'r1');
      expect(sent, isEmpty);
    });

    test('finds your own rejected route, for its notification', () async {
      RouteService.publishedReader = ({contributorId, routeId}) async => [];
      answers['my_routes'] = (_) => [rowFor('r1', status: 'rejected')];
      expect((await RouteService.getRouteById('r1'))?.id, 'r1');
    });

    test('gives null when it is gone, or on failure', () async {
      RouteService.publishedReader = ({contributorId, routeId}) async => [];
      answers['my_routes'] = (_) => <dynamic>[];
      expect(await RouteService.getRouteById('r1'), isNull);

      RouteService.publishedReader =
          ({contributorId, routeId}) async => throw const SocketException('x');
      expect(await RouteService.getRouteById('r1'), isNull);
    });
  });

  group('opening a route', () {
    Map<String, dynamic> opened({
      String? vote = 'up',
      Map<String, dynamic>? feedback,
      String? next,
    }) => {
      'vote': vote,
      'feedback': feedback,
      'nextFeedbackAt': next,
      'summary': {'fareAccurateYes': 9},
    };

    test('all four reads share one call', () async {
      answers['open_route'] = (_) => opened();

      await RouteService.incrementViewForUser('r1', 'uid-1');
      await Future.wait<dynamic>([
        RouteService.getUserVote('r1', 'uid-1'),
        RouteService.getUserRouteQualityFeedback(
          routeId: 'r1',
          userId: 'uid-1',
        ),
        RouteService.getUserRouteFeedbackNextAllowedAt(
          routeId: 'r1',
          userId: 'uid-1',
        ),
      ]);

      expect(sent, hasLength(1));
      expect(sent.single.body, {'routeId': 'r1'});
    });

    test('calls at the same moment still share one', () async {
      answers['open_route'] = (_) => opened();
      await Future.wait<dynamic>([
        RouteService.getUserVote('r1', 'uid-1'),
        RouteService.getUserVote('r1', 'uid-1'),
      ]);
      expect(sent, hasLength(1));
    });

    test('reads the vote, feedback and next date', () async {
      answers['open_route'] =
          (_) => opened(
            vote: 'down',
            feedback: {
              'fareAccurate': true,
              'scheduleAccurate': false,
              'stillOperating': true,
            },
            next: '2026-12-01T00:00:00.000Z',
          );

      expect(await RouteService.getUserVote('r1', 'uid-1'), isFalse);
      expect(
        await RouteService.getUserRouteQualityFeedback(
          routeId: 'r1',
          userId: 'uid-1',
        ),
        {
          'fareAccurate': true,
          'scheduleAccurate': false,
          'stillOperating': true,
        },
      );
      expect(
        await RouteService.getUserRouteFeedbackNextAllowedAt(
          routeId: 'r1',
          userId: 'uid-1',
        ),
        DateTime.utc(2026, 12, 1).toLocal(),
      );
    });

    test('a rider who has done nothing gets nulls', () async {
      answers['open_route'] = (_) => opened(vote: null);
      expect(await RouteService.getUserVote('r1', 'uid-1'), isNull);
      expect(
        await RouteService.getUserRouteQualityFeedback(
          routeId: 'r1',
          userId: 'uid-1',
        ),
        isNull,
      );
      expect(
        await RouteService.getUserRouteFeedbackNextAllowedAt(
          routeId: 'r1',
          userId: 'uid-1',
        ),
        isNull,
      );
    });

    test('a failed open is not remembered', () async {
      answers['open_route'] = refuses(500, 'internal');
      expect(await RouteService.getUserVote('r1', 'uid-1'), isNull);
      answers['open_route'] = (_) => opened(vote: 'up');
      expect(await RouteService.getUserVote('r1', 'uid-1'), isTrue);
    });

    test('voting sends vote, and the next read is fresh', () async {
      answers['open_route'] = (_) => opened(vote: null);
      answers['vote'] = (_) => {'vote': 'up'};
      expect(await RouteService.getUserVote('r1', 'uid-1'), isNull);

      final result = await RouteService.setUserVote(
        routeId: 'r1',
        userId: 'uid-1',
        isUpvote: true,
      );

      expect(result, isTrue);
      expect(sent.last.body, {'routeId': 'r1', 'up': true});
      answers['open_route'] = (_) => opened(vote: 'up');
      expect(await RouteService.getUserVote('r1', 'uid-1'), isTrue);
    });

    test('removing a vote gives null', () async {
      answers['vote'] = (_) => {'vote': null};
      expect(
        await RouteService.setUserVote(
          routeId: 'r1',
          userId: 'uid-1',
          isUpvote: true,
        ),
        isNull,
      );
    });

    test('feedback is sent, and the next summary is fresh', () async {
      answers['open_route'] = (_) => opened();
      answers['quality_feedback'] = (_) => <String, dynamic>{};
      await RouteService.getUserVote('r1', 'uid-1');
      expect(
        (await RouteService.getRouteFeedbackSummary('r1'))['fareAccurateYes'],
        9,
      );

      await RouteService.submitRouteQualityFeedback(
        routeId: 'r1',
        userId: 'uid-1',
        fareAccurate: true,
        scheduleAccurate: false,
        stillOperating: true,
      );

      expect(sent.last.action, 'quality_feedback');
      expect(sent.last.body, {
        'routeId': 'r1',
        'fareAccurate': true,
        'scheduleAccurate': false,
        'stillOperating': true,
      });
      RouteService.publishedReader =
          ({contributorId, routeId}) async => [
            rowFor('r1', summary: {'fareAccurateYes': 10}),
          ];
      expect(
        (await RouteService.getRouteFeedbackSummary('r1'))['fareAccurateYes'],
        10,
      );
    });
  });

  group('feedback summary', () {
    test('a route list fills it, so cards do not each make a call', () async {
      await RouteService.getAllRoutes();
      var reads = 0;
      RouteService.publishedReader = ({contributorId, routeId}) async {
        reads++;
        return [];
      };

      final summary = await RouteService.getRouteFeedbackSummary('r1');

      expect(summary['fareAccurateYes'], 2);
      expect(reads, 0);
    });

    test('gives zeros for a route it cannot see, or on failure', () async {
      RouteService.publishedReader = ({contributorId, routeId}) async => [];
      expect(
        (await RouteService.getRouteFeedbackSummary('none')).values.toSet(),
        {0},
      );

      RouteService.publishedReader =
          ({contributorId, routeId}) async => throw const SocketException('x');
      expect(
        (await RouteService.getRouteFeedbackSummary('other')).values.toSet(),
        {0},
      );
    });

    test('watching gives the summary once', () async {
      expect(
        (await RouteService.watchRouteFeedbackSummary('r1').first).containsKey(
          'fareAccurateYes',
        ),
        isTrue,
      );
    });
  });

  group('moderator queue', () {
    test('getPendingRoutes reads the queue', () async {
      answers['queue'] = (_) => [rowFor('r1', status: 'pending')];
      final routes = await RouteService.getPendingRoutes();
      expect(routes.single.id, 'r1');
    });

    test('refresh fills the list, and a failure keeps the old one', () async {
      answers['queue'] = (_) => [rowFor('r1', status: 'pending')];
      await ModerationService.refreshPendingRoutes();
      expect(ModerationService.pendingRoutesNotifier.value.single.id, 'r1');

      answers['queue'] = refuses(500, 'internal');
      await ModerationService.refreshPendingRoutes();
      expect(ModerationService.pendingRoutesNotifier.value.single.id, 'r1');
    });

    test('a double tap just refreshes, with no second notification', () async {
      answers['decide'] = refuses(409, 'conflict');
      answers['queue'] = (_) => <dynamic>[];
      ModerationService.pendingRoutesNotifier.value = [sampleRoute()];

      await ModerationService.approveRoute('r1');

      expect(notified, isEmpty);
      expect(sent.map((s) => s.action), ['decide', 'queue']);
      expect(ModerationService.pendingRoutesNotifier.value, isEmpty);
    });

    test('a reject passes its reasons through', () async {
      answers['decide'] =
          (_) => {
            'route': rowFor('r1', status: 'rejected'),
            'contributorId': 'rider-1',
            'title': 'A to B',
          };
      answers['queue'] = (_) => <dynamic>[];

      await ModerationService.rejectRoute(
        'r1',
        reasonCodes: ['wrong_path'],
        note: 'Wrong road',
      );

      expect(sent.first.body['reasonCodes'], ['wrong_path']);
      expect(sent.first.body['note'], 'Wrong road');
    });

    test('a real failure reaches the screen', () async {
      answers['decide'] = refuses(500, 'internal');
      ModerationService.pendingRoutesNotifier.value = [sampleRoute()];

      await expectLater(
        ModerationService.approveRoute('r1'),
        throwsA(isA<RoutesApiException>()),
      );
      expect(ModerationService.pendingRoutesNotifier.value, hasLength(1));
    });
  });
}
