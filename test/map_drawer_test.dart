import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/widgets/map_tab/map_drawer.dart';

void main() {
  testWidgets(
    'brought back to rest by code, the drawer shows its header again',
    (tester) async {
      final controller = DraggableScrollableController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapDrawer(
              controller: controller,
              peekHeight: 80,
              header: const Text('Header'),
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 50, child: Text('Row $i')),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Header'), findsOneWidget);

      // Open it all the way and scroll the list down, like a rider reaching
      // the Submit button at the bottom of the route form.
      controller.jumpTo(0.7);
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      list.controller!.jumpTo(1500);
      await tester.pumpAndSettle();
      expect(find.text('Header'), findsNothing);

      // Code animates the drawer back down to rest while the list is
      // scrolled. 80 px of the 600 px test screen is its rest height.
      MapDrawer.close(controller, 80 / 600);
      await tester.pumpAndSettle();
      expect(list.controller!.offset, 0);
      expect(find.text('Header'), findsOneWidget);
    },
  );

  testWidgets('at rest, new content puts the list back at the top', (
    tester,
  ) async {
    final controller = DraggableScrollableController();
    Widget drawer(String label) => MaterialApp(
      home: Scaffold(
        body: MapDrawer(
          controller: controller,
          peekHeight: 80,
          header: const Text('Header'),
          children: [
            for (var i = 0; i < 60; i++)
              SizedBox(height: 50, child: Text('$label $i')),
          ],
        ),
      ),
    );
    await tester.pumpWidget(drawer('Row'));
    // Left scrolled at rest somehow, like after the form is cleared.
    final list = tester.widget<ListView>(find.byType(ListView));
    list.controller!.jumpTo(500);
    await tester.pump();
    await tester.pumpWidget(drawer('New'));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, 0);
    expect(find.text('Header'), findsOneWidget);
  });
}
