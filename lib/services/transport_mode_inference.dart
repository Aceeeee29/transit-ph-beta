import '../models/ors_route_result.dart';

// =============================================================================
// PHILIPPINE FARE CALCULATOR  (LTFRB MC 2023-2024 rates)
// =============================================================================

class PhFareCalculator {
  static const _jeepneyBase    = 13.0;   static const _jeepneyBasKm  = 4000.0; static const _jeepneyPerKm  = 1.80;
  static const _busOrdBase     = 15.0;   static const _busOrdBaseKm  = 5000.0; static const _busOrdPerKm   = 1.85;
  static const _busAcBase      = 15.0;   static const _busAcBaseKm   = 5000.0; static const _busAcPerKm    = 2.65;
  static const _fxBase         = 35.0;   static const _fxBaseKm      = 5000.0; static const _fxPerKm       = 4.00;
  static const _tricycleBase   = 15.0;   static const _tricycleBaseKm= 2000.0; static const _tricyclePerKm = 5.00;
  static const _mrtBase        = 13.0;   static const _mrtPerStation  = 2.0;
  static const _lrt1Base       = 20.0;
  static const _ferryFlat      = 50.0;

  static double compute(String mode, double distanceMeters) {
    switch (mode) {
      case 'Walk':    return 0.0;
      case 'Jeepney': return _t(distanceMeters, _jeepneyBase,  _jeepneyBasKm,  _jeepneyPerKm);
      case 'Bus':
        return _t(distanceMeters,
          distanceMeters > 10000 ? _busAcBase    : _busOrdBase,
          distanceMeters > 10000 ? _busAcBaseKm  : _busOrdBaseKm,
          distanceMeters > 10000 ? _busAcPerKm   : _busOrdPerKm);
      case 'FX/Van':  return _t(distanceMeters, _fxBase,        _fxBaseKm,       _fxPerKm);
      case 'Tricycle':return _t(distanceMeters, _tricycleBase,  _tricycleBaseKm, _tricyclePerKm);
      case 'Train':
        final stations = (distanceMeters / 500).ceil().clamp(1, 20);
        return (_mrtBase + (stations - 1) * _mrtPerStation).clamp(_lrt1Base, 50.0);
      case 'Ferry':   return _ferryFlat;
      default:        return _t(distanceMeters, _jeepneyBase,  _jeepneyBasKm,  _jeepneyPerKm);
    }
  }

  static double _t(double d, double base, double baseM, double perKm) =>
      d <= baseM ? base : base + ((d - baseM) / 1000.0) * perKm;

  static String format(double fare)      => fare == 0 ? 'Free' : '₱${fare.toStringAsFixed(0)}';
  static String formatRange(double fare) {
    if (fare == 0) return 'Free';
    return '₱${(fare*0.9).round()}-₱${(fare*1.1).round()}';
  }
}

// =============================================================================
// PHILIPPINE ROAD DATABASE  (v2)
//
// Sources (Nov 2025):
//   https://wiki.openstreetmap.org/wiki/Metro_Manila/Bus_routes
//   https://wiki.openstreetmap.org/wiki/Metro_Manila/Jeepney_and_UV_Express_routes
//
// NOTE: This DB is now a FALLBACK behind Overpass API live queries.
//       It handles cases where Overpass returns no data (unmapped roads,
//       timeout, offline).  Only include roads with high confidence for ONE mode.
//       Contested roads (bus + jeepney) are omitted — let Overpass or
//       dominantMode handle them.
// =============================================================================

class PhRoadDatabase {

