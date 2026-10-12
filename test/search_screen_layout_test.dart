import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/screens/search_screen.dart';

void main() {
  testWidgets('search lays out before and after typing', (tester) async {
    SharedPreferences.setMockInitialValues({
      'recent_searches': ['Monumento'],
    });
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final routes = [
      for (var i = 0; i < 3; i++)
        route_model.Route(
          id: 'r$i',
          startLocation: 'Valenzuela Gateway Complex $i',
          endLocation: 'STI College Caloocan',
          shortDescription: 'Jeep then bus',
          steps: [
            route_model.Step(
              mode: 'Jeepney',
              instruction: 'Ride the jeep',
              details: '',
            ),
            route_model.Step(mode: 'Walk', instruction: 'Walk', details: ''),
          ],
          upvotes: 4,
          approvalStatus: route_model.RouteApprovalStatus.approved,
        ),
    ];
    await tester.pumpWidget(MaterialApp(home: SearchScreen(routes: routes)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Where to?'), 'STI');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Suggested routes'), findsOneWidget);
    expect(find.text('Community routes'), findsOneWidget);
  });
}
