import '../models/ors_route_result.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PHILIPPINE FARE CALCULATOR
// Based on LTFRB Memorandum Circulars (2023–2024 rates)
// ═══════════════════════════════════════════════════════════════════════════

class PhFareCalculator {
  // ── Jeepney (LTFRB MC 2023-014) ───────────────────────────────────────────
  static const _jeepneyBase = 13.0; // first 4 km
  static const _jeepneyBasKm = 4000.0; // base distance in meters
  static const _jeepneyPerKm = 1.80; // per km after base

  // ── Modern Jeepney (PUV Modernization) ────────────────────────────────────
  static const _modernJeepBase = 14.0;
  static const _modernJeepPerKm = 2.20;

  // ── City Bus ordinary (LTFRB MC 2023-015) ─────────────────────────────────
  static const _busOrdBase = 15.0; // first 5 km
  static const _busOrdBaseKm = 5000.0;
  static const _busOrdPerKm = 1.85;

  // ── City Bus aircon ────────────────────────────────────────────────────────
  static const _busAcBase = 15.0;
  static const _busAcBaseKm = 5000.0;
  static const _busAcPerKm = 2.65;

  // ── UV Express / FX (LTFRB MC 2022-021) ───────────────────────────────────
  static const _fxBase = 35.0; // first 5 km
  static const _fxBaseKm = 5000.0;
  static const _fxPerKm = 4.00;

  // ── Tricycle (LGU-set, NCR average) ───────────────────────────────────────
  static const _tricycleBase = 15.0; // first 2 km
  static const _tricycleBaseKm = 2000.0;
  static const _tricyclePerKm = 5.00;

  // ── MRT-3 (DOTR 2023 matrix) ─────────────────────────────────────────────
  // Flat rate by station count (1–13 stations), stored as fare per station gap
  static const _mrtBase = 13.0;
  static const _mrtPerStation = 2.0; // approx ₱2 per additional station

  // ── LRT-1 (LRTA 2023) ────────────────────────────────────────────────────
  static const _lrt1Base = 20.0;
  static const _lrt1PerKm = 1.50;

  // ── LRT-2 (LRTA 2023) ────────────────────────────────────────────────────
  static const _lrt2Base = 13.0;
  static const _lrt2PerKm = 1.50;

  // ── Pasig River Ferry / RoRo ──────────────────────────────────────────────
  static const _ferryFlat = 50.0; // Pasig Ferry flat rate

  /// Returns the estimated fare in PHP for a given mode and distance (meters).
  static double compute(String mode, double distanceMeters) {
    switch (mode) {
      case 'Walk':
        return 0.0;

      case 'Jeepney':
        return _tieredFare(
          distanceMeters,
          _jeepneyBase,
          _jeepneyBasKm,
          _jeepneyPerKm,
        );

      case 'Bus':
        // Use aircon rate for major EDSA/highway routes, ordinary for others
        return _tieredFare(
          distanceMeters,
          distanceMeters > 10000 ? _busAcBase : _busOrdBase,
          distanceMeters > 10000 ? _busAcBaseKm : _busOrdBaseKm,
          distanceMeters > 10000 ? _busAcPerKm : _busOrdPerKm,
        );

      case 'FX/Van':
        return _tieredFare(distanceMeters, _fxBase, _fxBaseKm, _fxPerKm);

      case 'Tricycle':
        return _tieredFare(
          distanceMeters,
          _tricycleBase,
          _tricycleBaseKm,
          _tricyclePerKm,
        );

      case 'Train':
        // Approximate by distance — 500m per station average
        final stations = (distanceMeters / 500).ceil().clamp(1, 20);
        return (_mrtBase + (stations - 1) * _mrtPerStation).clamp(
          _lrt1Base,
          50.0,
        );

      case 'Ferry':
        return _ferryFlat;

      default:
        return _tieredFare(
          distanceMeters,
          _jeepneyBase,
          _jeepneyBasKm,
          _jeepneyPerKm,
        );
    }
  }

  static double _tieredFare(
    double distMeters,
    double baseFare,
    double baseMeters,
    double perKm,
  ) {
    if (distMeters <= baseMeters) return baseFare;
    final extraKm = (distMeters - baseMeters) / 1000.0;
    return baseFare + (extraKm * perKm);
  }