  static const Map<String, String> _roadModes = {

    // ── TRAIN LINES & STATIONS ───────────────────────────────────────────────
    'metro rail transit': 'Train',  'light rail transit': 'Train',
    'philippine national railways': 'Train',
    'mrt-3': 'Train',  'mrt3': 'Train',  'mrt': 'Train',
    'lrt-1': 'Train',  'lrt1': 'Train',
    'lrt-2': 'Train',  'lrt2': 'Train',
    'pnr':   'Train',
    // MRT-3 stations
    'north avenue station': 'Train',  'quezon avenue station': 'Train',
    'kamuning station': 'Train',      'cubao station': 'Train',
    'santolan station': 'Train',      'ortigas station': 'Train',
    'shaw boulevard station': 'Train','boni station': 'Train',
    'guadalupe station': 'Train',     'buendia station': 'Train',
    'ayala station': 'Train',         'magallanes station': 'Train',
    'taft avenue station': 'Train',
    // LRT-1 stations
    'baclaran station': 'Train',      'edsa station': 'Train',
    'libertad station': 'Train',      'gil puyat station': 'Train',
    'vito cruz station': 'Train',     'quirino station': 'Train',
    'pedro gil station': 'Train',     'united nations station': 'Train',
    'central terminal': 'Train',      'carriedo station': 'Train',
    'doroteo jose': 'Train',          'bambang station': 'Train',
    'tayuman station': 'Train',       'blumentritt station': 'Train',
    'abad santos station': 'Train',   'r. papa station': 'Train',
    'balintawak station': 'Train',    'roosevelt station': 'Train',
    // LRT-2 stations
    'recto station': 'Train',         'legarda station': 'Train',
    'pureza station': 'Train',        'v. mapa': 'Train',
    'gilmore station': 'Train',       'betty go-belmonte': 'Train',
    'araneta cubao': 'Train',         'anonas station': 'Train',
    'katipunan station': 'Train',     'santolan-annapolis': 'Train',
    'masinag station': 'Train',       'antipolo station': 'Train',
    // PNR
    'tutuban': 'Train',  'alabang station': 'Train',  'calamba station': 'Train',

    // ── FERRY ─────────────────────────────────────────────────────────────────
    'pasig river ferry': 'Ferry',  'pasig river': 'Ferry',
    'manila bay': 'Ferry',         'manila north harbor': 'Ferry',
    'manila south harbor': 'Ferry','north harbor': 'Ferry',
    'south harbor': 'Ferry',       'batangas port': 'Ferry',
    'pier 15': 'Ferry',  'pier 4': 'Ferry',  'pier 2': 'Ferry',  'pier 1': 'Ferry',
    'ro-ro': 'Ferry',  'roro': 'Ferry',
    'superferry': 'Ferry',  'oceanjet': 'Ferry',  'weesam': 'Ferry',

    // ── EXPRESSWAYS → FX/Van ─────────────────────────────────────────────────
    // Confirmed: jeepneys/tricycles cannot use these roads legally.
    'south luzon expressway': 'FX/Van',  'slex': 'FX/Van',
    'north luzon expressway': 'FX/Van',  'nlex': 'FX/Van',
    'nlex mindanao avenue link': 'FX/Van',
    'metro skyway': 'FX/Van',  'skyway': 'FX/Van',
    'star tollway': 'FX/Van',  'cavitex': 'FX/Van',
    'manila-cavite expressway': 'FX/Van',  'mcx': 'FX/Van',
    'calax': 'FX/Van',  'cavite-laguna expressway': 'FX/Van',
    'muntinlupa-cavite expressway': 'FX/Van',
    'naiax': 'FX/Van',  'naiaix': 'FX/Van',
    'tplex': 'FX/Van',  'subic-clark-tarlac': 'FX/Van',
    'circumferential road 6': 'FX/Van',  'c6': 'FX/Van',
    'daang hari': 'FX/Van',        // P2P-only corridor
    'susana heights road': 'FX/Van',// SLEX access
    'east service road': 'FX/Van', // SLEX service road

    // ── BUS-DOMINANT ROADS ────────────────────────────────────────────────────
    // Confirmed by named bus routes in OSM Metro Manila/Bus_routes.
    'epifanio de los santos': 'Bus',  'edsa': 'Bus',
    // Macapagal / PITX / Coastal (bus routes 1,4,5,6,7,22,23,26-32,34,43)
    'president diosdado macapagal boulevard': 'Bus',
    'macapagal boulevard': 'Bus',  'diosdado macapagal': 'Bus',
    'seaside drive': 'Bus',        'pacific avenue': 'Bus',
    'coastal road': 'Bus',
    // Osmeña Highway / Ayala-Alabang (bus routes 10,11,12,24,25,P2P)
    'osmena highway': 'Bus',  'osmeña highway': 'Bus',
    // C-5 Road — corrected: major bus corridor (routes 4,15,18,38-42,55)
    'c-5 road': 'Bus',  'circumferential road 5': 'Bus',
    // Road 10 / Bonifacio Drive (routes 22,35,36,44,45,46)
    'road 10': 'Bus',  'bonifacio drive': 'Bus',  'mel lopez boulevard': 'Bus',
    // Alabang area
    'national road 1': 'Bus',  'national road': 'Bus',  'national highway': 'Bus',
    'alabang-zapote road': 'Bus',  'alabang zapote road': 'Bus',
    'spectrum midway': 'Bus',
    // South Luzon / Cavite arterials (routes 26-32,58)
    'aguinaldo boulevard': 'Bus',  'aguinaldo highway': 'Bus',
    'emilio aguinaldo highway': 'Bus',
    'antero soriano highway': 'Bus',
    "governor's drive": 'Bus',  'governors drive': 'Bus',
    'molino road': 'Bus',
    // QC arterials (bus routes 6,7,17,33,34)
    'commonwealth avenue': 'Bus',  'mindanao avenue': 'Bus',
    'visayas avenue': 'Bus',       'congressional avenue': 'Bus',
    'batasan road': 'Bus',         'quirino highway': 'Bus',
    'tandang sora avenue': 'Bus',  'regalado highway': 'Bus',
    'belfast street': 'Bus',
    // Aurora / Marcos / Sumulong (routes 3,17,18,55)
    'aurora boulevard': 'Bus',  'aurora blvd': 'Bus',
    'marcos highway': 'Bus',    'sumulong highway': 'Bus',
    'c.p. garcia avenue': 'Bus',  'cp garcia avenue': 'Bus',
    'c.p. garcia': 'Bus',         'cp garcia': 'Bus',
    'e. rodriguez sr. avenue': 'Bus',  'e. rodriguez sr': 'Bus',
    'e. rodriguez avenue': 'Bus',      'e. rodriguez': 'Bus',
    'e. rodriguez jr. avenue': 'Bus',  'e. rodriguez jr': 'Bus',
    // España / Lerma / Quezon Blvd corridor (routes 5,6,7,17,34)
    'espana boulevard': 'Bus',  'espana blvd': 'Bus',
    'españa boulevard': 'Bus',  'españa blvd': 'Bus',
    'lerma street': 'Bus',       'quezon boulevard': 'Bus',
    'padre burgos avenue': 'Bus',
    'a. mendoza boulevard': 'Bus',  'a. mendoza street': 'Bus',
    'laon laan street': 'Bus',      'dimasalang road': 'Bus',
    // Pasay / Taft / Gil Puyat (routes 4,5,6,7,10,17,23,24)
    'taft avenue': 'Bus',       'taft ave': 'Bus',
    'roxas boulevard': 'Bus',   'roxas blvd': 'Bus',
    'gil puyat avenue': 'Bus',  'sen. gil puyat': 'Bus',
    'ayala avenue': 'Bus',      'ayala ave': 'Bus',
    'buendia avenue': 'Bus',    'buendia ave': 'Bus',
    'chino roces avenue': 'Bus','chino roces': 'Bus',
    'paseo de roxas': 'Bus',    'makati avenue': 'Bus',  'makati ave': 'Bus',
    // NAIA / Paranaque (routes T428,T436-438,43)
    'dr. a. santos avenue': 'Bus',  'ninoy aquino avenue': 'Bus',
    'naia road': 'Bus',             'domestic road': 'Bus',
    'andrews avenue': 'Bus',        'airport road': 'Bus',
    // Rizal / MacArthur / C-3 (routes 8,9,14,22,35,36)
    'macarthur highway': 'Bus',        'mcarthur highway': 'Bus',
    'rizal avenue extension': 'Bus',   'rizal avenue': 'Bus',  'rizal ave': 'Bus',
    'andres bonifacio avenue': 'Bus',  'a. bonifacio avenue': 'Bus',
    'c-3 road': 'Bus',  'radial road 10': 'Bus',  'r-10': 'Bus',
    // Governor F. Halili / Santa Maria (routes 19,20,21,22,33)
    'governor f. halili avenue': 'Bus',  'governor fortunato halili': 'Bus',
    'santa maria bypass road': 'Bus',
    // Ortigas Center (routes 2,4,18,55)
    'ortigas avenue': 'Bus',   'ortigas ave': 'Bus',
    'julia vargas': 'Bus',     'meralco avenue': 'Bus',  'meralco ave': 'Bus',
    'shaw boulevard': 'Bus',   'shaw blvd': 'Bus',
    'magsaysay boulevard': 'Bus',
    // BGC / McKinley Hill (BGC Bus routes, P2P 4,15,16)
    'mckinley road': 'Bus',    'mckinley parkway': 'Bus',  'upper mckinley': 'Bus',
    'malabon-navotas road': 'Bus',  'maharlika highway': 'Bus',

    // ── JEEPNEY-DOMINANT ROADS ────────────────────────────────────────────────
    // Confirmed by route descriptions in OSM Jeepney_and_UV_Express_routes.
    // Camanava / Valenzuela feeders
    'samson road': 'Jeepney',
    'don basilio bautista boulevard': 'Jeepney',
    'susano road': 'Jeepney',     'zabarte road': 'Jeepney',
    'old zabarte road': 'Jeepney','camarin road': 'Jeepney',
    'bagbag road': 'Jeepney',     'novaliches road': 'Jeepney',
    'paso de blas road': 'Jeepney','paso de blas': 'Jeepney',
    'maysan road': 'Jeepney',     'gen. luis street': 'Jeepney',
    'general luis': 'Jeepney',    'buenamar street': 'Jeepney',
    'san bartolome': 'Jeepney',
    // QC: Batasan / Commonwealth feeders
    'batasan-san mateo road': 'Jeepney',
    'general luna street': 'Jeepney',  'general luna avenue': 'Jeepney',
    'batasan hills': 'Jeepney',   'fairview': 'Jeepney',
    'litex road': 'Jeepney',      'payatas road': 'Jeepney',
    'mayon avenue': 'Jeepney',    'rodriguez highway': 'Jeepney',
    'east capitol drive': 'Jeepney','capitol hills': 'Jeepney',
    // QC: Scouts / Timog / Tomas Morato / Banawe
    'scout mandarin': 'Jeepney',  'scout albano': 'Jeepney',
    'scout tuazon': 'Jeepney',    'lt. artiaga': 'Jeepney',
    'tomas morato avenue': 'Jeepney','tomas morato': 'Jeepney',
    'timog avenue': 'Jeepney',    'timog ave': 'Jeepney',
    'mother ignacia': 'Jeepney',  'panay avenue': 'Jeepney',
    'sergeant esguerra': 'Jeepney',
    'banawe avenue': 'Jeepney',   'banawe ave': 'Jeepney',
    'don a. roces avenue': 'Jeepney','don a. roces': 'Jeepney',
    'kamuning road': 'Jeepney',   'kamuning': 'Jeepney',
    // QC: Del Monte / Roosevelt / Cubao feeders
    'del monte avenue': 'Jeepney','del monte ave': 'Jeepney',
    'fpj avenue': 'Jeepney',      'n. quezon': 'Jeepney',
    'kabayani': 'Jeepney',        'sgt. rivera': 'Jeepney',
    'sergeant rivera': 'Jeepney', 'araneta avenue': 'Jeepney',
    'e. quintos': 'Jeepney',      'p. tuazon boulevard': 'Jeepney',
    'p. tuazon': 'Jeepney',       'murphy road': 'Jeepney',
    'murphy': 'Jeepney',          'n. domingo street': 'Jeepney',
    'n. domingo': 'Jeepney',      'new manila': 'Jeepney',
    'd. tuazon street': 'Jeepney','kamias road': 'Jeepney',
    'quezon avenue': 'Jeepney',   'quezon ave': 'Jeepney',
    // Marikina / Pasig
    'j.p. rizal street': 'Jeepney',  'jp rizal street': 'Jeepney',
    'j.p. rizal avenue': 'Jeepney',  'jp rizal avenue': 'Jeepney',
    'fortune avenue': 'Jeepney',     'bayan-bayanan avenue': 'Jeepney',
    'sampaguita avenue': 'Jeepney',  'shoe avenue': 'Jeepney',
    'east bank road': 'Jeepney',     'caruncho avenue': 'Jeepney',
    'ramon jabson street': 'Jeepney','pasig boulevard': 'Jeepney',
    'dr. sixto antonio avenue': 'Jeepney',
    'elisco road': 'Jeepney',        'maestrang pinang street': 'Jeepney',
    'a. sandoval avenue': 'Jeepney', 'barkadahan bridge': 'Jeepney',
    // Taguig / Fort Bonifacio feeders
    'pedro cayetano boulevard': 'Jeepney',
    'j.p. rizal avenue extension': 'Jeepney',
    'jp rizal avenue extension': 'Jeepney',
    'felix y. manalo street': 'Jeepney',
    'm.l. quezon avenue': 'Jeepney', 'p. victor street': 'Jeepney',
    'bayani road': 'Jeepney',        'lawton avenue': 'Jeepney',
    // Mandaluyong
    'kalentong': 'Jeepney',  'nueve de febrero': 'Jeepney',
    'vergara street': 'Jeepney',  'maysilo circle': 'Jeepney',
    'coronado street': 'Jeepney',
    // Makati feeders
    'pasong tamo': 'Jeepney',       'dela rosa street': 'Jeepney',
    'jupiter street': 'Jeepney',    'kalayaan avenue': 'Jeepney',
    'kalayaan ave': 'Jeepney',      'antonio arnaiz avenue': 'Jeepney',
    'arnaiz avenue': 'Jeepney',     'perea street': 'Jeepney',
    'leon guinto street': 'Jeepney','leon guinto': 'Jeepney',
    'a. lacson avenue': 'Jeepney',  'lacson avenue': 'Jeepney',
    'vito cruz street': 'Jeepney',  'vito cruz': 'Jeepney',
    'leveriza street': 'Jeepney',   'leveriza': 'Jeepney',
    'pablo ocampo avenue': 'Jeepney','pablo ocampo': 'Jeepney',
    'san marcelino': 'Jeepney',     'pedro gil street': 'Jeepney',
    'pedro gil': 'Jeepney',
    // Manila: Sampaloc / España feeders
    'sampaloc': 'Jeepney',  'algeciras': 'Jeepney',
    'blumentritt road': 'Jeepney',  'moriones street': 'Jeepney',
    'recto avenue': 'Jeepney',      'c.m. recto avenue': 'Jeepney',
    'claro m. recto': 'Jeepney',    'c.m. recto': 'Jeepney',
    'g. tuazon street': 'Jeepney',  'j. fajardo street': 'Jeepney',
    'cayco street': 'Jeepney',      'vicente cruz': 'Jeepney',
    'lepanto street': 'Jeepney',    'legarda street': 'Jeepney',
    'dapitan': 'Jeepney',           'lacson': 'Jeepney',
    // Manila: Tondo / Binondo feeders
    'abad santos avenue': 'Jeepney','abad santos': 'Jeepney',
    'bambang street': 'Jeepney',    'bambang': 'Jeepney',
    'tayuman street': 'Jeepney',    'tayuman': 'Jeepney',
    'lavezares street': 'Jeepney',  'lavezares': 'Jeepney',
    'c. palanca street': 'Jeepney', 'c. palanca': 'Jeepney',
    'dagupan street': 'Jeepney',    'antipolo street': 'Jeepney',
    'solis street': 'Jeepney',      'del fierro street': 'Jeepney',
    't. earnshaw street': 'Jeepney','mayhaligue street': 'Jeepney',
    'maysilo street': 'Jeepney',    'juan luna street': 'Jeepney',
    'herbosa street': 'Jeepney',    'velasquez street': 'Jeepney',
    'ilaya street': 'Jeepney',      'vitas road': 'Jeepney',
    "heroes del '96": 'Jeepney',    'heroes del 96': 'Jeepney',
    'nicanor reyes street': 'Jeepney','morayta': 'Jeepney',
    'evangelista street': 'Jeepney','general belarmino': 'Jeepney',
    'ipil street': 'Jeepney',       'new antipolo street': 'Jeepney',
    'laguna street': 'Jeepney',     'divisoria': 'Jeepney',
    'c-4 road': 'Jeepney',
    // Manila: Pandacan / Paco / Santa Ana
    'pandacan': 'Jeepney',   'paco': 'Jeepney',
    'nagtahan': 'Jeepney',   'sta. mesa boulevard': 'Jeepney',
    'sta. mesa blvd': 'Jeepney',  'santa mesa boulevard': 'Jeepney',
    'dimasalang': 'Jeepney', 'amang rodriguez': 'Jeepney',
    'san andres': 'Jeepney', 'san antonio': 'Jeepney',
    'g. puyat street': 'Jeepney', 'beata street': 'Jeepney',
    'jesus street': 'Jeepney',    'penafrancia street': 'Jeepney',
    'peñafrancia street': 'Jeepney','apacible street': 'Jeepney',
    'sgt. fabian yabut': 'Jeepney',
    // Southern MM feeders
    'diego cera avenue': 'Jeepney', 'fruto santos avenue': 'Jeepney',
    'naga road': 'Jeepney',         'marcos alvarez avenue': 'Jeepney',
    'marcos alvarez': 'Jeepney',    'sucat road': 'Jeepney',
  };

