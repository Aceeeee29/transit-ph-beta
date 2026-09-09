import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/place.dart';

/// Shared bounding box for the CAMANAVA area.
///
/// CAMANAVA = South Caloocan, Malabon, Navotas and Valenzuela.
/// North Caloocan is intentionally excluded (it is a separate, non-contiguous
/// part of Caloocan City). Bounds are hand-tuned, matching the region handling
/// used by the route contribution screen.
class CamanavaBounds {
  static const southWest = LatLng(14.60, 120.92);
  static const northEast = LatLng(14.76, 121.04);
  static final bounds = LatLngBounds(southWest, northEast);
  static const center = LatLng(14.665, 120.96);
  static const initialZoom = 11.5;
}

/// Curated CAMANAVA points of interest used by the "Nearby Places" module.
///
/// This is a hand-compiled community dataset for the beta: coordinates are
/// approximate (city-level accuracy) and descriptions are short summaries.
/// Categories map to the toggleable map filters (Attractions, Schools,
/// Hospitals, Malls, Parks).
const List<Place> camanavaPlaces = [
  // ── Attractions · historical & tourist spots ──────────────────────────────
  Place(
    id: 'bonifacio-monument',
    name: 'Bonifacio Monument',
    city: 'Caloocan',
    categories: [PlaceCategory.tourist, PlaceCategory.park],
    lat: 14.6533,
    lng: 120.9829,
    address: 'Rizal Ave. Ext., Grace Park, Caloocan',
    description:
        'Iconsikong pambansang bantayog ni Andres Bonifacio na dinisenyo ni '
        'Guillermo Tolentino. Simbolo ng Himagsikang 1896 at paboritong dito '
        'ng mga galaan at photo tourists sa Monumento.',
  ),
  Place(
    id: 'san-bartolome-church-malabon',
    name: 'San Bartolome Church (Malabon)',
    city: 'Malabon',
    categories: [PlaceCategory.tourist],
    lat: 14.6610,
    lng: 120.9560,
    address: 'C. Arellano St., Malabon',
    description:
        'Isa sa mga pinakalumang simbahan sa bansa (itinatag noong 1590s). '
        'Kilala sa lumang brick facade at heritage vibe — panoorin ang '
        'Mary Magdalene imagery habang namamasyal sa bayan.',
  ),
  Place(
    id: 'san-jose-navotas-church',
    name: 'San Jose de Navotas Parish Church',
    city: 'Navotas',
    categories: [PlaceCategory.tourist],
    lat: 14.6450,
    lng: 120.9390,
    address: 'M. Naval St., Navotas',
    description:
        'Makasaysayang simbahan ng Navotas malapit sa fish port. Dito '
        'nagsisimula ang routicon ng mga deboto at turista tuwing fiesta ng '
        'San Jose sa buwan ng Marso.',
  ),
  Place(
    id: 'navotas-fish-port',
    name: 'Navotas Fish Port Complex',
    city: 'Navotas',
    categories: [PlaceCategory.tourist],
    lat: 14.6480,
    lng: 120.9330,
    address: 'N. Corner of M. Naval St., Navotas',
    description:
        'Pinakamalaking fish port sa Pilipinas. Bukal ng sariwang seafood — '
        'best sa madaling araw para sa palengke tour at pansit ng mga '
        'pagkaing-dagat na kainan sa paligid.',
  ),
  Place(
    id: 'pio-valenzuela-shrine',
    name: 'Pio Valenzuela Shrine',
    city: 'Valenzuela',
    categories: [PlaceCategory.tourist],
    lat: 14.7060,
    lng: 120.9540,
    address: 'Pariancillo Villa, Valenzuela',
    description:
        'Apo ng makabayang si Dr. Pio Valenzuela, Katipunero at kasapi ng '
        'Kataas-taasang Kagalang-galangang Katipunan. Historical site na '
        'nagpapakita ng pamumuhay noong panahon ng rebolusyon.',
  ),
  Place(
    id: 'malabon-zoo',
    name: 'Malabon Zoo & Wildlife Park',
    city: 'Malabon',
    categories: [PlaceCategory.tourist, PlaceCategory.park],
    lat: 14.6640,
    lng: 120.9530,
    address: 'C. Arellano St., Malabon',
    description:
        'Pangalawa sa pinakamatandang zoo sa bansa, tahanan ng sikat na '
        'crocodile collection at native wildlife. Family-friendly galaan '
        'destination para sa weekend.',
  ),

  // ── Schools ─────────────────────────────────────────────────────────────
  Place(
    id: 'mcu',
    name: 'Manila Central University',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.6490,
    lng: 120.9720,
    address: 'Samson Rd., Caloocan',
    description:
        'Pioneer private university sa Caloocan, kilala sa nursing at med. '
        'Malapit sa ospital nito — MCU-FDTMF Hospital.',
  ),
  Place(
    id: 'sti-caloocan',
    name: 'STI College Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.6488,
    lng: 120.9718,
    address: 'Samson Rd., Caloocan',
    description:
        'STI campus malapit sa MCU. Sikat sa IT at business programs nito.',
  ),
  Place(
    id: 'caloocan-hs',
    name: 'Caloocan High School',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.6620,
    lng: 120.9770,
    address: '10th Ave., Grace Park, Caloocan',
    description: 'Isa sa pinakamalaking public high schools sa Caloocan.',
  ),
  Place(
    id: 'la-consolacion-caloocan',
    name: 'La Consolacion College Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.6625,
    lng: 120.9760,
    address: '8th Ave., Grace Park, Caloocan',
    description: 'Catholic school na kilala sa basic at higher education.',
  ),
  Place(
    id: 'malabon-nhs',
    name: 'Malabon National High School',
    city: 'Malabon',
    categories: [PlaceCategory.school],
    lat: 14.6680,
    lng: 120.9600,
    address: 'D. Gregorio, Malabon',
    description: 'Public high school sa puso ng Malabon.',
  ),
  Place(
    id: 'navotas-nhs',
    name: 'Navotas National High School',
    city: 'Navotas',
    categories: [PlaceCategory.school],
    lat: 14.6530,
    lng: 120.9430,
    address: 'M. Naval St., Navotas',
    description: 'Pangunahing public secondary school ng Navotas.',
  ),
  Place(
    id: 'slcv',
    name: 'St. Louis College Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.6900,
    lng: 120.9650,
    address: 'Maysan Rd., Valenzuela',
    description: 'Catholic school kilala sa edukasyon at vocational training.',
  ),
  Place(
    id: 'plv',
    name: 'Pamantasan ng Lungsod ng Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.7040,
    lng: 120.9580,
    address: 'Tongco St., Poblacion II, Valenzuela',
    description: 'City university ng Valenzuela (dating Valenzuela City '
        'Polytechnic College).',
  ),
  Place(
    id: 'pio-valenzuela-nhs',
    name: 'Pio Valenzuela National High School',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.7050,
    lng: 120.9630,
    address: 'Marulas, Valenzuela',
    description: 'Public high school na ipinangalan sa bayaning si Dr. Pio '
        'Valenzuela.',
  ),

  // ── Hospitals ───────────────────────────────────────────────────────────
  Place(
    id: 'our-lady-of-grace',
    name: 'Our Lady of Grace Hospital',
    city: 'Caloocan',
    categories: [PlaceCategory.hospital],
    lat: 14.6620,
    lng: 120.9820,
    address: '5th Ave., Caloocan',
    description: 'Private hospital na nag-aalok ng 24-hour emergency services.',
  ),
  Place(
    id: 'mcu-fdtm',
    name: 'MCU-FDTMF Hospital',
    city: 'Caloocan',
    categories: [PlaceCategory.hospital],
    lat: 14.6490,
    lng: 120.9720,
    address: 'Samson Rd., Caloocan',
    description: 'University hospital ng MCU, kilala sa pangkalahatang '
        'medical at surgical care.',
  ),
  Place(
    id: 'caloocan-medical',
    name: 'Caloocan Medical Center',
    city: 'Caloocan',
    categories: [PlaceCategory.hospital],
    lat: 14.6550,
    lng: 120.9790,
    address: 'Gen. Luna St., Caloocan',
    description: 'Secondary hospital sa Caloocan para sa outpatient at '
        'inpatient care.',
  ),
  Place(
    id: 'ospital-ng-malabon',
    name: 'Ospital ng Malabon',
    city: 'Malabon',
    categories: [PlaceCategory.hospital],
    lat: 14.6660,
    lng: 120.9600,
    address: 'Brgy. San Agustin, Malabon',
    description: 'Lokal na pampublikong ospital ng Malabon.',
  ),
  Place(
    id: 'navotas-city-hospital',
    name: 'Navotas City Hospital',
    city: 'Navotas',
    categories: [PlaceCategory.hospital],
    lat: 14.6460,
    lng: 120.9440,
    address: 'M. Naval St., Navotas',
    description: 'City hospital na nagsisilbi sa mga residente ng Navotas.',
  ),
  Place(
    id: 'fatima-medical',
    name: 'Fatima University Medical Center',
    city: 'Valenzuela',
    categories: [PlaceCategory.hospital],
    lat: 14.6680,
    lng: 120.9690,
    address: 'McArthur Hwy., Karuhatan, Valenzuela',
    description: 'Teaching hospital ng Our Lady of Fatima University, kilala '
        'sa Malasakit at specialist care.',
  ),
  Place(
    id: 'valenzuela-general-hospital',
    name: 'Valenzuela City General Hospital',
    city: 'Valenzuela',
    categories: [PlaceCategory.hospital],
    lat: 14.7010,
    lng: 120.9540,
    address: 'A. Pablo St., Valenzuela',
    description: 'Pampublikong ospital ng Lungsod ng Valenzuela.',
  ),

  // ── Malls ───────────────────────────────────────────────────────────────
  Place(
    id: 'sm-sangandaan',
    name: 'SM Center Sangandaan',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.6490,
    lng: 120.9790,
    address: 'Sangandaan, Caloocan',
    description: 'Compact SM center malapit sa Monumento — madalas na '
        'meeting point ng mga commuter.',
  ),
  Place(
    id: 'monumento-mall',
    name: 'Monumento Mall',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.6540,
    lng: 120.9830,
    address: 'Rizal Ave. Ext., Caloocan',
    description: 'Mall sa tabi ng LRT Monumento, sikat sa local stalls at '
        'foodcourt.',
  ),
  Place(
    id: 'metro-mall-monumento',
    name: 'Metro Mall Monumento',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.6550,
    lng: 120.9820,
    address: 'Rizal Ave. Ext., Caloocan',
    description: 'Lumang public market-mall combo ng Monumento.',
  ),
  Place(
    id: 'sm-malabon',
    name: 'SM Center Malabon',
    city: 'Malabon',
    categories: [PlaceCategory.mall],
    lat: 14.6670,
    lng: 120.9570,
    address: 'Brgy. Catmon, Malabon',
    description: 'Malaking mall sa Malabon na nagsisilbing mall ng bayan.',
  ),
  Place(
    id: 'waltermart-navotas',
    name: 'WalterMart Navotas',
    city: 'Navotas',
    categories: [PlaceCategory.mall],
    lat: 14.6500,
    lng: 120.9390,
    address: 'M. Naval St., Navotas',
    description: 'Supermarket at retail na paborito ng mga Navoteño.',
  ),
  Place(
    id: 'sm-city-valenzuela',
    name: 'SM City Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.mall],
    lat: 14.6670,
    lng: 120.9700,
    address: 'McArthur Hwy., Karuhatan, Valenzuela',
    description: 'Pinakamalaking mall sa Valenzuela, mayron cinema at '
        'central foodcourt near McArthur Highway.',
  ),
  Place(
    id: 'victory-central-mall',
    name: 'Victory Central Mall Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.mall],
    lat: 14.7050,
    lng: 120.9560,
    address: 'McArthur Hwy., Valenzuela',
    description: 'Lokal na mall at palengke ng Valenzuela poblacion.',
  ),

  // ── Parks ───────────────────────────────────────────────────────────────
  Place(
    id: 'navotas-centennial-park',
    name: 'Navotas Centennial Park',
    city: 'Navotas',
    categories: [PlaceCategory.park],
    lat: 14.6460,
    lng: 120.9400,
    address: 'Along R-10 dike, Navotas',
    description:
        'Seafront park sa dike ng Navotas — magandang tambayan sa gabi '
        'para sa jogging at sahang ng fish port bay.',
  ),
  Place(
    id: 'valenzuela-peoples-park',
    name: 'Valenzuela People\'s Park',
    city: 'Valenzuela',
    categories: [PlaceCategory.park],
    lat: 14.7030,
    lng: 120.9550,
    address: 'Malinta, Valenzuela',
    description: 'City park na may jogging path, playgrounds at event space '
        '— paboritong palaruan ng mga pamilya.',
  ),
  Place(
    id: 'caloocan-city-hall-plaza',
    name: 'Caloocan City Hall Plaza',
    city: 'Caloocan',
    categories: [PlaceCategory.park],
    lat: 14.6560,
    lng: 120.9790,
    address: 'Rizal Ave., Grace Park, Caloocan',
    description: 'Plaza sa harap ng City Hall ng Caloocan, kilalang tambayan '
        'para sa mga simpleng lakad at gatherings.',
  ),
];