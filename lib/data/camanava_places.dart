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
/// This is a hand-compiled community dataset for the beta. Most entries have
/// now been re-pinned via the in-app tap-to-copy coord chip (Sep 2026).
/// A few remain approximate/pending — see inline notes below.
/// Categories map to the toggleable map filters (Attractions, Schools,
/// Hospitals, Malls, Parks).
const List<Place> camanavaPlaces = [
  // ── Attractions · historical & tourist spots ──────────────────────────────
  Place(
    id: 'bonifacio-monument',
    name: 'Bonifacio Monument',
    city: 'Caloocan',
    categories: [PlaceCategory.tourist, PlaceCategory.park],
    lat: 14.657028,
    lng: 120.983952,
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
    lat: 14.658696,
    lng: 120.951531,
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
    lat: 14.648979,
    lng: 120.976529,
    address: 'M. Naval St., Navotas',
    description:
        'Makasaysayang simbahan ng Navotas malapit sa fish port. Dito '
        'nagsisimula ang routicon ng mga deboto at turista tuwing fiesta ng '
        'San Jose sa buwan ng Marso.',
  ),
  // NOTE: 'navotas-fish-port' (Navotas Fish Port Complex) removed per request.
  Place(
    id: 'pio-valenzuela-shrine',
    name: 'Pio Valenzuela Shrine',
    city: 'Valenzuela',
    categories: [PlaceCategory.tourist],
    lat: 14.708556,
    lng: 120.944992,
    address: 'Pariancillo Villa, Valenzuela',
    description:
        'Apo ng makabayang si Dr. Pio Valenzuela, Katipunero at kasapi ng '
        'Kataas-taasang Kagalang-galangang Katipunan. Historical site na '
        'nagpapakita ng pamumuhay noong panahon ng rebolusyon.',
  ),
  // NOTE: 'malabon-zoo' (Malabon Zoo & Wildlife Park) removed per request.

  // ── Schools ─────────────────────────────────────────────────────────────
  Place(
    id: 'mcu',
    name: 'Manila Central University',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.658945,
    lng: 120.98638,
    address: 'Samson Rd., Caloocan',
    description:
        'Pioneer private university sa Caloocan, kilala sa nursing at med. '
        'Malapit sa ospital nito — MCU-FDTMF Hospital.',
  ),
  Place(
    id: 'ue-caloocan',
    name: 'University of the East Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.658043,
    lng: 120.976026,
    address: 'Samson Rd., Caloocan',
    description: 'UE Caloocan campus sa Samson Road — kilala sa business, '
        'engineering at basic education programs.',
  ),
  Place(
    id: 'sti-caloocan',
    name: 'STI College Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.657767,
    lng: 120.976511,
    address: 'Samson Rd., Caloocan',
    description:
        'STI campus malapit sa MCU. Sikat sa IT at business programs nito.',
  ),
  Place(
    id: 'caloocan-hs',
    name: 'Caloocan High School',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.651012,
    lng: 120.981581,
    address: '10th Ave., Grace Park, Caloocan',
    description: 'Isa sa pinakamalaking public high schools sa Caloocan.',
  ),
  Place(
    id: 'la-consolacion-caloocan',
    name: 'La Consolacion College Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.652095,
    lng: 120.972932,
    address: '8th Ave., Grace Park, Caloocan',
    description: 'Catholic school na kilala sa basic at higher education.',
  ),
  Place(
    id: 'malabon-nhs',
    name: 'Malabon National High School',
    city: 'Malabon',
    categories: [PlaceCategory.school],
    lat: 14.677065,
    lng: 120.942084,
    address: 'D. Gregorio, Malabon',
    description: 'Public high school sa puso ng Malabon.',
  ),
  Place(
    id: 'navotas-nhs',
    name: 'Navotas National High School',
    city: 'Navotas',
    categories: [PlaceCategory.school],
    lat: 14.657873,
    lng: 120.948418,
    address: 'M. Naval St., Navotas',
    description: 'Pangunahing public secondary school ng Navotas.',
  ),
  Place(
    id: 'slcv',
    name: 'St. Louis College Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.695719,
    lng: 120.971437,
    address: 'Maysan Rd., Valenzuela',
    description: 'Catholic school kilala sa edukasyon at vocational training.',
  ),
  Place(
    id: 'plv',
    name: 'Pamantasan ng Lungsod ng Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.693982,
    lng: 120.969447,
    address: 'Tongco St., Poblacion II, Valenzuela',
    description: 'City university ng Valenzuela (dating Valenzuela City '
        'Polytechnic College).',
  ),
  Place(
    id: 'valenzuela-nhs',
    name: 'Valenzuela National High School',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.672602,
    lng: 120.984830,
    address: 'Marulas, Valenzuela',
    description: 'Public high school sa Valenzuela — dating tinawag na Pio '
        'Valenzuela National High School.',
  ),
  Place(
    id: 'olfu',
    name: 'Our Lady of Fatima University',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.716363,
    lng: 121.060954,
    address: 'To confirm — see note below',
    description: 'Pribadong unibersidad na kilala sa nursing, medicine at '
        'allied health programs. Pinagmulan ng Fatima University Medical '
        'Center.',
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
    lat: 14.657536,
    lng: 120.987050,
    address: 'Samson Rd., Caloocan',
    description: 'University hospital ng MCU, kilala sa pangkalahatang '
        'medical at surgical care.',
  ),
  Place(
    id: 'caloocan-medical',
    name: 'Caloocan Medical Center',
    city: 'Caloocan',
    categories: [PlaceCategory.hospital],
    lat: 14.648295,
    lng: 120.973461,
    address: 'Gen. Luna St., Caloocan',
    description: 'Secondary hospital sa Caloocan para sa outpatient at '
        'inpatient care.',
  ),
  Place(
    id: 'ospital-ng-malabon',
    name: 'Ospital ng Malabon',
    city: 'Malabon',
    categories: [PlaceCategory.hospital],
    lat: 14.657190,
    lng: 120.950643,
    address: 'Brgy. San Agustin, Malabon',
    description: 'Lokal na pampublikong ospital ng Malabon.',
  ),
  Place(
    id: 'navotas-city-hospital',
    name: 'Navotas City Hospital',
    city: 'Navotas',
    categories: [PlaceCategory.hospital],
    // TODO: coordinates still pending re-pin ("pa").
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
    lat: 14.678057,
    lng: 120.980371,
    address: 'McArthur Hwy., Karuhatan, Valenzuela',
    description: 'Teaching hospital ng Our Lady of Fatima University, kilala '
        'sa Malasakit at specialist care.',
  ),
  Place(
    id: 'valenzuela-medical-center',
    name: 'Valenzuela Medical Center',
    city: 'Valenzuela',
    categories: [PlaceCategory.hospital],
    lat: 14.689841,
    lng: 120.977759,
    address: 'A. Pablo St., Valenzuela',
    description: 'Pampublikong ospital ng Lungsod ng Valenzuela — dating '
        'tinawag na Valenzuela City General Hospital.',
  ),

  // ── Malls ───────────────────────────────────────────────────────────────
  Place(
    id: 'sm-sangandaan',
    name: 'SM Center Sangandaan',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.658071,
    lng: 120.971969,
    address: 'Sangandaan, Caloocan',
    description: 'Compact SM center malapit sa Monumento — madalas na '
        'meeting point ng mga commuter.',
  ),
  Place(
    id: 'sm-grand-central',
    name: 'SM City Grand Central',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.654965,
    lng: 120.984256,
    address: 'Rizal Ave. Ext., Monumento, Caloocan',
    description: 'Malaking SM mall sa Monumento — dating Ever Gotesco Grand '
        'Central, katabi ng LRT Monumento.',
  ),
  Place(
    id: 'monumento-mall',
    name: 'Monumento Mall',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.654384,
    lng: 120.984039,
    address: 'Rizal Ave. Ext., Caloocan',
    description: 'Mall sa tabi ng LRT Monumento, sikat sa local stalls at '
        'foodcourt.',
  ),
  Place(
    id: 'caloocan-mall',
    name: 'Caloocan Mall',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.654141,
    lng: 120.984023,
    address: 'Rizal Ave. Ext., Caloocan',
    description: 'Lumang public market-mall combo ng Monumento — dating '
        'tinawag na Metro Mall Monumento.',
  ),
  // NOTE: 'sm-malabon' (SM Center Malabon) removed per request.
  Place(
    id: 'vmall-monumento',
    name: 'VMall Monumento',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.655445,
    lng: 120.983665,
    address: 'Rizal Ave. Ext., Monumento, Caloocan',
    description: 'Victory Mall sa Monumento circle — foodcourt at local stalls '
        'katabi ng LRT.',
  ),
  Place(
    id: 'waltermart-caloocan',
    name: 'WalterMart Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.641783,
    lng: 120.976003,
    address: 'Caloocan',
    description: 'Supermarket at retail — dating naka-tag bilang WalterMart '
        'Navotas, ngayon nakumpirma na nasa Caloocan.',
  ),
  Place(
    id: 'sm-city-valenzuela',
    name: 'SM City Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.mall],
    lat: 14.685566,
    lng: 120.976647,
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
  Place(
    id: 'fisher-mall-malabon',
    name: 'Fisher Mall Malabon',
    city: 'Malabon',
    categories: [PlaceCategory.mall],
    lat: 14.656757,
    lng: 120.960674,
    address: 'Dagat-Dagatan Ave., Longos, Malabon',
    description: 'Shopping mall sa Longos na may sinehan, supermarket at '
        'malawak na foodcourt.',
  ),

  // ── Parks ───────────────────────────────────────────────────────────────
  Place(
    id: 'navotas-centennial-park',
    name: 'Navotas Centennial Park',
    city: 'Navotas',
    categories: [PlaceCategory.park],
    lat: 14.651015,
    lng: 120.94673,
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
    lat: 14.691548,
    lng: 120.969967,
    address: 'Malinta, Valenzuela',
    description: 'City park na may jogging path, playgrounds at event space '
        '— paboritong palaruan ng mga pamilya.',
  ),
  // NOTE: 'caloocan-city-hall-plaza' removed per request, replaced below.
  Place(
    id: 'caloocan-city-peoples-park',
    name: 'Caloocan City People\'s Park',
    city: 'Caloocan',
    categories: [PlaceCategory.park],
    lat: 14.647914,
    lng: 120.990402,
    address: 'Grace Park East, Caloocan',
    description: 'Community park sa Grace Park East, tambayan para sa mga '
        'simpleng lakad, ehersisyo at pamilyang gatherings.',
  ),
];