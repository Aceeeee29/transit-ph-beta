import 'package:flutter_test/flutter_test.dart';

import 'package:transitph_beta/main.dart';

void main() {
  testWidgets('TransitPH app loads and shows title', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TransitPHApp());

    // Verify that the title "TransitPH" is shown on the home screen.
    expect(find.text('TransitPH'), findsOneWidget);
  });
}
