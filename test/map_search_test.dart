import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/screens/map_search_screen.dart';
import 'package:transitph_beta/services/place_search_service.dart';
import 'package:transitph_beta/services/post_service.dart';

void main() {
  final route = route_model.Route(
    id: 'r1',
    startLocation: 'Monumento',
    endLocation: 'Valenzuela Gateway Complex',
    shortDescription: 'Jeep along MacArthur Highway',
    steps: [
      route_model.Step(mode: 'Jeepney', instruction: 'Ride', details: ''),
    ],
  );

  Future<MapSearchResult?> search(
    WidgetTester tester,
    String query, {
    required Finder tapOn,
  }) async {
    MapSearchResult? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  picked = await Navigator.of(context).push<MapSearchResult>(
                    MaterialPageRoute(
                      builder: (_) => MapSearchScreen(routes: [route]),
                    ),
                  );
                },
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    // Past the debounce; the OpenStreetMap lookup fails fast in tests.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(tapOn);
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('finds a landmark and opens it on the map', (tester) async {
    final picked = await search(
      tester,
      'Bonifacio',
      tapOn: find.text('Bonifacio Monument, Caloocan'),
    );
    expect(picked, isA<MapSearchPlace>());
    final place = (picked as MapSearchPlace).place;
    expect(
      PlaceSearchService.landmarkAt(place.latitude, place.longitude)?.id,
      'bonifacio-monument',
    );
  });

  testWidgets('finds community routes by their ends', (tester) async {
    final picked = await search(
      tester,
      'Monumento',
      tapOn: find.text('Monumento → Valenzuela Gateway Complex'),
    );
    expect(picked, isA<MapSearchRoute>());
    expect((picked as MapSearchRoute).route.id, 'r1');
  });

  testWidgets('offers directions to whatever was typed', (tester) async {
    final picked = await search(
      tester,
      'SM North',
      tapOn: find.text('Directions to "SM North"'),
    );
    expect(picked, isA<MapSearchDirections>());
    expect((picked as MapSearchDirections).query, 'SM North');
  });

  test('post lifetimes count from now, and forever never expires', () {
    expect(PostLifetime.forever.expiresAtFromNow(), isNull);
    final week = PostLifetime.days7.expiresAtFromNow()!.toDate();
    final expected = DateTime.now().add(const Duration(days: 7));
    expect(week.difference(expected).inSeconds.abs(), lessThan(5));
    expect(PostLifetime.standard, PostLifetime.days3);
  });
}
