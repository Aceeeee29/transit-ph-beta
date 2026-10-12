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

  testWidgets('the header with a guide fits the generated-route drawer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              // Generated-route peek height minus the handle.
              height: 100 - MapDrawer.handleHeight,
              child: RouteDrawerHeader(
                primary: '1 hr 12 min',
                secondary: '18.4 km · ₱64',
                byline: 'Suggested by ${RouteGuide.names[2]}',
                trailing: const SizedBox(width: 90, height: 40),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Suggested by Erling Haaland'), findsOne);
  });
}
