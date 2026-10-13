import 'package:flutter/material.dart';
import '../../services/fare_matrix.dart';
import '../../theme/app_colors.dart';

/// Full-screen bottom sheet explaining how to use the search & route features.
/// Self-contained – no state or callbacks required.
class SearchHelpSheet extends StatelessWidget {
  const SearchHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder:
          (_, scrollController) => Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title
                Row(
                  children: [
                    Icon(
                      Icons.help_outline,
                      color: AppColors.tintText(Colors.blue),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Search & Route Tips',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.tintText(Colors.blue),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Section 1: Recommended format ─────────────────────────────────
                _sectionTitle('✅ Recommended Format'),
                const SizedBox(height: 8),
                _card(
                  color: AppColors.tint(Colors.green),
                  border: AppColors.tintBorder(Colors.green),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Landmark or Street, City/Municipality',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.tintText(Colors.green, shade: 800),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _example(
                        '✓',
                        'SM Megamall, Mandaluyong',
                        AppColors.tintText(Colors.green),
                      ),
                      _example(
                        '✓',
                        'Quezon City Hall, Quezon City',
                        AppColors.tintText(Colors.green),
                      ),
                      _example(
                        '✓',
                        'NAIA Terminal 3, Pasay',
                        AppColors.tintText(Colors.green),
                      ),
                      _example(
                        '✓',
                        'Ayala MRT Station, Makati',
                        AppColors.tintText(Colors.green),
                      ),
                      _example(
                        '✓',
                        'Robinsons Place Manila, Ermita',
                        AppColors.tintText(Colors.green),
                      ),
                      _example(
                        '✓',
                        'UST, Sampaloc, Manila',
                        AppColors.tintText(Colors.green),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Section 2: What to avoid ──────────────────────────────────────
                _sectionTitle('❌ Inputs That May Fail'),
                const SizedBox(height: 8),
                _card(
                  color: AppColors.tint(Colors.red),
                  border: AppColors.tintBorder(Colors.red),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _example(
                        '✗',
                        '"Mall" — too vague',
                        AppColors.tintText(Colors.red),
                      ),
                      _example(
                        '✗',
                        '"Cubao" — no city context',
                        AppColors.tintText(Colors.red),
                      ),
                      _example(
                        '✗',
                        '"Home" — not a real address',
                        AppColors.tintText(Colors.red),
                      ),
                      _example(
                        '✗',
                        '"EDSA" — a road, not a point',
                        AppColors.tintText(Colors.red),
                      ),
                      _example(
                        '✗',
                        '"School" — too generic',
                        AppColors.tintText(Colors.red),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tip: If a search fails, try adding the city name after a comma.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.tintText(Colors.red, shade: 800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Section 3: Community vs Generated ────────────────────────────
                _sectionTitle('🗺️ Community Routes vs Generated Routes'),
                const SizedBox(height: 8),
                _card(
                  color: AppColors.tint(Colors.blue),
                  border: AppColors.tintBorder(Colors.blue),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _info(
                        Icons.people_alt_outlined,
                        'Community Routes',
                        'Contributed by real commuters. Includes accurate jeepney codes, stops, and fares.',
                        AppColors.tintText(Colors.blue),
                      ),
                      const SizedBox(height: 10),
                      _info(
                        Icons.map_outlined,
                        'Generated Routes (Supabase + OSRM)',
                        'Auto-generated from Supabase GTFS transit data, with OSRM used to connect road geometry between stops. Modes/fares are still estimates — verify locally.',
                        AppColors.tintText(Colors.orange),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Section 4: Starting point tips ───────────────────────────────
                _sectionTitle('📍 Starting Point Tips'),
                const SizedBox(height: 8),
                _card(
                  color: AppColors.tint(Colors.purple),
                  border: AppColors.tintBorder(Colors.purple),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _info(
                        Icons.my_location,
                        'Your location (GPS)',
                        'Routes start from your current GPS position by default. Make sure location permission is granted.',
                        AppColors.tintText(Colors.purple),
                      ),
                      const SizedBox(height: 10),
                      _info(
                        Icons.edit_location_alt_outlined,
                        'Start somewhere else',
                        'Type a landmark or address in the top field. Clear it with the × to start from your location again.',
                        AppColors.tintText(Colors.purple),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Section 5: Fare disclaimer ────────────────────────────────────
                _sectionTitle('💰 About Estimated Fares'),
                const SizedBox(height: 8),
                _card(
                  color: AppColors.tint(Colors.amber),
                  border: AppColors.tintBorder(Colors.amber, shade: 300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fares shown for generated routes are estimates based on LTFRB 2025–2026 rates and the calculated road distance.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.tintText(Colors.amber, shade: 900),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _example(
                        '•',
                        'Jeepney: ${_rule(PhFareCalculator.jeepney)}',
                        AppColors.tintText(Colors.amber, shade: 900),
                      ),
                      _example(
                        '•',
                        'Bus: ${PhFareCalculator.peso(PhFareCalculator.busOrdinary.base)} base + ${PhFareCalculator.peso(PhFareCalculator.busOrdinary.perKm)}–${PhFareCalculator.peso(PhFareCalculator.busAircon.perKm)}/km',
                        AppColors.tintText(Colors.amber, shade: 900),
                      ),
                      _example(
                        '•',
                        'FX/Van: ${_rule(PhFareCalculator.fxVan)}',
                        AppColors.tintText(Colors.amber, shade: 900),
                      ),
                      _example(
                        '•',
                        'Tricycle: ${_rule(PhFareCalculator.tricycle)}',
                        AppColors.tintText(Colors.amber, shade: 900),
                      ),
                      _example(
                        '•',
                        'Train: ${PhFareCalculator.peso(PhFareCalculator.trainMin)} base',
                        AppColors.tintText(Colors.amber, shade: 900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A ±15% range is shown to account for real-world variance. Always confirm with the driver or station.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.tintText(Colors.amber, shade: 900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
  );

  Widget _card({
    required Color color,
    required Color border,
    required Widget child,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border),
    ),
    child: child,
  );

  static String _rule(FareRule rule) =>
      '${PhFareCalculator.peso(rule.base)} base + '
      '${PhFareCalculator.peso(rule.perKm)}/km';

  Widget _example(String prefix, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          prefix,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    ),
  );

  Widget _info(IconData icon, String title, String body, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: TextStyle(fontSize: 12, color: color.withOpacity(0.85)),
            ),
          ],
        ),
      ),
    ],
  );
}
