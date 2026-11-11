import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'fare_matrix.dart';

/// Loads the current fare rates, so a change on the dashboard reaches riders
/// without an app update. If it can't, fare_matrix.dart's numbers stay in use.
class FareRuleService {
  FareRuleService._();

  static Future<void> load() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final rows = await Supabase.instance.client
          .from('fare_rules')
          .select('mode,base,base_km,per_km')
          .lte('effective_from', today)
          .order('effective_from', ascending: false)
          .order('id', ascending: false)
          .timeout(const Duration(seconds: 15));
      PhFareCalculator.applyRules(rows);
    } catch (e) {
      debugPrint('[FareRuleService] Using saved fares: $e');
    }
  }
}