  /// Formats a fare double as "₱13.00" or "₱13–25" range string.
  static String format(double fare) {
    if (fare == 0) return 'Free';
    return '₱${fare.toStringAsFixed(0)}';
  }

  /// Formats a total fare with a ±20% range to account for real-world variance.
  static String formatRange(double fare) {
    if (fare == 0) return 'Free';
    final low = (fare * 0.9).roundToDouble();
    final high = (fare * 1.1).roundToDouble();
    return '₱${low.toStringAsFixed(0)}–${high.toStringAsFixed(0)}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PHILIPPINE ROAD DATABASE
// Maps specific road/street names to their primary transit mode.
// Sources: LTFRB route matrices, MMDA, Wikipedia PH transport articles.
// ═══════════════════════════════════════════════════════════════════════════

class PhRoadDatabase {
  /// Each entry: road name fragment (lowercase) → primary transit mode.
  /// Checked before generic heuristics — specific beats general.
  static const Map<String, String> _roadModes = {
    // ── TRAIN LINES ──────────────────────────────────────────────────────────
    // MRT-3 (runs along EDSA from North Ave to Taft)
    'mrt': 'Train',
    'mrt-3': 'Train',
    'mrt3': 'Train',
    'metro rail transit': 'Train',

    // LRT-1 (runs along Taft Ave / Rizal Ave from FPJ to Bacoor)
    'lrt': 'Train',
    'lrt-1': 'Train',
    'lrt1': 'Train',
    'lrt-2': 'Train',
    'lrt2': 'Train',
    'light rail transit': 'Train',

    // PNR
    'pnr': 'Train',
    'philippine national railways': 'Train',
    'tutuban': 'Train',
    'alabang station': 'Train',
    'calamba station': 'Train',

    // Station name fragments
    'north avenue station': 'Train',
    'quezon avenue station': 'Train',
    'kamuning station': 'Train',
    'cubao station': 'Train',
    'santolan station': 'Train',
    'ortigas station': 'Train',
    'shaw boulevard station': 'Train',
    'boni station': 'Train',
    'guadalupe station': 'Train',
    'buendia station': 'Train',
    'ayala station': 'Train',
    'magallanes station': 'Train',
    'taft avenue station': 'Train',
    'baclaran station': 'Train',
    'doroteo jose': 'Train',
    'carriedo station': 'Train',
    'central terminal': 'Train',
    'recto station': 'Train',
    'legarda station': 'Train',
    'pureza station': 'Train',
    'v. mapa': 'Train',
    'gilmore station': 'Train',
    'betty go-belmonte': 'Train',
    'araneta cubao': 'Train',
    'anonas station': 'Train',
    'katipunan station': 'Train',
    'santolan-annapolis': 'Train',
    'masinag station': 'Train',

    // ── FERRY / WATER TRANSPORT ───────────────────────────────────────────────
    'pasig river ferry': 'Ferry',
    'pasig river': 'Ferry',
    'manila bay': 'Ferry',
    'pier 1': 'Ferry',
    'pier 2': 'Ferry',
    'pier 4': 'Ferry',
    'pier 15': 'Ferry',
    'manila north harbor': 'Ferry',
    'manila south harbor': 'Ferry',
    'batangas port': 'Ferry',
    'cebu port': 'Ferry',
    'iloilo port': 'Ferry',
    'zamboanga port': 'Ferry',
    'davao wharf': 'Ferry',
    'ro-ro': 'Ferry',
    'roro': 'Ferry',
    'superferry': 'Ferry',
    'oceanjet': 'Ferry',
    'weesam': 'Ferry',

    // ── EXPRESSWAYS → FX/Van ─────────────────────────────────────────────────
    'south luzon expressway': 'FX/Van',
    'slex': 'FX/Van',
    'north luzon expressway': 'FX/Van',
    'nlex': 'FX/Van',
    'tplex': 'FX/Van',
    'tarlac-pangasinan-la union expressway': 'FX/Van',
    'skyway': 'FX/Van',
    'metro skyway': 'FX/Van',
    'star tollway': 'FX/Van',
    'cavitex': 'FX/Van',
    'calax': 'FX/Van',
    'cavite-laguna expressway': 'FX/Van',
    'naiax': 'FX/Van',
    'naiaix': 'FX/Van',
    'mcx': 'FX/Van',
    'manila-cavite expressway': 'FX/Van',
    'c6': 'FX/Van',
    'circumferential road 6': 'FX/Van',
    'subic-clark-tarlac': 'FX/Van',

    // ── MAJOR BUS ROUTES (EDSA corridor and primary highways) ────────────────
    // EDSA — MRT runs above, buses run the lanes
    'epifanio de los santos': 'Bus',
    'edsa': 'Bus',

    // Quezon City major avenues
    'commonwealth avenue': 'Bus',
    'mindanao avenue': 'Bus',
    'quirino highway': 'Bus',
    'visayas avenue': 'Bus',
    'east avenue': 'Bus',
    'east ave': 'Bus',
    'batasan road': 'Bus',
    'congressional avenue': 'Bus',
    'tandang sora avenue': 'Bus',
    'aurora boulevard': 'Bus',
    'aurora blvd': 'Bus',
    'katipunan avenue': 'Bus',
    'c.p. garcia': 'Bus',
    'cp garcia': 'Bus',

    // Manila major roads
    'españa boulevard': 'Bus',
    'españa blvd': 'Bus',
    'espana boulevard': 'Bus',
    'espana blvd': 'Bus',
    'taft avenue': 'Bus',
    'taft ave': 'Bus',
    'roxas boulevard': 'Bus',
    'roxas blvd': 'Bus',
    'quirino avenue': 'Bus',
    'pedro gil': 'Bus',
    'un avenue': 'Bus',
    'united nations avenue': 'Bus',
    'padre faura': 'Bus',

    // Pasig / Mandaluyong / Marikina
    'shaw boulevard': 'Bus',
    'shaw blvd': 'Bus',
    'ortigas avenue': 'Bus',
    'ortigas ave': 'Bus',
    'julia vargas': 'Bus',
    'meralco avenue': 'Bus',
    'meralco ave': 'Bus',
    'e. rodriguez': 'Bus',
    'e. rodriguez sr': 'Bus',
    'e. rodriguez jr': 'Bus',
    'marcos highway': 'Bus',
    'marikina-infanta highway': 'Bus',
    'sumulong highway': 'Bus',
    'masinag': 'Bus',

    // Makati
    'ayala avenue': 'Bus',
    'ayala ave': 'Bus',
    'buendia avenue': 'Bus',
    'buendia ave': 'Bus',
    'sen. gil puyat': 'Bus',
    'chino roces': 'Bus',
    'paseo de roxas': 'Bus',
    'makati avenue': 'Bus',
    'makati ave': 'Bus',
    'edsa-ayala': 'Bus',

    // Parañaque / Las Piñas / Muntinlupa
    'dr. a. santos avenue': 'Bus',
    'sucat road': 'Bus',
    'aguirre avenue': 'Bus',
    'alabang-zapote road': 'Bus',
    'las piñas-muntinlupa road': 'Bus',
    'national road (muntinlupa)': 'Bus',

    // Caloocan / Valenzuela / Malabon / Navotas (CAMANAVA)
    'a. mabini': 'Bus',
    'rizal avenue extension': 'Bus',
    'rizal avenue': 'Bus',
    'rizal ave': 'Bus',
    'c-3 road': 'Bus',
    'radial road 10': 'Bus',
    'r-10': 'Bus',
    'malabon-navotas road': 'Bus',
    'mcarthur highway': 'Bus',

    // Laguna / Cavite / Batangas (provincial)
    'national highway': 'Bus',
    'maharlika highway': 'Bus',
    'governor\'s drive': 'Bus',
    'emilio aguinaldo highway': 'Bus',
    'aguinaldo highway': 'Bus',
    'daang hari': 'Bus',
    'molino road': 'Bus',

    // ── JEEPNEY-DOMINANT ROADS ───────────────────────────────────────────────
    // These are roads where jeepneys are the primary (sometimes only) transit
    'quezon avenue': 'Jeepney',
    'quezon ave': 'Jeepney',
    'n. domingo': 'Jeepney',
    'new manila': 'Jeepney',
    'st. john': 'Jeepney',
    'kamias road': 'Jeepney',
    'scout mandarin': 'Jeepney',
    'scout albano': 'Jeepney',
    'timog avenue': 'Jeepney',
    'timog ave': 'Jeepney',
    'mother ignacia': 'Jeepney',
    'panay avenue': 'Jeepney',
    'sergeant esguerra': 'Jeepney',
    'perea street': 'Jeepney',
    'dela rosa': 'Jeepney',
    'jupiter street': 'Jeepney',
    'kalayaan avenue': 'Jeepney',
    'kalayaan ave': 'Jeepney',
    'banawe avenue': 'Jeepney',
    'banawe ave': 'Jeepney',
    'e. quintos': 'Jeepney',
    'blumentritt road': 'Jeepney',
    'moriones street': 'Jeepney',
    'legarda street': 'Jeepney',
    'recto avenue': 'Jeepney',
    'recto ave': 'Jeepney',
    'claro m. recto': 'Jeepney',
    'c.m. recto': 'Jeepney',
    'lerma street': 'Jeepney',
    'san marcelino': 'Jeepney',
    'vito cruz': 'Jeepney',
    'leveriza': 'Jeepney',
    'pablo ocampo': 'Jeepney',
    'general luna': 'Jeepney',
    'antonio arnaiz': 'Jeepney',
    'arnaiz avenue': 'Jeepney',
    'pasong tamo': 'Jeepney',
    'edsa-taft': 'Jeepney',
    'manila zoo': 'Jeepney',
    'leon guinto': 'Jeepney',
    'a. lacson avenue': 'Jeepney',
    'lacson avenue': 'Jeepney',
    'sampaloc': 'Jeepney',
    'algeciras': 'Jeepney',
    'abad santos': 'Jeepney',
    'bambang': 'Jeepney',
    'tayuman': 'Jeepney',
    'lavezares': 'Jeepney',
    'c. palanca': 'Jeepney',
    'g. puyat': 'Jeepney',
    'san andres': 'Jeepney',
    'san antonio': 'Jeepney',
    'paco': 'Jeepney',
    'pandacan': 'Jeepney',
    'sta. mesa boulevard': 'Jeepney',
    'sta. mesa blvd': 'Jeepney',
    'dimasalang': 'Jeepney',
    'nagtahan': 'Jeepney',
    'amang rodriguez': 'Jeepney',
    'circumferential road 5': 'Jeepney',
    'c-5': 'Jeepney',
    'c5 road': 'Jeepney',
    'kabayani': 'Jeepney',
    'sgt. rivera': 'Jeepney',
    'n. quezon': 'Jeepney',
    'mindanao': 'Jeepney',
    'tomas morato': 'Jeepney',
    'scout tuazon': 'Jeepney',
    'lt. artiaga': 'Jeepney',
    'east capitol drive': 'Jeepney',
    'capitol hills': 'Jeepney',
    'batasan hills': 'Jeepney',
    'fairview': 'Jeepney',
    'novaliches road': 'Jeepney',
    'zabarte road': 'Jeepney',
    'camarin road': 'Jeepney',
    'bagbag road': 'Jeepney',
    'san bartolome': 'Jeepney',
  };

  /// Looks up the transit mode for a road by checking if the instruction
  /// contains any known road name from the database.
  /// Returns null if no match found (fall back to distance heuristics).
  static String? lookupMode(String instruction) {
    final text = instruction.toLowerCase();

    // Longer/more specific entries should match before shorter ones,
    // so sort by key length descending before scanning.
    final sorted =
        _roadModes.entries.toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in sorted) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSIT MODE INFERRER  (upgraded — road DB first, heuristics as fallback)
// ═══════════════════════════════════════════════════════════════════════════

/// Infers the most appropriate Philippine public transit mode for each ORS
/// step, then computes an estimated fare using LTFRB 2023/2024 rates.
///
/// Priority chain:
///   1. Walk     — depart/arrive keywords or ≤ 350 m
///   2. Road DB  — exact road name lookup in [PhRoadDatabase]
///   3. Train    — station/rail keywords
///   4. Ferry    — pier/port/water keywords
///   5. FX/Van   — expressway keywords or > 20 km
///   6. Tricycle — short + residential keywords
///   7. Bus      — major avenue + long distance
///   8. Jeepney  — default for urban medium segments
class TransitModeInferrer {
  // ── Distance thresholds ───────────────────────────────────────────────────
  static const _walkMax = 350.0;
  static const _tricycleMax = 1500.0;
  static const _jeepneyMax = 8000.0;
  static const _busMax = 20000.0;

  // ── Fallback keyword lists (used only when road DB has no match) ──────────
  static const _trainKeywords = ['station', 'rail', 'metro rail', 'light rail'];
  static const _ferryKeywords = [
    'pier',
    'port',
    'ferry',
    'wharf',
    'harbor',
    'harbour',
  ];
  static const _expressWayKeywords = ['expressway', 'tollway', 'toll road'];
  static const _residentialKeywords = [
    'street',
    'st.',
    ' st,',
    'lane',
    'drive',
    'subdivision',
    'village',
    'barangay',
    'brgy',
    'alley',
  ];
  static const _majorAvenuKeywords = ['avenue', 'blvd', 'boulevard', 'highway'];
  static const _departArriveKeywords = [
    'depart',
    'arrive',
    'destination',
    'start',
    'head',
  ];

  /// Applies mode inference AND fare calculation to every step.
  /// Returns a new list with [suggestedMode] and [estimatedFare] populated.
  static List<OrsStep> inferModes(List<OrsStep> steps) {
    if (steps.isEmpty) return steps;

    final totalDistance = steps.fold(0.0, (s, e) => s + e.distanceMeters);

    return steps.asMap().entries.map((entry) {
      final step = entry.value;
      final isFirst = entry.key == 0;
      final isLast = entry.key == steps.length - 1;

      final mode = _inferMode(
        step: step,
        isFirst: isFirst,
        isLast: isLast,
        totalDistance: totalDistance,
      );

      final fare = PhFareCalculator.compute(mode, step.distanceMeters);

      return OrsStep(
        instruction: step.instruction,
        distanceMeters: step.distanceMeters,
        durationSeconds: step.durationSeconds,
        suggestedMode: mode,
        estimatedFare: fare,
        wayPointStart: step.wayPointStart,
        wayPointEnd: step.wayPointEnd,
      );
    }).toList();
  }

  static String _inferMode({
    required OrsStep step,
    required bool isFirst,
    required bool isLast,
    required double totalDistance,
  }) {
    final text = step.instruction.toLowerCase();
    final dist = step.distanceMeters;

    // 1. Depart / arrive are always walking actions
    if (_containsAny(text, _departArriveKeywords)) return 'Walk';

    // 2. Very short → Walk
    if (dist <= _walkMax) return 'Walk';

    // 3. Road database lookup — most accurate signal
    final dbMode = PhRoadDatabase.lookupMode(text);
    if (dbMode != null) return dbMode;

    // 4. Fallback: train keywords
    if (_containsAny(text, _trainKeywords)) return 'Train';

    // 5. Fallback: ferry keywords
    if (_containsAny(text, _ferryKeywords)) return 'Ferry';

    // 6. Fallback: expressway → FX/Van
    if (_containsAny(text, _expressWayKeywords)) return 'FX/Van';

    // 7. Short residential → Tricycle
    if (dist <= _tricycleMax && _containsAny(text, _residentialKeywords)) {
      return 'Tricycle';
    }

    // 8. Major road + long → Bus
    if (_containsAny(text, _majorAvenuKeywords) && dist > _jeepneyMax) {
      return 'Bus';
    }

    // 9. Very long segments
    if (dist > _busMax) return 'FX/Van';
    if (dist > _jeepneyMax) {
      return totalDistance > 25000 ? 'FX/Van' : 'Bus';
    }

    // 10. Default
    return 'Jeepney';
  }

  static bool _containsAny(String text, List<String> keywords) =>
      keywords.any((kw) => text.contains(kw));
}
