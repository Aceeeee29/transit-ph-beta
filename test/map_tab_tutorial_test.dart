import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:transitph_beta/widgets/map/transit_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transitph_beta/screens/contribute_screen.dart';
import 'package:transitph_beta/widgets/spotlight_tutorial.dart';

void main() {
  testWidgets('the tour puts the map back and leaves it tappable', (
    tester,
  ) async {
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
    expect(find.byType(SpotlightTutorial), findsOneWidget);

    // Mid-tour the example route is drawn: its step's Save button shows.
    var sawSaveStep = false;
    for (var i = 0; i < 20; i++) {
      if (find.text('Save step').evaluate().isNotEmpty) sawSaveStep = true;
      final done = find.text('Start drawing');
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
    expect(sawSaveStep, isTrue);
    expect(find.byType(SpotlightTutorial), findsNothing);

    // The rider's own (empty) map is back.
    expect(find.text('Save step'), findsNothing);
    expect(
      find.text('Tap on the map to select the starting point'),
      findsOneWidget,
    );

    // The middle of the screen reaches the map, not an open drawer.
    final center = tester.getCenter(find.byType(ContributeScreen));
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, center, tester.view.viewId);
    final map = tester.renderObject(find.byType(TransitMap));
    expect(result.path.any((entry) => entry.target == map), isTrue);
  });

  Widget host({
    required List<SpotlightStep> steps,
    required VoidCallback onComplete,
    VoidCallback? onUnderneathTap,
    GlobalKey? targetKey,
  }) {
    return MaterialApp(
      home: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onUnderneathTap,
            ),
          ),
          Positioned(
            left: 40,
            top: 100,
            child: SizedBox(key: targetKey, width: 80, height: 40),
          ),
          SpotlightTutorial(steps: steps, onComplete: onComplete),
        ],
      ),
    );
  }

  testWidgets('the tour locks the screen, then lets taps through as it closes',
      (tester) async {
    var completed = 0;
    var underneathTaps = 0;
    final target = GlobalKey();
    await tester.pumpWidget(
      host(
        targetKey: target,
        steps: [
          SpotlightStep(title: 'Step 0', body: '', target: target),
          const SpotlightStep(title: 'Step 1', body: ''),
        ],
        onComplete: () => completed++,
        onUnderneathTap: () => underneathTaps++,
      ),
    );
    await tester.pumpAndSettle();

    // Even the lit part doesn't reach the screen underneath.
    await tester.tapAt(const Offset(80, 120));
    expect(underneathTaps, 0);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it!'));
    await tester.pump(const Duration(milliseconds: 50));

    // Mid-fade: the backdrop no longer catches taps meant for the map.
    await tester.tapAt(const Offset(10, 10));
    expect(underneathTaps, 1);

    await tester.pumpAndSettle();
    expect(completed, 1);
    expect(find.byType(SpotlightTutorial), findsOneWidget); // host removes it
  });

  testWidgets('each step sets the screen up; Back and Skip work', (
    tester,
  ) async {
    final shown = <int>[];
    var completed = 0;
    await tester.pumpWidget(
      host(
        steps: [
          for (var i = 0; i < 3; i++)
            SpotlightStep(
              title: 'Step $i',
              body: '',
              onShow: () => shown.add(i),
            ),
        ],
        onComplete: () => completed++,
      ),
    );
    await tester.pumpAndSettle();
    expect(shown, [0]);
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(shown, [0, 1, 0]);
    expect(find.text('Step 0'), findsOneWidget);

    await tester.tap(find.text('Skip tour'));
    await tester.pumpAndSettle();
    expect(completed, 1);
  });
}