  static String? lookupMode(String instruction) {
    final text   = instruction.toLowerCase();
    final sorted = _roadModes.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in sorted) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }
}

// =============================================================================
// TRANSIT MODE INFERRER
// =============================================================================

/// Infers the Philippine transit mode for each ORS step.
///
/// Priority chain:
///   1. Walk         — depart/arrive keywords or <= 350 m
///   2. overpassMode — live Overpass API result (highest confidence)
///   3. Road DB      — PhRoadDatabase keyword match (fallback)
///   4. Train        — station/rail keywords (hard infrastructure)
///   5. Ferry        — pier/port keywords (hard infrastructure)
///   6. Expressway   — tollway/highway keywords -> FX/Van
///   7. dominantMode — user's chosen vehicle (anchors ambiguous roads)
///   8. Distance     — heuristic fallback
class TransitModeInferrer {
  static const _walkMax      = 350.0;
  static const _tricycleMax  = 1500.0;
  static const _jeepneyMax   = 8000.0;
  static const _busMax       = 20000.0;

  static const _trainKws       = ['station', 'rail', 'metro rail', 'light rail'];
  static const _ferryKws       = ['pier', 'port', 'ferry', 'wharf', 'harbor', 'harbour'];
  static const _expressWayKws  = ['expressway', 'tollway', 'toll road'];
  static const _residentialKws = ['street', 'st.', ' st,', 'lane', 'drive',
                                   'subdivision', 'village', 'barangay', 'brgy', 'alley'];
  static const _majorAveKws    = ['avenue', 'blvd', 'boulevard', 'highway'];
  static const _departKws      = ['depart', 'arrive', 'destination', 'start', 'head'];

