import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/models/place.dart';
import 'package:transitph_beta/models/route.dart' as route_model;
import 'package:transitph_beta/services/map_tab_controller.dart';

void main() {
  final controller = MapTabController.instance;

  tearDown(() {
    controller.close();
    controller.placeCategories.value = const {PlaceCategory.tourist};
    controller.showPins.value = true;
  });

  test('opening a route shows it; closing goes back to browsing', () {
    var notified = 0;
    void listener() => notified++;
    controller.addListener(listener);
    addTearDown(() => controller.removeListener(listener));

    final route = route_model.Route(
      id: 'r1',
      startLocation: 'Monumento',
      endLocation: 'Malabon',
      shortDescription: '',
      steps: const [],
    );
    controller.showRoute(route, showDownloadButton: false);
    final first = controller.current!;
    expect(first.route, same(route));
    expect(first.originName, 'Monumento');
    expect(first.showDownloadButton, isFalse);

    // Reopening the same route restarts the view.
    controller.showRoute(route);
    expect(controller.current!.serial, isNot(first.serial));

    controller.close();
    expect(controller.current, isNull);
    expect(notified, 3);
  });

  test('category chips toggle; All highlights every one, then none', () {
    controller.toggleCategory(PlaceCategory.school);
    expect(controller.placeCategories.value, {
      PlaceCategory.tourist,
      PlaceCategory.school,
    });
    controller.toggleCategory(PlaceCategory.tourist);
    expect(controller.placeCategories.value, {PlaceCategory.school});
    controller.toggleAllCategories();
    expect(controller.placeCategories.value, PlaceCategory.values.toSet());
    controller.toggleAllCategories();
    expect(controller.placeCategories.value, isEmpty);
  });
}
