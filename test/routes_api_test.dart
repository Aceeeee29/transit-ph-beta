import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/services/route_service.dart'
    show PendingRouteLimitException;
import 'package:transitph_beta/services/routes_api.dart';

void main() {
  late List<({String action, Map body, String token})> sent;
  late List<bool> tokenRequests;

  /// Makes the server give these answers, one per call.
  void serverAnswers(List<({int status, dynamic data})> answers) {
    final remaining = [...answers];
    RoutesApi.invoker = (action, body, token) async {
      sent.add((action: action, body: body, token: token));
      return remaining.removeAt(0);
    };
  }

  ({int status, dynamic data}) ok(dynamic data) => (
    status: 200,
    data: {'ok': true, 'data': data},
  );

  ({int status, dynamic data}) failure(
    int status,
    String code, [
    Map<String, dynamic> extra = const {},
  ]) => (status: status, data: {'ok': false, 'error': code, ...extra});

  setUp(() {
    sent = [];
    tokenRequests = [];
    RoutesApi.tokenSource = (forceRefresh) async {
      tokenRequests.add(forceRefresh);
      return forceRefresh ? 'fresh-token' : 'saved-token';
    };
  });

  tearDown(() {
    RoutesApi.invoker = null;
    RoutesApi.tokenSource = null;
  });

  test('sends the action, body and token, and returns the data', () async {
    serverAnswers([
      ok({'id': 'r1'}),
    ]);

    final result = await RoutesApi.call('submit', {'route': 'x'});

    expect(result, {'id': 'r1'});
    expect(sent.single.action, 'submit');
    expect(sent.single.body, {'route': 'x'});
    expect(sent.single.token, 'saved-token');
    expect(tokenRequests, [false]);
  });

  test('an empty list comes back as an empty list', () async {
    serverAnswers([ok(<dynamic>[])]);
    expect(await RoutesApi.call('my_routes'), isEmpty);
  });

  test('an expired token gets refreshed and retried once', () async {
    // An app left open for over an hour holds an expired token.
    serverAnswers([
      failure(401, 'unauthenticated'),
      ok({'done': true}),
    ]);

    final result = await RoutesApi.call('whoami');

    expect(result, {'done': true});
    expect(tokenRequests, [false, true]);
    expect(sent.map((s) => s.token), ['saved-token', 'fresh-token']);
  });

  test('two 401s in a row give up, without a third try', () async {
    serverAnswers([
      failure(401, 'unauthenticated'),
      failure(401, 'unauthenticated'),
    ]);

    await expectLater(
      RoutesApi.call('whoami'),
      throwsA(
        isA<RoutesApiException>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.code, 'code', 'unauthenticated'),
      ),
    );
    expect(sent, hasLength(2));
  });

  test('other errors are not retried', () async {
    serverAnswers([failure(403, 'forbidden')]);

    await expectLater(
      RoutesApi.call('decide'),
      throwsA(
        isA<RoutesApiException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.code, 'code', 'forbidden'),
      ),
    );
    expect(sent, hasLength(1));
  });

  test('no signed-in user gives 401 without calling the server', () async {
    RoutesApi.tokenSource = (_) async => null;
    serverAnswers([]);

    await expectLater(
      RoutesApi.call('whoami'),
      throwsA(
        isA<RoutesApiException>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.code, 'code', 'unauthenticated'),
      ),
    );
    expect(sent, isEmpty);
  });

  test('losing the login during the retry gives 401', () async {
    RoutesApi.tokenSource =
        (forceRefresh) async => forceRefresh ? null : 'saved-token';
    serverAnswers([failure(401, 'unauthenticated')]);

    await expectLater(
      RoutesApi.call('whoami'),
      throwsA(isA<RoutesApiException>().having((e) => e.status, 'status', 401)),
    );
    expect(sent, hasLength(1));
  });

  group('errors the screens already handle', () {
    test('pending_limit is a PendingRouteLimitException', () async {
      serverAnswers([failure(409, 'pending_limit')]);
      await expectLater(
        RoutesApi.call('submit'),
        throwsA(isA<PendingRouteLimitException>()),
      );
    });

    test('remove_first is the same StateError as before', () async {
      serverAnswers([failure(409, 'remove_first')]);
      await expectLater(
        RoutesApi.call('vote'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'remove_first'),
        ),
      );
    });

    test('feedback_cooldown keeps its date in the message', () async {
      serverAnswers([
        failure(429, 'feedback_cooldown', {
          'nextAllowedAt': '2026-12-01T00:00:00.000Z',
        }),
      ]);
      await expectLater(
        RoutesApi.call('quality_feedback'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'feedback_cooldown:2026-12-01T00:00:00.000Z',
          ),
        ),
      );
    });
  });

  test('extra details stay on the exception', () async {
    serverAnswers([
      failure(400, 'invalid', {'field': 'steps'}),
    ]);
    await expectLater(
      RoutesApi.call('submit'),
      throwsA(
        isA<RoutesApiException>().having((e) => e.extra, 'extra', {
          'field': 'steps',
        }),
      ),
    );
  });

  test('a reply that is not ours is an error, not a success', () async {
    // A gateway fault or a paused project can answer with plain text.
    for (final answer in [
      (status: 503, data: 'Service Unavailable'),
      (status: 200, data: 'odd'),
      (status: 200, data: null),
      (status: 200, data: {'something': 'else'}),
    ]) {
      serverAnswers([answer]);
      await expectLater(
        RoutesApi.call('whoami'),
        throwsA(
          isA<RoutesApiException>()
              .having((e) => e.status, 'status', answer.status)
              .having((e) => e.code, 'code', 'bad_response'),
        ),
      );
    }
  });

  test('being offline reaches the screen as the same error', () async {
    // Contribute shows an error and keeps the rider's drawing.
    RoutesApi.invoker = (action, body, token) async {
      throw TimeoutException('no network');
    };
    await expectLater(
      RoutesApi.call('submit'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
