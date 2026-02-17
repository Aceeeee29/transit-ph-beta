import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import 'route_map_screen.dart';
import 'search_screen.dart';
import '../services/gamification_service.dart';
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

  // Search filters
  final Set<String> _selectedModes = {};

  // Bookmarks
  Set<String> _bookmarkedRouteIds = {};

  // Recommendations
  Map<String, List<route_model.Route>> _recommendations = {};
  bool _isLoadingRecommendations = true;

  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;

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

  void _findRoute() async {
    final destination = _destinationController.text.trim().toLowerCase();

    if (destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a destination')),
      );
      return;
    }

    // Award points for searching
    final user = await GamificationService.loadUser();
    final unlockedItems = await GamificationService.incrementRoutesSearched(
      user,
    );

    // Show achievement notifications
    if (unlockedItems.isNotEmpty) {
      setState(() {
        _pendingNotifications = unlockedItems;
        _showNotificationOverlay = true;
      });
    }

    final matchedRoutes =
        widget.routes.where((route) {
          final matchesDestination =
              route.endLocation.trim().toLowerCase().contains(destination) ||
              route.shortDescription.trim().toLowerCase().contains(destination);

          // Apply filters
          if (_selectedModes.isNotEmpty) {
            final hasMatchingMode = route.steps.any(
              (step) => _selectedModes.contains(step.mode),
            );
            return matchesDestination && hasMatchingMode;
          }

          return matchesDestination;
        }).toList();

    _showSearchResultsBottomSheet(matchedRoutes);
  }

  void _showSearchResultsBottomSheet(List<route_model.Route> matchedRoutes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header with filters
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
                              onPressed: () => _showFilterDialog(),
                              icon: const Icon(Icons.filter_list),
                              label: Text(
                                'Filter${_selectedModes.isNotEmpty ? ' (${_selectedModes.length})' : ''}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Filter chips
                      if (_selectedModes.isNotEmpty)
                        SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children:
                                _selectedModes
                                    .map(
                                      (mode) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: Chip(
                                          label: Text(mode),
                                          deleteIcon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          onDeleted: () {
                                            setState(() {
                                              _selectedModes.remove(mode);
                                            });
                                            _findRoute();
                                          },
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
                      const Divider(),
                      // Results
                      Expanded(
                        child:
                            matchedRoutes.isEmpty
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
                                  itemBuilder:
                                      (context, index) =>
                                          _buildRouteCard(matchedRoutes[index]),
                                ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Filter by Transport Mode'),
            content: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      [
                            'Jeepney',
                            'Bus',
                            'Train',
                            'Tricycle',
                            'FX/Van',
                            'Ferry',
                            'Walk',
                          ]
                          .map(
                            (mode) => CheckboxListTile(
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
                            ),
                          )
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

  Widget _buildRouteCard(route_model.Route route) {
    final isBookmarked = _bookmarkedRouteIds.contains(route.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RouteMapScreen(route: route),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${route.startLocation} to ${route.endLocation}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: isBookmarked ? Colors.blue : Colors.grey,
                    ),
                    onPressed: () async {
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
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                route.shortDescription,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Transport modes
              Wrap(
                spacing: 4,
                children:
                    route.steps.map((step) => _modeIcon(step.mode)).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.visibility, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${route.views}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.thumb_up, size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${route.upvotes}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.thumb_down, size: 16, color: Colors.red.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${route.downvotes}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (route.eta != null) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      route.eta!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  if (route.price != null) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.attach_money,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      route.price!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
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

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: routes.length > 5 ? 5 : routes.length,
            itemBuilder: (context, index) {
              final route = routes[index];
              final isBookmarked = _bookmarkedRouteIds.contains(route.id);
              return Card(
                margin: const EdgeInsets.only(right: 16),
                child: Container(
                  width: 250,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${route.startLocation} to ${route.endLocation}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
                            child: Icon(
                              isBookmarked
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              color: isBookmarked ? Colors.blue : Colors.grey,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        route.shortDescription,
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(
                            Icons.visibility,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${route.views}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.thumb_up,
                            size: 14,
                            color: Colors.green.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${route.upvotes}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (context) => RouteMapScreen(route: route),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.map,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'View',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Text(
                  'TransitPH',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your community guide to Philippine transit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 16),

                // Weather card
                if (_isLoadingWeather)
                  const Center(child: CircularProgressIndicator())
                else if (_weatherData != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.wb_sunny, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Current Weather: ${_weatherData!.condition}, ${_weatherData!.temp}, Precipitation: ${_weatherData!.precipitation}, Humidity: ${_weatherData!.humidity}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_weatherData!.isStorm)
                    Card(
                      color: Colors.red.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.warning, color: Colors.red),
                            const SizedBox(width: 8),
                            const Text(
                              'Storm Warning: Severe weather expected. Plan accordingly.',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),

                // Search card with location detection
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 6,
                  shadowColor: Colors.black12,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Starting location with detect button
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _startController,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.location_on_outlined,
                                  ),
                                  hintText: 'Starting from...',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed:
                                  _isDetectingLocation
                                      ? null
                                      : _detectCurrentLocation,
                              icon:
                                  _isDetectingLocation
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(
                                        Icons.my_location,
                                        color: Colors.blue,
                                      ),
                              tooltip: 'Use Current Location',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
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
                            child: TextField(
                              controller: _destinationController,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(
                                  Icons.location_on_outlined,
                                ),
                                hintText: 'Going to...',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Dynamic recommendations section
                if (_isLoadingRecommendations)
                  const Center(child: CircularProgressIndicator())
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

                const SizedBox(height: 16),
                const Text(
                  'New to the area?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Help build our database by contributing a route you know!',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
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