  /// Applies mode inference, fare calculation, and step merging.
  ///
  /// After inferring a mode for every raw ORS step, consecutive steps that
  /// share the same [suggestedMode] are **merged into one** — because "Turn
  /// left → Turn right → Continue straight" in the same vehicle is NOT a
  /// transfer, it is just one continuous ride.
  ///
  /// A new step is only created when the mode actually changes (e.g.
  /// Walk → Jeepney → Bus).
  ///
  /// [dominantMode]  — the transport mode the user selected (e.g. 'Jeepney').
  ///                   Anchors ambiguous steps after all other signals fail.
  ///
  /// [overpassModes] — live Overpass API results, one per raw step.
  ///                   When non-null, takes precedence over the road DB.
  static List<OrsStep> inferModes(
    List<OrsStep> steps, {
    String? dominantMode,
    List<String?>? overpassModes,
  }) {
    if (steps.isEmpty) return steps;
    final totalDist = steps.fold(0.0, (s, e) => s + e.distanceMeters);

    // Pass 1 — assign a mode to every raw ORS step
    final labeled = steps.asMap().entries.map((entry) {
      final i    = entry.key;
      final step = entry.value;
      final overpassMode = (overpassModes != null && i < overpassModes.length)
          ? overpassModes[i] : null;

      final mode = _inferMode(
        step:          step,
        isFirst:       i == 0,
        isLast:        i == steps.length - 1,
        totalDistance: totalDist,
        dominantMode:  dominantMode,
        overpassMode:  overpassMode,
      );

      return OrsStep(
        instruction:    step.instruction,
        distanceMeters: step.distanceMeters,
        durationSeconds:step.durationSeconds,
        suggestedMode:  mode,
        estimatedFare:  PhFareCalculator.compute(mode, step.distanceMeters),
        wayPointStart:  step.wayPointStart,
        wayPointEnd:    step.wayPointEnd,
      );
    }).toList();

    // Pass 2 — merge consecutive steps that share the same mode
    return _mergeConsecutiveSameMode(labeled);
  }

