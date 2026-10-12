import 'package:flutter_test/flutter_test.dart';
import 'package:transitph_beta/services/location_service.dart';
import 'package:transitph_beta/widgets/map_tab/region_weather_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed weather load is tried again instead of kept', () async {
    // No location plugin in tests: the launch prompt "settles" by failing,
    // and so does the weather.
    await LocationService.requestPermissionIfUndecided();

    final first = WeatherChip.load();
    expect(await first, isNull);
    final second = WeatherChip.load();
    expect(identical(first, second), isFalse);
    expect(await second, isNull);
    expect(WeatherChip.current.value, isNull);
  });
}
