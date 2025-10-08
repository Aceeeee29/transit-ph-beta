import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import 'route_map_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<route_model.Route> routes;

  const HomeScreen({super.key, required this.routes});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  void _findRoute() {
    final start = _startController.text.trim().toLowerCase();
    final destination = _destinationController.text.trim().toLowerCase();

    if (start.isEmpty || destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both starting point and destination'),
        ),
      );
      return;
    }

    final matchedRoutes =
        widget.routes.where((route) {
          return route.startLocation.toLowerCase().contains(start) &&
              route.endLocation.toLowerCase().contains(destination);
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
                                        icon: const Icon(Icons.map),
                                        label: const Text('View Map'),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 32),
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
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Find Route'),
                      ),
                    ),
                  ],
                ),
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
          ],
        ),
      ),
    );
  }
}