  /// Collapses consecutive [OrsStep]s that have the same [suggestedMode] into
  /// a single step.
  ///
  /// Merged step properties:
  ///   • instruction    — most descriptive road name found across the group,
  ///                      prefixed with the vehicle label (e.g. "Ride Jeepney
  ///                      via España Blvd → Quezon Ave → EDSA")
  ///   • distanceMeters — sum of all merged steps
  ///   • durationSeconds— sum of all merged steps
  ///   • estimatedFare  — recalculated from total merged distance (fare is
  ///                      NOT additive — you pay once for the whole ride)
  ///   • wayPointStart  — from the first step in the group
  ///   • wayPointEnd    — from the last step in the group
  static List<OrsStep> _mergeConsecutiveSameMode(List<OrsStep> steps) {
    if (steps.isEmpty) return steps;

    final merged = <OrsStep>[];
    var group = [steps.first];

    for (int i = 1; i < steps.length; i++) {
      if (steps[i].suggestedMode == group.first.suggestedMode) {
        group.add(steps[i]);
      } else {
        merged.add(_collapseGroup(group));
        group = [steps[i]];
      }
    }
    merged.add(_collapseGroup(group));
    return merged;
  }

  /// Collapses a group of same-mode steps into one representative [OrsStep].
  static OrsStep _collapseGroup(List<OrsStep> group) {
    if (group.length == 1) return group.first;

    final mode        = group.first.suggestedMode;
    final totalDist   = group.fold(0.0, (s, e) => s + e.distanceMeters);
    final totalDur    = group.fold(0.0, (s, e) => s + e.durationSeconds);
    final fare        = PhFareCalculator.compute(mode, totalDist);
    final wayStart    = group.first.wayPointStart;
    final wayEnd      = group.last.wayPointEnd;

    // Build a human-readable instruction:
    //   "Ride Jeepney via España Blvd → Quezon Ave → EDSA"
    // We pick road names from the step instructions, skipping pure turn words.
    final roadNames = group
        .map((s) => _extractRoadName(s.instruction))
        .where((r) => r.isNotEmpty)
        .toList();

    final String instruction;
    if (mode == 'Walk') {
      instruction = roadNames.isEmpty
          ? 'Walk ${_distLabel(totalDist)}'
          : 'Walk via ${roadNames.join(' → ')}';
    } else {
      instruction = roadNames.isEmpty
          ? 'Ride $mode (${_distLabel(totalDist)})'
          : 'Ride $mode via ${roadNames.join(' → ')}';
    }

    return OrsStep(
      instruction:    instruction,
      distanceMeters: totalDist,
      durationSeconds:totalDur,
      suggestedMode:  mode,
      estimatedFare:  fare,
      wayPointStart:  wayStart,
      wayPointEnd:    wayEnd,
    );
  }

