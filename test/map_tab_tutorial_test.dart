import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:transitph_beta/widgets/map/transit_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transitph_beta/screens/contribute_screen.dart';
import 'package:transitph_beta/services/tutorial_service.dart';
import 'package:transitph_beta/widgets/tutorial_overlay.dart';

void main() {
  testWidgets('the map is still tappable after the tutorial', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    Future<void> frames() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    var mode = MapTabMode.nearby;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder:
              (context, setState) => ContributeScreen(
                onRouteSubmitted: (_) async {},
                mapMode: mode,
                onMapModeChanged: (m) => setState(() => mode = m),
              ),
        ),
      ),
    );
    await frames();

    await tester.tap(find.byTooltip('Tutorial'));
    await frames();
    for (var i = 0; i < 20; i++) {
      final done = find.text('Got it!');
      final next = find.text('Next');
      if (done.evaluate().isNotEmpty) {
        await tester.tap(done);
      } else if (next.evaluate().isNotEmpty) {
        await tester.tap(next.first);
      } else {
        break;
      }
      await frames();
    }
    expect(find.text('Got it!'), findsNothing);

    // The middle of the screen reaches the map, not an open drawer.
    final center = tester.getCenter(find.byType(ContributeScreen));
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, center, tester.view.viewId);
    final map = tester.renderObject(find.byType(TransitMap));
    expect(result.path.any((entry) => entry.target == map), isTrue);
  });

  testWidgets('the closing tutorial lets taps through and completes once', (
    tester,
  ) async {
    var completed = 0;
    var underneathTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => underneathTaps++,
              ),
            ),
            TutorialOverlay(
              steps: [
                for (var i = 0; i < 2; i++)
                  TutorialStep(title: 'Step $i', description: ''),
              ],
              onComplete: () => completed++,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it!'));
    await tester.pump(const Duration(milliseconds: 50));

    // Mid-fade: the backdrop no longer catches taps meant for the map.
    await tester.tapAt(const Offset(10, 10));
    expect(underneathTaps, 1);

    await tester.pumpAndSettle();
    expect(completed, 1);
  });
}
