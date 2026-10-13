import 'package:flutter/material.dart';

import '../../services/location_service.dart';
import '../../services/weather_service.dart';
import '../translated_text.dart';
import '../../theme/app_colors.dart';

/// The drawer's resting row: the area picker on the left (CAMANAVA,
/// Valenzuela, …) and the current weather on the right.
class RegionWeatherRow extends StatelessWidget {
  final List<String> regions;
  final String? selectedRegion;
  final ValueChanged<String> onRegionSelected;

  const RegionWeatherRow({
    super.key,
    required this.regions,
    required this.selectedRegion,
    required this.onRegionSelected,
  });

  static const _accent = Color(0xFF0B8FD6);
  static Color get _textPrimary => AppColors.textPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Takes all the width the weather leaves, so names like
          // "Metro Manila" aren't cut short.
          Flexible(
            child: PopupMenuButton<String>(
              tooltip: 'Choose area',
              onSelected: onRegionSelected,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder:
                  (_) => [
                    for (final region in regions)
                      PopupMenuItem(
                        value: region,
                        child: Row(
                          children: [
                            Icon(
                              region == selectedRegion
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 18,
                              color: _accent,
                            ),
                            const SizedBox(width: 10),
                            Text(region),
                          ],
                        ),
                      ),
                  ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: TranslatedText(
                        selectedRegion ?? 'Choose area',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _textPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const WeatherChip(),
        ],
      ),
    );
  }
}

/// Current temperature with a condition icon. Shared across the app's map
/// views and refreshed at most every 15 minutes.
class WeatherChip extends StatefulWidget {
  const WeatherChip({super.key});

  static Future<WeatherData?>? _pending;
  static DateTime? _fetchedAt;

  /// The latest weather, shared by every chip (Home and the Map tab).
  static final current = ValueNotifier<WeatherData?>(null);

  /// The current weather, fetched at most every 15 minutes app-wide;
  /// [force] fetches now (e.g. right after location was allowed). A failed
  /// fetch isn't kept, so the next call tries again.
  static Future<WeatherData?> load({bool force = false}) {
    final fresh =
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(minutes: 15);
    if (!force && _pending != null && fresh) return _pending!;
    _fetchedAt = DateTime.now();
    return _pending = _fetch();
  }

  static Future<WeatherData?> _fetch() async {
    // Don't race the launch permission prompt (see LocationService).
    await LocationService.startupPermissionSettled;
    WeatherData? weather;
    try {
      weather = await WeatherService.getCurrentWeatherAndLocation();
    } catch (e) {
      debugPrint('[Weather] Load failed: $e');
    }
    if (weather == null) {
      _pending = null;
      _fetchedAt = null;
    } else {
      current.value = weather;
    }
    return weather;
  }

  @override
  State<WeatherChip> createState() => _WeatherChipState();
}

class _WeatherChipState extends State<WeatherChip> {
  @override
  void initState() {
    super.initState();
    WeatherChip.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: WeatherChip.current,
      builder: (context, weather, _) => _chip(weather),
    );
  }

  IconData _iconFor(WeatherData weather) {
    final condition = weather.condition.toLowerCase();
    if (weather.isStorm || condition.contains('thunder')) {
      return Icons.thunderstorm_rounded;
    }
    if (condition.contains('rain') ||
        condition.contains('shower') ||
        condition.contains('drizzle')) {
      return Icons.water_drop_rounded;
    }
    if (condition.contains('fog')) return Icons.foggy;
    if (condition.contains('clear')) {
      final hour = DateTime.now().hour;
      return hour >= 18 || hour < 6
          ? Icons.nightlight_round
          : Icons.wb_sunny_rounded;
    }
    return Icons.cloud_rounded;
  }

  Widget _chip(WeatherData? weather) {
    if (weather == null) return const SizedBox.shrink();
    final degrees = double.tryParse(
      weather.temp.replaceAll(RegExp(r'[^0-9.\-]'), ''),
    );
    return Tooltip(
      message: weather.condition,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(weather), size: 22, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              degrees != null ? '${degrees.round()}°' : weather.temp,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
