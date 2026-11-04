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
  static const initialZoom = 13.0;
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
  ),
  Place(
    id: 'san-bartolome-church-malabon',
    name: 'San Bartolome Church (Malabon)',
    city: 'Malabon',
    categories: [PlaceCategory.tourist],
    lat: 14.658696,
    lng: 120.951531,
    address: 'C. Arellano St., Malabon',
  ),
  Place(
    id: 'san-jose-navotas-church',
    name: 'San Jose de Navotas Parish Church',
    city: 'Navotas',
    categories: [PlaceCategory.tourist],
    // Google Maps: MW7W+52F, Navotas (was wrongly placed in Caloocan).
    lat: 14.662938,
    lng: 120.945047,
    address: 'M. Naval St., Navotas',
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
  ),
  Place(
    id: 'ue-caloocan',
    name: 'University of the East Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.658043,
    lng: 120.976026,
    address: 'Samson Rd., Caloocan',
  ),
  Place(
    id: 'sti-caloocan',
    name: 'STI College Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.657767,
    lng: 120.976511,
    address: 'Samson Rd., Caloocan',
  ),
  Place(
    id: 'caloocan-hs',
    name: 'Caloocan High School',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.651012,
    lng: 120.981581,
    address: '10th Ave., Grace Park, Caloocan',
  ),
  Place(
    id: 'la-consolacion-caloocan',
    name: 'La Consolacion College Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.school],
    lat: 14.652095,
    lng: 120.972932,
    address: '8th Ave., Grace Park, Caloocan',
  ),
  Place(
    id: 'malabon-nhs',
    name: 'Malabon National High School',
    city: 'Malabon',
    categories: [PlaceCategory.school],
    lat: 14.677065,
    lng: 120.942084,
    address: 'D. Gregorio, Malabon',
  ),
  Place(
    id: 'navotas-nhs',
    name: 'Navotas National High School',
    city: 'Navotas',
    categories: [PlaceCategory.school],
    lat: 14.657873,
    lng: 120.948418,
    address: 'M. Naval St., Navotas',
  ),
  Place(
    id: 'slcv',
    name: 'St. Louis College Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.695719,
    lng: 120.971437,
    address: 'Maysan Rd., Valenzuela',
  ),
  // NOTE: 'plv' (Pamantasan ng Lungsod ng Valenzuela) removed per request;
  // OpenStreetMap's pin is at the right spot.
  Place(
    id: 'valenzuela-nhs',
    name: 'Valenzuela National High School',
    city: 'Valenzuela',
    categories: [PlaceCategory.school],
    lat: 14.672602,
    lng: 120.984830,
    address: 'Marulas, Valenzuela',
  ),
  // NOTE: 'olfu' (Our Lady of Fatima University) removed per request;
  // OpenStreetMap's pin is at the right spot.

  // ── Hospitals ───────────────────────────────────────────────────────────
  // NOTE: 'our-lady-of-grace' (Our Lady of Grace Hospital) removed per
  // request; OpenStreetMap's pin is at the right spot.
  Place(
    id: 'mcu-fdtm',
    name: 'MCU-FDTMF Hospital',
    city: 'Caloocan',
    categories: [PlaceCategory.hospital],
    lat: 14.657536,
    lng: 120.987050,
    address: 'Samson Rd., Caloocan',
  ),
  Place(
    id: 'caloocan-medical',
    name: 'Caloocan Medical Center',
    city: 'Caloocan',
    categories: [PlaceCategory.hospital],
    lat: 14.648295,
    lng: 120.973461,
    address: 'Gen. Luna St., Caloocan',
  ),
  Place(
    id: 'ospital-ng-malabon',
    name: 'Ospital ng Malabon',
    city: 'Malabon',
    categories: [PlaceCategory.hospital],
    lat: 14.657190,
    lng: 120.950643,
    address: 'Brgy. San Agustin, Malabon',
  ),
  // NOTE: 'navotas-city-hospital' (Navotas City Hospital) removed per
  // request; OpenStreetMap's pin is at the right spot.
  Place(
    id: 'fatima-medical',
    name: 'Fatima University Medical Center',
    city: 'Valenzuela',
    categories: [PlaceCategory.hospital],
    lat: 14.678057,
    lng: 120.980371,
    address: 'McArthur Hwy., Karuhatan, Valenzuela',
  ),
  Place(
    id: 'valenzuela-medical-center',
    name: 'Valenzuela Medical Center',
    city: 'Valenzuela',
    categories: [PlaceCategory.hospital],
    lat: 14.689841,
    lng: 120.977759,
    address: 'A. Pablo St., Valenzuela',
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
  ),
  Place(
    id: 'sm-grand-central',
    name: 'SM City Grand Central',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.654965,
    lng: 120.984256,
    address: 'Rizal Ave. Ext., Monumento, Caloocan',
  ),
  // NOTE: 'monumento-mall' (Monumento Mall) and 'caloocan-mall' (Caloocan
  // Mall) removed per request: they were 27 m apart, and OpenStreetMap's
  // pins there (North mall, LRT Caloocan Mall, Jackman Plaza) are used.
  // NOTE: 'sm-malabon' (SM Center Malabon) removed per request.
  Place(
    id: 'vmall-monumento',
    name: 'VMall Monumento',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.655445,
    lng: 120.983665,
    address: 'Rizal Ave. Ext., Monumento, Caloocan',
  ),
  Place(
    id: 'waltermart-caloocan',
    name: 'WalterMart Caloocan',
    city: 'Caloocan',
    categories: [PlaceCategory.mall],
    lat: 14.641783,
    lng: 120.976003,
    address: 'Caloocan',
  ),
  Place(
    id: 'sm-city-valenzuela',
    name: 'SM City Valenzuela',
    city: 'Valenzuela',
    categories: [PlaceCategory.mall],
    lat: 14.685566,
    lng: 120.976647,
    address: 'McArthur Hwy., Karuhatan, Valenzuela',
  ),
  // NOTE: 'victory-central-mall' (Victory Central Mall Valenzuela) removed
  // per request; its spot was only a guess.
  Place(
    id: 'fisher-mall-malabon',
    name: 'Fisher Mall Malabon',
    city: 'Malabon',
    categories: [PlaceCategory.mall],
    lat: 14.656757,
    lng: 120.960674,
    address: 'Dagat-Dagatan Ave., Longos, Malabon',
  ),

  // ── Parks ───────────────────────────────────────────────────────────────
  // NOTE: 'navotas-centennial-park' (Navotas Centennial Park) removed per
  // request; OpenStreetMap's "Navotas City Park" pin is used.
  Place(
    id: 'valenzuela-peoples-park',
    name: 'Valenzuela People\'s Park',
    city: 'Valenzuela',
    categories: [PlaceCategory.park],
    lat: 14.691548,
    lng: 120.969967,
    address: 'Malinta, Valenzuela',
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
  ),
];

/// The closest curated place within [maxMeters] of [point], for naming
/// points along a route ("the stop near Bonifacio Monument"). Null when
/// nothing is close enough to be meaningful.
String? nearestCamanavaPlaceName(LatLng point, {double maxMeters = 350}) {
  const distance = Distance();
  String? best;
  var bestMeters = maxMeters;
  for (final place in camanavaPlaces) {
    final meters = distance.as(
      LengthUnit.Meter,
      point,
      LatLng(place.lat, place.lng),
    );
    if (meters <= bestMeters) {
      best = place.name;
      bestMeters = meters;
    }
  }
  return best;
}
