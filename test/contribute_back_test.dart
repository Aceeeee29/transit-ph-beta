import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transitph_beta/screens/contribute_screen.dart';
import 'package:transitph_beta/services/map_style_service.dart';

void main() {
  testWidgets('back in the Map tab leaves Contribute without closing the app '
      'screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // The clean map's tile timers would outlive the test; the base map
    // doesn't matter here.
    MapStyleService.instance.look.value = MapLook.classic;
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    Future<void> frames() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    var parentBacks = 0;
    // Like MainScreen: pushed over another route, blocks back and handles
    // it itself (here: counting it).
    await tester.pumpWidget(MaterialApp(home: const Text('below')));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder:
            (_) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) parentBacks++;
              },
              child: ContributeScreen(onRouteSubmitted: (_) async {}),
            ),
      ),
    );
    await frames();
    // Dismiss the first-use tutorial.
    if (find.text('Load Example').evaluate().isNotEmpty) {
      await tester.tap(find.text('Load Example'));
      await frames();
    }

    await tester.binding.handlePopRoute();
    await frames();

    expect(parentBacks, 1);
    expect(find.text('Discard this route?'), findsNothing);
    // Still on the Contribute screen, not popped back to "below".
    expect(find.byType(ContributeScreen), findsOne);
    expect(find.text('below'), findsNothing);
  });
}
