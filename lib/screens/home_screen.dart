import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import 'route_map_screen.dart';
import 'search_screen.dart';
import '../services/gamification_service.dart';
import '../services/weather_service.dart';
import '../services/location_service.dart';
import '../services/recommendation_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/home/fare_matrix_dialog.dart';

class HomeScreen extends StatefulWidget {
  final List<route_model.Route> routes;
  final Future<void> Function()? onRefresh;

  const HomeScreen({super.key, required this.routes, this.onRefresh});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  WeatherData? _weatherData;
  bool _isLoadingWeather = true;
  bool _isDetectingLocation = false;
  final Set<String> _selectedModes = {};
  Map<String, List<route_model.Route>> _recommendations = {};
  bool _isLoadingRecommendations = true;
  int? _totalUsers;
  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;

  // ─── Color tokens ────────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

  // ─── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _getWeather();
    _loadRecommendations();
    _loadTotalUsers();
  }

  @override
  void dispose() {
    _startController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _loadTotalUsers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .count()
          .get();
      if (mounted) setState(() => _totalUsers = snap.count);
    } catch (_) {
      // silently ignore — widget simply won't render
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoadingRecommendations = true);
    try {
      final recs = await RecommendationService.getAllRecommendations(widget.routes);
      setState(() {
        _recommendations = recs;
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      setState(() => _isLoadingRecommendations = false);
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting weather: $e')),
      );
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
              content: Text('Could not detect location. Please check permissions.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error detecting location: $e')),
        );
      }
    } finally {
      setState(() => _isDetectingLocation = false);
    }
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  // ─── Route actions ────────────────────────────────────────────────────────────

  void _findRoute() async {
    final destination = _destinationController.text.trim().toLowerCase();
    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a destination')),
      );
      return;
    }

    final user = await GamificationService.loadUser();
    final unlockedItems = await GamificationService.incrementRoutesSearched(user);
    if (unlockedItems.isNotEmpty) {
      setState(() {
        _pendingNotifications = unlockedItems;
        _showNotificationOverlay = true;
      });
    }

    final matched = widget.routes.where((route) {
      final matchesDest =
          route.endLocation.trim().toLowerCase().contains(destination) ||
          route.shortDescription.trim().toLowerCase().contains(destination);
      if (_selectedModes.isNotEmpty) {
        return matchesDest &&
            route.steps.any((s) => _selectedModes.contains(s.mode));
      }
      return matchesDest;
    }).toList();

    _showSearchResultsSheet(matched);
  }

  // ─── Dialogs / modals ────────────────────────────────────────────────────────

  void _showFareMatrixDialog() {
    showDialog(
      context: context,
      builder: (_) => const HomeFareMatrixDialog(),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Transport Mode'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: ['Jeepney', 'Bus', 'Train', 'Tricycle', 'FX/Van', 'Ferry', 'Walk']
                  .map((mode) => CheckboxListTile(
                        title: Row(
                          children: [
                            _modeIcon(mode),
                            const SizedBox(width: 8),
                            Text(mode),
                          ],
                        ),
                        value: _selectedModes.contains(mode),
                        onChanged: (checked) {
                          setDialogState(() {
                            setState(() {
                              if (checked == true) {
                                _selectedModes.add(mode);
                              } else {
                                _selectedModes.remove(mode);
                              }
                            });
                          });
                        },
                      ))
                  .toList(),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _selectedModes.clear());
              Navigator.pop(context);
              _findRoute();
            },
            child: const Text('Clear All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showSearchResultsSheet(List<route_model.Route> matchedRoutes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Search Results (${matchedRoutes.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showFilterDialog,
                      icon: const Icon(Icons.filter_list),
                      label: Text(
                        'Filter${_selectedModes.isNotEmpty ? ' (${_selectedModes.length})' : ''}',
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedModes.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: _selectedModes
                        .map((mode) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                label: Text(mode),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                onDeleted: () {
                                  setState(() => _selectedModes.remove(mode));
                                  _findRoute();
                                },
                              ),
                            ))
                        .toList(),
                  ),
                ),
              const Divider(),
              Expanded(
                child: matchedRoutes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No routes found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try adjusting your filters',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: matchedRoutes.length,
                        itemBuilder: (context, index) =>
                            _buildRouteCard(matchedRoutes[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Widget builders ─────────────────────────────────────────────────────────

  Widget _buildRouteCard(route_model.Route route) {
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RouteMapScreen(route: route)),
        ),
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
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: route.steps.map((step) => _modeChip(step.mode)).toList(),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _statItem(Icons.visibility_outlined, '${route.views}', _textSecondary),
                    const SizedBox(width: 14),
                    _statItem(Icons.thumb_up_outlined, '${route.upvotes}', const Color(0xFF3EC97A)),
                    const SizedBox(width: 14),
                    _statItem(Icons.thumb_down_outlined, '${route.downvotes}', _danger),
                    if (route.eta != null) ...[
                      const SizedBox(width: 14),
                      _statItem(Icons.schedule_outlined, route.eta!, _textSecondary),
                    ],
                    if (route.price != null) ...[
                      const SizedBox(width: 14),
                      _statItem(Icons.payments_outlined, route.price!, const Color(0xFF3EC97A)),
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

  Widget _buildRecommendationSection(String title, List<route_model.Route> routes) {
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
            itemBuilder: (context, index) =>
                _buildRecommendationCard(routes[index]),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRecommendationCard(route_model.Route route) {
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
                _statItem(Icons.visibility_outlined, '${route.views}', _textSecondary),
                const SizedBox(width: 10),
                _statItem(Icons.thumb_up_outlined, '${route.upvotes}', const Color(0xFF3EC97A)),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RouteMapScreen(route: route)),
              ),
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
                    Icon(Icons.map_outlined, color: Colors.white, size: 14),
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
  }

  Widget _statItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _modeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return const Icon(Icons.directions_walk, color: Colors.green, size: 20);
      case 'Jeepney':
        return const Icon(Icons.directions_bus, color: Colors.blue, size: 20);
      case 'Bus':
        return const Icon(Icons.directions_bus_filled, color: Colors.red, size: 20);
      case 'Train':
        return const Icon(Icons.train, color: Colors.purple, size: 20);
      case 'Tricycle':
        return const Icon(Icons.pedal_bike, color: Colors.orange, size: 20);
      case 'FX/Van':
        return const Icon(Icons.directions_car, color: Colors.amber, size: 20);
      case 'Ferry':
        return const Icon(Icons.directions_boat, color: Colors.lightBlue, size: 20);
      default:
        return const Icon(Icons.directions_walk, color: Colors.green, size: 20);
    }
  }

  Widget _modeChip(String mode) {
    const modeColors = {
      'Walk': Color(0xFF3EC97A),
      'Jeepney': Color(0xFF2E7CF6),
      'Bus': Color(0xFFE05C6A),
      'Train': Color(0xFF9B7FE8),
      'Tricycle': Color(0xFFE89A3C),
      'FX/Van': Color(0xFFD4A017),
      'Ferry': Color(0xFF3EC9D6),
    };
    final color = modeColors[mode] ?? _textSecondary;
    IconData iconData;
    switch (mode) {
      case 'Walk':
        iconData = Icons.directions_walk;
        break;
      case 'Jeepney':
        iconData = Icons.directions_bus;
        break;
      case 'Bus':
        iconData = Icons.directions_bus_filled;
        break;
      case 'Train':
        iconData = Icons.train;
        break;
      case 'Tricycle':
        iconData = Icons.pedal_bike;
        break;
      case 'FX/Van':
        iconData = Icons.directions_car;
        break;
      case 'Ferry':
        iconData = Icons.directions_boat;
        break;
      default:
        iconData = Icons.directions_walk;
    }
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
          Icon(iconData, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            mode,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

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
                _buildHeader(),
                const SizedBox(height: 20),
                _buildWeatherSection(),
                const SizedBox(height: 16),
                _buildSearchCard(),
                const SizedBox(height: 16),
                _buildFareButton(),
                if (_totalUsers != null) ...[
                  const SizedBox(height: 16),
                  _buildUserCountCard(),
                ],
                const SizedBox(height: 28),
                _buildRecommendations(),
                _buildCtaFooter(),
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

  Widget _buildHeader() {
    return Row(
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
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TransitPH',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Your community transit guide',
              style: TextStyle(fontSize: 12, color: _textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeatherSection() {
    if (_isLoadingWeather) {
      return Container(
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
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
          ),
        ),
      );
    }

    if (_weatherData == null) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    );
  }

  Widget _buildSearchCard() {
    return Container(
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
                      readOnly: true,
                      style: const TextStyle(color: _textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(
                          Icons.radio_button_checked,
                          color: Color(0xFF3EC97A),
                          size: 18,
                        ),
                        hintText: 'Starting from...',
                        hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
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
                  onTap: _isDetectingLocation ? null : _detectCurrentLocation,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isDetectingLocation ? _surfaceAlt : _accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isDetectingLocation
                            ? _border
                            : _accent.withOpacity(0.3),
                      ),
                    ),
                    child: _isDetectingLocation
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
                        : const Icon(Icons.my_location, color: _accent, size: 18),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
              child: Column(
                children: List.generate(
                  3,
                  (_) => Container(
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: const BoxDecoration(
                      color: _border,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchScreen(
                    routes: widget.routes,
                    onRefresh: widget.onRefresh,
                  ),
                ),
              ),
              child: AbsorbPointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: TextField(
                    controller: _destinationController,
                    style: const TextStyle(color: _textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.location_on,
                        color: _accent,
                        size: 18,
                      ),
                      hintText: 'Going to...',
                      hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
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
    );
  }

  Widget _buildUserCountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.people_alt_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_totalUsers!.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} commuters',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const Text(
                'Community members & counting',
                style: TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF3EC97A).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.circle, size: 7, color: Color(0xFF3EC97A)),
                SizedBox(width: 5),
                Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3EC97A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFareButton() {
    return GestureDetector(
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
    );
  }

  Widget _buildRecommendations() {
    if (_isLoadingRecommendations) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recommendations['rushHourAlternatives']?.isNotEmpty == true)
          _buildRecommendationSection(
            '🚗 Rush Hour Alternatives',
            _recommendations['rushHourAlternatives']!,
          ),
        if (_recommendations['forYou']?.isNotEmpty == true)
          _buildRecommendationSection(
            '⭐ Recommended for You',
            _recommendations['forYou']!,
          ),
        if (_recommendations['popular']?.isNotEmpty == true)
          _buildRecommendationSection(
            '🔥 Popular Routes',
            _recommendations['popular']!,
          ),
      ],
    );
  }

  Widget _buildCtaFooter() {
    return Container(
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
            child: const Icon(Icons.add_road, color: _accent, size: 20),
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
            style: TextStyle(fontSize: 13, color: _textSecondary, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
