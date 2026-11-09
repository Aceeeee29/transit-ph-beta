import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/widgets/moderation/reject_reasons_dialog.dart';

void main() {
  late RejectChoice? result;
  late bool closed;

  Future<void> openDialog(WidgetTester tester) async {
    result = null;
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showRejectReasonsDialog(context);
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  bool canConfirm(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }

  testWidgets('shows every reason', (tester) async {
    await openDialog(tester);
    for (final label in [
      'Missing information',
      'Outside the service area',
      "Path doesn't match the real route",
      'Fare is wrong',
      'Already exists',
      'Route no longer runs',
      'Spam or unsafe content',
      'Other',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('confirm is disabled with nothing picked', (tester) async {
    await openDialog(tester);
    expect(canConfirm(tester), isFalse);
  });

  testWidgets('a note alone is not enough', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'Looks wrong');
    await tester.pump();
    expect(canConfirm(tester), isFalse);
  });

  testWidgets('picking then unpicking disables confirm again', (tester) async {
    await openDialog(tester);
    await pick(tester, 'Fare is wrong');
    expect(canConfirm(tester), isTrue);
    await pick(tester, 'Fare is wrong');
    expect(canConfirm(tester), isFalse);
  });

  testWidgets('Other needs a real note', (tester) async {
    await openDialog(tester);
    await pick(tester, 'Other');
    expect(canConfirm(tester), isFalse);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(canConfirm(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'Not a real terminal');
    await tester.pump();
    expect(canConfirm(tester), isTrue);
  });

  testWidgets('returns the code with no note', (tester) async {
    await openDialog(tester);
    await pick(tester, 'Fare is wrong');
    await confirm(tester);
    expect(result?.codes, ['wrong_fare']);
    expect(result?.note, isNull);
  });

  testWidgets('returns the trimmed note, and codes in list order', (
    tester,
  ) async {
    await openDialog(tester);
    await pick(tester, 'Already exists');
    await pick(tester, 'Fare is wrong');
    await tester.enterText(find.byType(TextField), '  Check the fare  ');
    await tester.pump();
    await confirm(tester);
    expect(result?.codes, ['wrong_fare', 'duplicate']);
    expect(result?.note, 'Check the fare');
  });

  testWidgets('cancel returns null', (tester) async {
    await openDialog(tester);
    await pick(tester, 'Fare is wrong');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });
}
