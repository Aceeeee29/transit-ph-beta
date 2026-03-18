import 'package:flutter/material.dart';

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
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
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
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Row(
              children: [
                Icon(Icons.help_outline, color: Colors.blue.shade700, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Search & Route Tips',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Section 1: Recommended format ─────────────────────────────────
            _sectionTitle('✅ Recommended Format'),
            const SizedBox(height: 8),
            _card(
              color: Colors.green.shade50,
              border: Colors.green.shade200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Landmark or Street, City/Municipality',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _example('✓', 'SM Megamall, Mandaluyong', Colors.green.shade700),
                  _example('✓', 'Quezon City Hall, Quezon City', Colors.green.shade700),
                  _example('✓', 'NAIA Terminal 3, Pasay', Colors.green.shade700),
                  _example('✓', 'Ayala MRT Station, Makati', Colors.green.shade700),
                  _example('✓', 'Robinsons Place Manila, Ermita', Colors.green.shade700),
                  _example('✓', 'UST, Sampaloc, Manila', Colors.green.shade700),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Section 2: What to avoid ──────────────────────────────────────
            _sectionTitle('❌ Inputs That May Fail'),
            const SizedBox(height: 8),
            _card(
              color: Colors.red.shade50,
              border: Colors.red.shade200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _example('✗', '"Mall" — too vague', Colors.red.shade700),
                  _example('✗', '"Cubao" — no city context', Colors.red.shade700),
                  _example('✗', '"Home" — not a real address', Colors.red.shade700),
                  _example('✗', '"EDSA" — a road, not a point', Colors.red.shade700),
                  _example('✗', '"School" — too generic', Colors.red.shade700),
                  const SizedBox(height: 8),
                  Text(
                    'Tip: If a search fails, try adding the city name after a comma.',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.red.shade800,
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
              color: Colors.blue.shade50,
              border: Colors.blue.shade200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _info(
                    Icons.people_alt_outlined,
                    'Community Routes',
                    'Contributed by real commuters. Includes accurate jeepney codes, stops, and fares.',
                    Colors.blue.shade700,
                  ),
                  const SizedBox(height: 10),
                  _info(
                    Icons.map_outlined,
                    'Generated Routes (Supabase + OSRM)',
                    'Auto-generated from Supabase GTFS transit data, with OSRM used to connect road geometry between stops. Modes/fares are still estimates — verify locally.',
                    Colors.orange.shade700,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Section 4: Starting point tips ───────────────────────────────
            _sectionTitle('📍 Starting Point Tips'),
            const SizedBox(height: 8),
            _card(
              color: Colors.purple.shade50,
              border: Colors.purple.shade200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _info(
                    Icons.my_location,
                    'My Location (GPS)',
                    'Uses your current GPS position. Make sure location permission is granted.',
                    Colors.purple.shade700,
                  ),
                  const SizedBox(height: 10),
                  _info(
                    Icons.edit_location_alt_outlined,
                    'Enter Address',
                    'Type any landmark or address as your starting point. Use the same format as the destination.',
                    Colors.purple.shade700,
                  ),
                  const SizedBox(height: 10),
                  _info(
                    Icons.gps_fixed,
                    'GPS Fill button',
                    'Inside "Enter Address" mode, tap the GPS icon to auto-fill your current location into the field — then edit it if needed.',
                    Colors.purple.shade700,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Section 5: Fare disclaimer ────────────────────────────────────
            _sectionTitle('💰 About Estimated Fares'),
            const SizedBox(height: 8),
            _card(
              color: Colors.amber.shade50,
              border: Colors.amber.shade300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fares shown for generated routes are estimates based on LTFRB 2025–2026 rates and the calculated road distance.',
                    style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                  ),
                  const SizedBox(height: 8),
                  _example('•', 'Jeepney: ₱13 base + ₱1.80/km', Colors.amber.shade900),
                  _example('•', 'Bus: ₱13–15 base + ₱1.85–2.65/km', Colors.amber.shade900),
                  _example('•', 'FX/Van: ₱35 base + ₱4.00/km', Colors.amber.shade900),
                  _example('•', 'Tricycle: ₱15 base + ₱5.00/km', Colors.amber.shade900),
                  _example('•', 'Train: ₱20 base', Colors.amber.shade900),
                  const SizedBox(height: 8),
                  Text(
                    'A ±15% range is shown to account for real-world variance. Always confirm with the driver or station.',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.amber.shade900,
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
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: child,
      );

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
