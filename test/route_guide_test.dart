import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/services/route_guide.dart';
import 'package:transitph_beta/widgets/map_tab/map_drawer.dart';
import 'package:transitph_beta/widgets/map_tab/route_view_widgets.dart';

void main() {
  test('the same trip always gets the same guide', () {
    const trip = 'SM City Grand Central|5210|1260';
    expect(RouteGuide.nameFor(trip), RouteGuide.nameFor(trip));
    expect(RouteGuide.names, contains(RouteGuide.nameFor(trip)));
    // Different trips spread over the guides.
    final used = {
      for (var i = 0; i < 40; i++) RouteGuide.nameFor('Trip $i|${i * 97}'),
    };
    expect(used.length, greaterThan(1));
  });

  for (final following in [false, true]) {
    testWidgets(
      'the drawer header fits its peek height (following: $following)',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 2.75;
        addTearDown(tester.view.reset);

        final peek = RouteDrawerHeader.peekHeight(
          showsButton: !following,
          byline: !following,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: peek - MapDrawer.handleHeight,
                  child: RouteDrawerHeader(
                    primary: '1 hr 12 min',
                    secondary: '18.4 km · ₱64 est.',
                    byline: 'Suggested by ${RouteGuide.names[2]}',
                    isFollowing: following,
                    hasArrived: false,
                    onStart: () {},
                    onStop: () {},
                    onDone: () {},
                    onOverview: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('18.4 km · ₱64 est.'), findsOne);
        expect(find.byTooltip('Whole route'), findsOne);
        // The guide shows before Start; the X only while following.
        expect(
          find.text('Suggested by Erling Haaland'),
          following ? findsNothing : findsOne,
        );
        expect(
          find.byTooltip('Stop route'),
          following ? findsOne : findsNothing,
        );
        expect(find.text('Start'), following ? findsNothing : findsOne);
      },
    );
  }
}
