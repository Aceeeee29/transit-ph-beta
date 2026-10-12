import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transitph_beta/screens/contribute_screen.dart';

void main() {
  testWidgets('one drawing card replaces the floating panels', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    Future<void> frames() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
      MaterialApp(home: ContributeScreen(onRouteSubmitted: (_) async {})),
    );
    await frames();
    expect(find.text('Tap on the map to select the starting point'), findsOne);

    // The tutorial opens on first use; its example is a finished route.
    await tester.tap(find.text('Load Example'));
    await frames();

    expect(tester.takeException(), isNull);
    expect(find.text('Route finished. Drag the dots to fix a line.'), findsOne);
    expect(find.byTooltip('Undo'), findsOne);
    expect(find.byTooltip('Clear route'), findsOne);
    expect(find.text('Snap to road'), findsOne);
    // The old left panel is gone.
    expect(find.text('Route Metrics:'), findsNothing);

    // Clearing asks first.
    await tester.tap(find.byTooltip('Clear route'));
    await frames();
    expect(find.text('Clear this route?'), findsOne);
    await tester.tap(find.text('Cancel'));
    await frames();
    expect(find.text('Route finished. Drag the dots to fix a line.'), findsOne);
  });
}
