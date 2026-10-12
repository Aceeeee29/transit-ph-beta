import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/data/camanava_places.dart';
import 'package:transitph_beta/models/place.dart';
import 'package:transitph_beta/widgets/map_tab/map_drawer.dart';
import 'package:transitph_beta/widgets/map_tab/map_search_bar.dart';
import 'package:transitph_beta/widgets/map_tab/map_side_button.dart';
import 'package:transitph_beta/widgets/map_tab/place_category_chips.dart';
import 'package:transitph_beta/widgets/map_tab/place_widgets.dart';
import 'package:transitph_beta/widgets/map_tab/region_weather_row.dart';

void main() {
  Widget harness(DraggableScrollableController controller, {Place? place}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.grey)),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: MapSearchBar(
                      hintText: 'Search routes',
                      onTap: () {},
                      actions: [
                        MapSearchBarAction(
                          icon: Icons.add_circle_outline_rounded,
                          tooltip: 'Contribute a route',
                          onTap: () {},
                        ),
                        MapSearchBarAction(
                          icon: Icons.help_outline_rounded,
                          tooltip: 'Tutorial',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  PlaceCategoryChips(
                    selected: const {PlaceCategory.tourist},
                    onSelectAll: () {},
                    onToggle: (_) {},
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              bottom: 92,
              child: MapSideButtons(
                children: [
                  MapSideButton(
                    icon: Icons.location_on_rounded,
                    tooltip: 'Hide pins',
                    onTap: () {},
                  ),
                  MapSideButton(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Center on my location',
                    onTap: () {},
                  ),
                ],
              ),
            ),
            MapDrawer(
              controller: controller,
              peekHeight: 80,
              header: RegionWeatherRow(
                regions: const ['CAMANAVA', 'Valenzuela'],
                selectedRegion: 'CAMANAVA',
                onRegionSelected: (_) {},
              ),
              children: [
                if (place != null)
                  PlaceDetailsSection(
                    place: place,
                    distanceKm: 1.2,
                    onClose: () {},
                  ),
                for (final p in camanavaPlaces.take(5))
                  PlaceListTile(place: p, distanceKm: null, onTap: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('map chrome lays out on a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final controller = DraggableScrollableController();
    await tester.pumpWidget(harness(controller, place: camanavaPlaces.first));
    await tester.pump();

    expect(find.text('Search routes'), findsOneWidget);
    expect(find.text('CAMANAVA'), findsOneWidget);
    expect(find.byType(MapSideButton), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // Opening the drawer shows the selected place's details.
    MapDrawer.open(controller, full: true);
    await tester.pumpAndSettle();
    expect(find.text(camanavaPlaces.first.name), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('region names show in full on a phone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    for (final region in ['Metro Manila', 'CAMANAVA']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegionWeatherRow(
              regions: const ['Metro Manila', 'CAMANAVA'],
              selectedRegion: region,
              onRegionSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      final label = tester.renderObject<RenderParagraph>(find.text(region));
      expect(label.didExceedMaxLines, isFalse, reason: region);
    }
  });

  test('pins hide when zoomed far out and are full size up close', () {
    expect(placePinScaleForZoom(10), 0);
    expect(placePinScaleForZoom(15), 1);
    final markers = placeMarkers(
      places: camanavaPlaces.take(3),
      scale: 0,
      selectedId: camanavaPlaces.first.id,
      onTap: (_) {},
    );
    // Only the selected place survives at zoom-out.
    expect(markers, hasLength(1));
  });
}