  /// Extracts the road/street name from an ORS instruction like
  /// "Turn left onto España Blvd" → "España Blvd"
  /// "Continue straight on EDSA"  → "EDSA"
  /// "Head north"                 → ""   (no road name)
  static String _extractRoadName(String instruction) {
    // ORS instruction patterns that precede a road name
    final patterns = [
      RegExp(r'onto (.+)$', caseSensitive: false),
      RegExp(r'on (.+)$',   caseSensitive: false),
      RegExp(r'along (.+)$',caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(instruction.trim());
      if (m != null) {
        final road = m.group(1)!.trim();
        // Skip generic or very short fragments
        if (road.length > 2 && !road.toLowerCase().startsWith('the ')) return road;
      }
    }
    return '';
  }

  static String _distLabel(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.toInt()} m';
  }

  static String _inferMode({
    required OrsStep step,
    required bool isFirst,
    required bool isLast,
    required double totalDistance,
    String? dominantMode,
    String? overpassMode,
  }) {
    final text = step.instruction.toLowerCase();
    final dist = step.distanceMeters;

    // 1. Depart / arrive → always Walk
    if (_any(text, _departKws)) return 'Walk';

    // 2. Very short → Walk
    if (dist <= _walkMax) return 'Walk';

    // 3. Overpass — ONLY hard-override for Train and Ferry.
    //
    //    Train and Ferry are fixed physical infrastructure: if Overpass says
    //    a road is a rail line or ferry route, that is always true regardless
    //    of what the user selected.
    //
    //    For road-based modes (Bus, Jeepney, FX/Van, Tricycle) Overpass is NOT
    //    a hard override. Many PH roads have BOTH bus AND jeepney route
    //    relations in OSM. If the user selected Jeepney and we're on EDSA,
    //    Overpass returns 'Bus' (higher priority in OSM), which would silently
    //    ignore the user's choice. That's wrong — the user knows which vehicle
    //    they want to take.
    //
    //    Road-based Overpass results are only used when there is NO dominantMode
    //    (i.e. the caller didn't know what mode to use and is relying purely on
    //    inference). When dominantMode IS set, it wins over road-based results.
    if (overpassMode == 'Train' || overpassMode == 'Ferry') return overpassMode!;

    // 4. Road DB — keyword match against PhRoadDatabase
    final dbMode = PhRoadDatabase.lookupMode(text);
    if (dbMode != null) return dbMode;

    // 5. Hard infrastructure: Train (keyword fallback when Overpass had no data)
    if (_any(text, _trainKws)) return 'Train';

    // 6. Hard infrastructure: Ferry
    if (_any(text, _ferryKws)) return 'Ferry';

    // 7. Expressway → FX/Van (physical road restriction, always applies)
    if (_any(text, _expressWayKws)) return 'FX/Van';

    // 8. Dominant mode anchor — user's chosen vehicle wins.
    //    This sits ABOVE the road-based Overpass result intentionally:
    //    if the user picked Jeepney, roads with OSM bus relations still
    //    return Jeepney because that's the vehicle they're riding.
    if (dominantMode != null && dominantMode != 'Walk') return dominantMode;

    // 9. Road-based Overpass result — only reached when dominantMode is null.
    //    At this point we have no user preference, so Overpass is our best
    //    inference for what mode serves this road.
    if (overpassMode != null) return overpassMode;

    // 10. Distance heuristics (only when dominantMode is null)
    if (dist <= _tricycleMax && _any(text, _residentialKws)) return 'Tricycle';
    if (_any(text, _majorAveKws) && dist > _jeepneyMax)      return 'Bus';
    if (dist > _busMax)    return 'FX/Van';
    if (dist > _jeepneyMax) return totalDistance > 25000 ? 'FX/Van' : 'Bus';

    return 'Jeepney';
  }

  static bool _any(String text, List<String> kws) =>
      kws.any((kw) => text.contains(kw));
}