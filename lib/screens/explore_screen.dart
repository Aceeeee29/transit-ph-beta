import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/ors_route_result.dart';
import '../models/place_model.dart';
import '../services/places_service.dart';
import '../services/distance_service.dart';
import '../services/routing_service.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _green = Color(0xFF3EC97A);

  PlaceCategory _selectedCategory = PlaceCategory.school;
  List<Place> _places = [];
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;
  bool _isLoadingLocation = true;
  String? _currentAddress;

  final MapController _mapController = MapController();
  bool _showMap = false;

  List<LatLng>? _previewPolyline;
  Place? _previewPlace;
  bool _isRouting = false;
  OrsRouteResult? _previewResult;

  static const Map<PlaceCategory, IconData> _categoryIcons = {
    PlaceCategory.school: Icons.school,
    PlaceCategory.hospital: Icons.local_hospital,
    PlaceCategory.mall: Icons.shopping_bag,
    PlaceCategory.publicPark: Icons.park,
  };

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final permission = await Permission.location.request();
    if (!permission.isGranted) {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      _currentPosition = pos;
      _isLoadingLocation = false;
      _refreshPlaces(pos.latitude, pos.longitude);
      setState(() {});
      _startLocationUpdates();
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  void _startLocationUpdates() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final prev = _currentPosition;
      _currentPosition = pos;
      _refreshPlaces(pos.latitude, pos.longitude);
      if (prev == null ||
          DistanceService.calculateM(
                prev.latitude,
                prev.longitude,
                pos.latitude,
                pos.longitude,
              ) >
              100) {
        setState(() {});
      } else {
        setState(() {});
      }
    });
  }

  void _refreshPlaces(double lat, double lng) {
    _places = PlacesService.getByCategorySorted(_selectedCategory, lat, lng);
  }

  void _onCategorySelected(PlaceCategory category) {
    setState(() {
      _selectedCategory = category;
      if (_currentPosition != null) {
        _refreshPlaces(_currentPosition!.latitude, _currentPosition!.longitude);
      }
    });
  }

  Future<void> _onPlaceTap(Place place) async {
    final pos = _currentPosition;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location unavailable. Cannot generate route preview.'),
        ),
      );
      return;
    }

    setState(() {
      _showMap = true;
      _previewPlace = place;
      _previewPolyline = null;
      _previewResult = null;
      _isRouting = true;
    });

    final result = await _loadRoutePreview(place);

    if (!mounted) return;

    if (result == null || result.polyline.length < 2) {
      setState(() {
        _previewPlace = null;
        _isRouting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not generate a route preview. Try again.'),
        ),
      );
      return;
    }

    setState(() {
      _previewPolyline = result.polyline;
      _previewResult = result;
      _isRouting = false;
    });
    _fitRouteBounds(result.polyline);
  }

  Future<OrsRouteResult?> _loadRoutePreview(Place place) async {
    final pos = _currentPosition!;
    final origin = LatLng(pos.latitude, pos.longitude);
    final destination = LatLng(place.latitude, place.longitude);
    try {
      return await RoutingService.getRoute(
        originName: 'Current Location',
        origin: origin,
        destinationName: place.name,
        destination: destination,
        mode: 'Jeepney',
      );
    } catch (e) {
      debugPrint('[ExploreScreen] GTFS route failed ($e) — OSRM walk fallback');
    }
    return RoutingService.snapToRoad(
      origin: origin,
      destination: destination,
      mode: 'Walk',
    );
  }

  void _fitRouteBounds(List<LatLng> pts) {
    var minLat = pts.first.latitude;
    var maxLat = pts.first.latitude;
    var minLng = pts.first.longitude;
    var maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (maxLat == minLat && maxLng == minLng) {
        _mapController.move(LatLng(minLat, minLng), 15);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(
              LatLng(minLat, minLng),
              LatLng(maxLat, maxLng),
            ),
            padding: const EdgeInsets.all(64),
          ),
        );
      }
    });
  }

  void _dismissRoutePreview() {
    setState(() {
      _previewPolyline = null;
      _previewPlace = null;
      _previewResult = null;
      _isRouting = false;
    });
  }

  String _formatDuration(int seconds) {
    return '${(seconds / 60).ceil()} min';
  }

  List<Polyline> _buildPreviewPolylines(
    List<LatLng> pts,
    List<OrsStep> steps,
  ) {
    final polylines = <Polyline>[];

    void addSegment(List<LatLng> seg, Color color) {
      if (seg.length < 2) return;
      polylines.add(
        Polyline(
          points: seg,
          color: Colors.white,
          strokeWidth: 7,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
      polylines.add(
        Polyline(
          points: seg,
          color: color,
          strokeWidth: 4.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }

    if (steps.isEmpty) {
      addSegment(pts, _accent);
      return polylines;
    }

    var cursor = 0;
    for (final step in steps) {
      final start = math.max(0, math.min(step.wayPointStart, pts.length - 1));
      final end = math.max(
        start + 1,
        math.min(step.wayPointEnd, pts.length - 1),
      );
      final lo = math.min(start, cursor);
      addSegment(pts.sublist(lo, end + 1), _modeColor(step.suggestedMode));
      cursor = end;
    }
    if (cursor < pts.length - 1) {
      addSegment(pts.sublist(cursor, pts.length), _accent);
    }
    return polylines;
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return Icons.directions_walk;
      case 'Jeepney':
        return Icons.directions_bus;
      case 'Bus':
        return Icons.directions_bus_filled;
      case 'Train':
        return Icons.train;
      case 'Tricycle':
        return Icons.two_wheeler;
      case 'FX/Van':
        return Icons.airport_shuttle;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_bus;
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'Walk':
        return Colors.green.shade600;
      case 'Jeepney':
        return Colors.blue.shade600;
      case 'Bus':
        return Colors.red.shade600;
      case 'Train':
        return Colors.purple.shade600;
      case 'Tricycle':
        return Colors.orange.shade600;
      case 'FX/Van':
        return Colors.amber.shade700;
      case 'Ferry':
        return Colors.lightBlue.shade600;
      default:
        return Colors.blue.shade600;
    }
  }

  String _modeLabel(List<OrsStep> steps) {
    final seen = <String>{};
    final modes = <String>[];
    for (final s in steps) {
      if (s.suggestedMode == 'Walk') continue;
      if (seen.add(s.suggestedMode)) modes.add(s.suggestedMode);
    }
    return modes.join(' + ');
  }

  Widget _buildStepRow(OrsStep step, {required bool isLast}) {
    final color = _modeColor(step.suggestedMode);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(_modeIcon(step.suggestedMode), color: color, size: 14),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 18,
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.suggestedMode,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        step.instruction,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (step.estimatedFare > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '₱${step.estimatedFare.round()}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _green,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    if (_places.isEmpty) return [];
    return _places.map((p) {
      return Marker(
        point: LatLng(p.latitude, p.longitude),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                p.distanceKm != null
                    ? DistanceService.formatDistance(p.distanceKm!)
                    : '',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              _categoryIcons[_selectedCategory] ?? Icons.location_on,
              color: _accent,
              size: 28,
            ),
          ],
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Nearby Places',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: _textPrimary,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => setState(() => _showMap = !_showMap),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _showMap ? _accentSoft : _surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _showMap ? _accent.withValues(alpha: 0.35) : _border,
                ),
              ),
              child: Icon(
                _showMap ? Icons.list_rounded : Icons.map_rounded,
                color: _showMap ? _accent : _textSecondary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCurrentLocationBanner(),
          _buildCategoryChips(),
          if (_showMap) _buildMapView(),
          Expanded(child: _buildPlaceList()),
        ],
      ),
    );
  }

  Widget _buildCurrentLocationBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.my_location_rounded,
              color: _accent,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                _isLoadingLocation
                    ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Location',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _textSecondary,
                          ),
                        ),
                        Text(
                          _currentPosition != null
                              ? '${_currentPosition!.latitude.toStringAsFixed(4)}, '
                                  '${_currentPosition!.longitude.toStringAsFixed(4)}'
                              : 'Location unavailable',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                      ],
                    ),
          ),
          if (_currentPosition != null)
            Text(
              '${_places.length} found',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children:
              PlaceCategory.values.map((cat) {
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _onCategorySelected(cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? _accent : _surfaceAlt,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isSelected ? _accent : _border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _categoryIcons[cat] ?? Icons.place,
                            size: 14,
                            color: isSelected ? Colors.white : _textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cat.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : _textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildMapView() {
    if (_currentPosition == null) return const SizedBox.shrink();

    final userLatLng = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    return Stack(
      children: [
        SizedBox(
          height: 260,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _places.isNotEmpty
                      ? LatLng(_places.first.latitude, _places.first.longitude)
                      : userLatLng,
              initialZoom: 14.0,
              minZoom: 5.0,
              maxZoom: 18.0,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(4.5, 116.0),
                  const LatLng(21.5, 127.0),
                ),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app.transitph_beta',
              ),
              if (_previewPolyline != null)
                PolylineLayer(
                  polylines: _buildPreviewPolylines(
                    _previewPolyline!,
                    _previewResult?.steps ?? const <OrsStep>[],
                  ),
                ),
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: userLatLng,
                      child: const Icon(
                        Icons.navigation,
                        color: _accent,
                        size: 32,
                      ),
                    ),
                  if (_previewPlace != null)
                    Marker(
                      point: LatLng(
                        _previewPlace!.latitude,
                        _previewPlace!.longitude,
                      ),
                      child: const Icon(
                        Icons.flag,
                        color: Color(0xFFE05C6A),
                        size: 32,
                      ),
                    ),
                  ..._buildMarkers(),
                ],
              ),
            ],
          ),
        ),
        if (_previewPlace != null || _isRouting)
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: _buildRoutePreviewCard(),
          ),
      ],
    );
  }

  Widget _buildRoutePreviewCard() {
    final place = _previewPlace;
    final result = _previewResult;
    final steps = result?.steps ?? const <OrsStep>[];
    final rideSteps = steps
        .where((s) => s.suggestedMode != 'Walk')
        .toList();
    final totalFare =
        rideSteps.fold<double>(0.0, (sum, s) => sum + s.estimatedFare);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child:
                    _isRouting
                        ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accent,
                          ),
                        )
                        : Icon(
                          _categoryIcons[place?.category] ?? Icons.place,
                          color: _accent,
                          size: 18,
                        ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child:
                    _isRouting
                        ? const Text(
                          'Generating route preview...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _textSecondary,
                          ),
                        )
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              place?.name ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                            if (result != null)
                              Text(
                                '${DistanceService.formatDistance(result.distanceMeters / 1000)}  •  '
                                '${_formatDuration(result.durationSeconds.round())}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _accent,
                                ),
                              ),
                            if (result != null && rideSteps.isNotEmpty)
                              Text(
                                '≈₱${totalFare.round()} fare • ${_modeLabel(rideSteps)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _green,
                                ),
                              ),
                          ],
                        ),
              ),
              if (!_isRouting)
                GestureDetector(
                  onTap: _dismissRoutePreview,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      color: _textSecondary,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
          if (!_isRouting && steps.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: _border),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      _buildStepRow(steps[i], isLast: i == steps.length - 1),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaceList() {
    if (_isLoadingLocation) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentPosition == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.location_disabled_rounded,
                size: 32,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Enable location to see nearby places',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_places.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 32,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No places found in this category',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _places.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final place = _places[index];
        return _PlaceCard(
          place: place,
          rank: index + 1,
          categoryIcon: _categoryIcons[place.category] ?? Icons.place,
          onTap: () => _onPlaceTap(place),
        );
      },
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final Place place;
  final int rank;
  final IconData categoryIcon;
  final VoidCallback onTap;

  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _green = Color(0xFF3EC97A);

  const _PlaceCard({
    required this.place,
    required this.rank,
    required this.categoryIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      place.address,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (place.distanceKm != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _green.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    DistanceService.formatDistance(place.distanceKm!),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _green,
                    ),
                  ),
                ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFFB9C9DE),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
