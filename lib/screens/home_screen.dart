import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import 'route_map_screen.dart';
import '../services/gamification_service.dart';
import '../services/weather_service.dart';
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

  List<String> _pendingNotifications = [];
  bool _showNotificationOverlay = false;

  void _findRoute() async {
    final start = _startController.text.trim().toLowerCase();
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
          final matchesDestination = route.endLocation.trim().toLowerCase().contains(
            destination,
          ) || route.shortDescription.trim().toLowerCase().contains(destination);
          return matchesDestination;
        }).toList();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Route Search Results'),
            content: SizedBox(
              width: double.maxFinite,
              child:
                  matchedRoutes.isEmpty
                      ? const Text('No routes found.')
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: matchedRoutes.length,
                        itemBuilder: (context, index) {
                          final route = matchedRoutes[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${route.startLocation} to ${route.endLocation}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    route.shortDescription,
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Views: ${route.views} | Upvotes: ${route.upvotes} | Downvotes: ${route.downvotes}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: route.steps.length,
                                    itemBuilder: (context, stepIndex) {
                                      final step = route.steps[stepIndex];
                                      return ListTile(
                                        leading: _modeIcon(step.mode),
                                        title: Text(step.instruction),
                                        subtitle: Text(step.details),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  if (route.startLat != null &&
                                      route.startLng != null &&
                                      route.endLat != null &&
                                      route.endLng != null)
                                    Center(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder:
                                                  (context) => RouteMapScreen(
                                                    route: route,
                                                  ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.map,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'View Map',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  @override
  void initState() {
    super.initState();
    _getWeather();
  }

  Future<void> _getWeather() async {
    setState(() {
      _isLoadingWeather = true;
    });

    try {
      final weatherData = await WeatherService.getCurrentWeatherAndLocation();
      if (weatherData != null) {
        setState(() {
          _weatherData = weatherData;
          _startController.text = weatherData.address;
          _isLoadingWeather = false;
        });
      } else {
        setState(() {
          _isLoadingWeather = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting weather: $e')),
      );
      setState(() {
        _isLoadingWeather = false;
      });
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
        return const Icon(Icons.directions_walk, color: Colors.green);
      case 'Jeepney':
        return const Icon(Icons.directions_bus, color: Colors.blue);
      case 'Bus':
        return const Icon(Icons.directions_bus_filled, color: Colors.red);
      case 'Train':
        return const Icon(Icons.train, color: Colors.purple);
      case 'Tricycle':
        return const Icon(Icons.pedal_bike, color: Colors.orange);
      case 'FX/Van':
        return const Icon(Icons.directions_car, color: Colors.amber);
      case 'Ferry':
        return const Icon(Icons.directions_boat, color: Colors.lightBlue);
      default:
        return const Icon(Icons.directions_walk, color: Colors.green);
    }
  }

  void _onNotificationsDismissed() {
    setState(() {
      _showNotificationOverlay = false;
      _pendingNotifications.clear();
    });
  }

  void _voteRoute(route_model.Route route, bool isUpvote) {
    setState(() {
      if (isUpvote) {
        route.upvotes++;
      } else {
        route.downvotes++;
      }
    });
    // In a real app, persist this to a database
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
                if (_isLoadingWeather)
                  const Center(child: CircularProgressIndicator())
                else if (_weatherData != null)
                  Column(
                    children: [
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
                  ),
                const SizedBox(height: 16),
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
                        TextField(
                          controller: _startController,
                          readOnly: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            hintText: 'Starting from...',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _destinationController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            hintText: 'Going to...',
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _findRoute,
                            icon: const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Find Route',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Routes you may like',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount:
                        widget.routes.length > 5 ? 5 : widget.routes.length,
                    itemBuilder: (context, index) {
                      final route = widget.routes[index];
                      return Card(
                        margin: const EdgeInsets.only(right: 16),
                        child: Container(
                          width: 250,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${route.startLocation} to ${route.endLocation}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
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
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder:
                                          (context) =>
                                              RouteMapScreen(route: route),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.map,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'View',
                                  style: TextStyle(color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
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
                const SizedBox(height: 32),
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
