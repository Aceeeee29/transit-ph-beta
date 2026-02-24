import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import 'route_map_screen.dart';
import 'search_screen.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';
import '../services/bookmark_service.dart';
import '../services/recommendation_service.dart';
import '../widgets/notification_overlay.dart';

class HomeScreen extends StatefulWidget {
  final List<route_model.Route> routes;

  const HomeScreen({super.key, required this.routes});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  WeatherData? _weatherData;
  bool _isLoadingWeather = true;
  bool _isDetectingLocation = false;

  // Bookmarks
  Set<String> _bookmarkedRouteIds = {};

  // Recommendations
  Map<String, List<route_model.Route>> _recommendations = {};
  bool _isLoadingRecommendations = true;

  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;

  // ─── Color tokens (matches CreatePostDialog design system) ─────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

  @override
  void initState() {
    super.initState();
    _getWeather();
    _loadBookmarks();
    _loadRecommendations();
  }

  Future<void> _loadBookmarks() async {
    final bookmarkedIds = await BookmarkService.getBookmarkedRouteIds();
    setState(() {
      _bookmarkedRouteIds = bookmarkedIds.toSet();
    });
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _isLoadingRecommendations = true;
    });

    try {
      final recommendations = await RecommendationService.getAllRecommendations(
        widget.routes,
      );
      setState(() {
        _recommendations = recommendations;
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingRecommendations = false;
      });
    }
  }

  Widget _buildRouteCard(route_model.Route route) {
    final isBookmarked = _bookmarkedRouteIds.contains(route.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RouteMapScreen(route: route),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${route.startLocation} → ${route.endLocation}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final newState = await BookmarkService.toggleBookmark(
                        route.id,
                      );
                      setState(() {
                        if (newState) {
                          _bookmarkedRouteIds.add(route.id);
                        } else {
                          _bookmarkedRouteIds.remove(route.id);
                        }
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              newState
                                  ? 'Route saved for later'
                                  : 'Route removed from saved',
                            ),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isBookmarked ? _accentSoft : _surfaceAlt,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color:
                              isBookmarked ? _accent.withOpacity(0.3) : _border,
                        ),
                      ),
                      child: Icon(
                        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                        color: isBookmarked ? _accent : _textSecondary,
                        size: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                route.shortDescription,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              // Transport modes
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children:
                    route.steps.map((step) => _modeChip(step.mode)).toList(),
              ),
              const SizedBox(height: 10),
              // Stats row
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _statItem(
                      Icons.visibility_outlined,
                      '${route.views}',
                      _textSecondary,
                    ),
                    const SizedBox(width: 14),
                    _statItem(
                      Icons.thumb_up_outlined,
                      '${route.upvotes}',
                      const Color(0xFF3EC97A),
                    ),
                    const SizedBox(width: 14),
                    _statItem(
                      Icons.thumb_down_outlined,
                      '${route.downvotes}',
                      _danger,
                    ),
                    if (route.eta != null) ...[
                      const SizedBox(width: 14),
                      _statItem(
                        Icons.schedule_outlined,
                        route.eta!,
                        _textSecondary,
                      ),
                    ],
                    if (route.price != null) ...[
                      const SizedBox(width: 14),
                      _statItem(
                        Icons.payments_outlined,
                        route.price!,
                        const Color(0xFF3EC97A),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _getWeather() async {
    setState(() => _isLoadingWeather = true);

    try {
      final weatherData = await WeatherService.getCurrentWeatherAndLocation();
      if (weatherData != null) {
        setState(() {
          _weatherData = weatherData;
          _startController.text = weatherData.address;
          _isLoadingWeather = false;
        });
      } else {
        setState(() => _isLoadingWeather = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error getting weather: $e')));
      setState(() => _isLoadingWeather = false);
    }
  }

  Future<void> _detectCurrentLocation() async {
    setState(() => _isDetectingLocation = true);

    try {
      final address = await LocationService.getCurrentLocationAddress();
      if (address != null) {
        setState(() => _startController.text = address);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location detected successfully'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not detect location. Please check permissions.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error detecting location: $e')));
      }
    } finally {
      setState(() => _isDetectingLocation = false);
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Widget _modeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return const Icon(Icons.directions_walk, color: Colors.green, size: 20);
      case 'Jeepney':
        return const Icon(Icons.directions_bus, color: Colors.blue, size: 20);
      case 'Bus':
        return const Icon(
          Icons.directions_bus_filled,
          color: Colors.red,
          size: 20,
        );
      case 'Train':
        return const Icon(Icons.train, color: Colors.purple, size: 20);
      case 'Tricycle':
        return const Icon(Icons.pedal_bike, color: Colors.orange, size: 20);
      case 'FX/Van':
        return const Icon(Icons.directions_car, color: Colors.amber, size: 20);
      case 'Ferry':
        return const Icon(
          Icons.directions_boat,
          color: Colors.lightBlue,
          size: 20,
        );
      default:
        return const Icon(Icons.directions_walk, color: Colors.green, size: 20);
    }
  }

  // Pill chip version of mode icon for cards
  Widget _modeChip(String mode) {
    final Map<String, Color> modeColors = {
      'Walk': const Color(0xFF3EC97A),
      'Jeepney': _accent,
      'Bus': _danger,
      'Train': const Color(0xFF9B7FE8),
      'Tricycle': const Color(0xFFE89A3C),
      'FX/Van': const Color(0xFFD4A017),
      'Ferry': const Color(0xFF3EC9D6),
    };
    final color = modeColors[mode] ?? _textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_modeIconData(mode), size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            mode,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _modeIconData(String mode) {
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
        return Icons.pedal_bike;
      case 'FX/Van':
        return Icons.directions_car;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_walk;
    }
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  void _showFareMatrixDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: _accent.withOpacity(0.08),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    border: Border(
                      bottom: BorderSide(color: _border, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.payments_outlined,
                          color: _accent,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Fare Matrix',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _surfaceAlt,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 15,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children:
                        [
                              _fareRow(
                                'Jeepney',
                                '₱13 base fare',
                                Icons.directions_bus,
                                _accent,
                              ),
                              _fareRow(
                                'City Bus',
                                '₱13 – ₱40+',
                                Icons.directions_bus_filled,
                                _danger,
                              ),
                              _fareRow(
                                'Train (LRT/MRT)',
                                '₱20 – ₱55',
                                Icons.train,
                                const Color(0xFF9B7FE8),
                              ),
                              _fareRow(
                                'Tricycle',
                                '₱15 – ₱60+',
                                Icons.pedal_bike,
                                const Color(0xFFE89A3C),
                              ),
                              _fareRow(
                                'FX / UV Express',
                                '₱30 – ₱100+',
                                Icons.directions_car,
                                const Color(0xFFD4A017),
                              ),
                            ]
                            .map(
                              (row) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: row,
                              ),
                            )
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fareRow(String label, String fare, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
          Text(
            fare,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationSection(
    String title,
    List<route_model.Route> routes,
  ) {
    if (routes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: _textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: routes.length > 5 ? 5 : routes.length,
            itemBuilder: (context, index) {
              final route = routes[index];
              final isBookmarked = _bookmarkedRouteIds.contains(route.id);
              return Container(
                width: 240,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${route.startLocation} → ${route.endLocation}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: _textPrimary,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final newState =
                                  await BookmarkService.toggleBookmark(
                                    route.id,
                                  );
                              setState(() {
                                if (newState) {
                                  _bookmarkedRouteIds.add(route.id);
                                } else {
                                  _bookmarkedRouteIds.remove(route.id);
                                }
                              });
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isBookmarked ? _accentSoft : _surfaceAlt,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color:
                                      isBookmarked
                                          ? _accent.withOpacity(0.3)
                                          : _border,
                                ),
                              ),
                              child: Icon(
                                isBookmarked
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                color: isBookmarked ? _accent : _textSecondary,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        route.shortDescription,
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          _statItem(
                            Icons.visibility_outlined,
                            '${route.views}',
                            _textSecondary,
                          ),
                          const SizedBox(width: 10),
                          _statItem(
                            Icons.thumb_up_outlined,
                            '${route.upvotes}',
                            const Color(0xFF3EC97A),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (context) => RouteMapScreen(route: route),
                            ),
                          );
                        },
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withOpacity(0.28),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map_outlined,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'View Route',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: _bg),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),

                // ─── Hero header ───────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_transit_filled,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TransitPH',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Text(
                          'Your community transit guide',
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Weather card
                if (_isLoadingWeather)
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accent,
                        ),
                      ),
                    ),
                  )
                else if (_weatherData != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.wb_sunny_outlined,
                            color: Color(0xFFE89A3C),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_weatherData!.condition}  •  ${_weatherData!.temp}  •  💧 ${_weatherData!.humidity}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_weatherData!.isStorm) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _danger.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(
                              Icons.warning_amber_outlined,
                              color: _danger,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Storm Warning: Severe weather expected. Plan accordingly.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),

                // ─── Search card with location detection ───────────────────
                Container(
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Starting location with detect button
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _surfaceAlt,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _border),
                                ),
                                child: TextField(
                                  controller: _startController,
                                  style: const TextStyle(
                                    color: _textPrimary,
                                    fontSize: 14,
                                  ),
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(
                                      Icons.radio_button_checked,
                                      color: Color(0xFF3EC97A),
                                      size: 18,
                                    ),
                                    hintText: 'Starting from...',
                                    hintStyle: TextStyle(
                                      color: _textSecondary,
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 13,
                                      horizontal: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap:
                                  _isDetectingLocation
                                      ? null
                                      : _detectCurrentLocation,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color:
                                      _isDetectingLocation
                                          ? _surfaceAlt
                                          : _accentSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        _isDetectingLocation
                                            ? _border
                                            : _accent.withOpacity(0.3),
                                  ),
                                ),
                                child:
                                    _isDetectingLocation
                                        ? const Center(
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: _accent,
                                            ),
                                          ),
                                        )
                                        : const Icon(
                                          Icons.my_location,
                                          color: _accent,
                                          size: 18,
                                        ),
                              ),
                            ),
                          ],
                        ),
                        // Connector dots
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 20,
                            top: 4,
                            bottom: 4,
                          ),
                          child: Column(
                            children: List.generate(
                              3,
                              (_) => Container(
                                width: 3,
                                height: 3,
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: _border,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Destination
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (context) =>
                                        SearchScreen(routes: widget.routes),
                              ),
                            );
                          },
                          child: AbsorbPointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: _surfaceAlt,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _border),
                              ),
                              child: TextField(
                                controller: _destinationController,
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 14,
                                ),
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(
                                    Icons.location_on,
                                    color: _accent,
                                    size: 18,
                                  ),
                                  hintText: 'Going to...',
                                  hintStyle: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 13,
                                    horizontal: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ─── Action buttons row ────────────────────────────────────
                GestureDetector(
                  onTap: _showFareMatrixDialog,
                  child: Container(
                    height: 48,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _border, width: 1.5),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.payments_outlined, color: _accent, size: 17),
                        SizedBox(width: 8),
                        Text(
                          'View Fare Matrix',
                          style: TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ─── Dynamic recommendations section ──────────────────────
                if (_isLoadingRecommendations)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(color: _accent),
                    ),
                  )
                else ...[
                  // Rush hour alternatives
                  if (_recommendations['rushHourAlternatives']?.isNotEmpty ==
                      true)
                    _buildRecommendationSection(
                      '🚗 Rush Hour Alternatives',
                      _recommendations['rushHourAlternatives']!,
                    ),

                  // Based on your searches
                  if (_recommendations['forYou']?.isNotEmpty == true)
                    _buildRecommendationSection(
                      '⭐ Recommended for You',
                      _recommendations['forYou']!,
                    ),

                  // Popular routes
                  if (_recommendations['popular']?.isNotEmpty == true)
                    _buildRecommendationSection(
                      '🔥 Popular Routes',
                      _recommendations['popular']!,
                    ),
                ],

                // ─── CTA footer ────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accent.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: _border),
                        ),
                        child: const Icon(
                          Icons.add_road,
                          color: _accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'New to the area?',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Help build our database by contributing a route you know!',
                        style: TextStyle(
                          fontSize: 13,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
        if (_showNotificationOverlay)
          NotificationOverlay(
            notifications: _pendingNotifications,
            onAllDismissed: _onNotificationsDismissed,
          ),
      ],
    );
  }
}
