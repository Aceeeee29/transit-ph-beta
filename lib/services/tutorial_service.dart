import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import '../models/route.dart' as route_model;

class TutorialService {
  static const String _hasSeenContributeTutorialKey = 'has_seen_contribute_tutorial';
  
  /// Check if the user has seen the contribute tutorial
  static Future<bool> hasSeenContributeTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenContributeTutorialKey) ?? false;
  }
  
  /// Mark the contribute tutorial as seen
  static Future<void> markContributeTutorialAsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenContributeTutorialKey, true);
  }
  
  /// Reset tutorial status (for testing)
  static Future<void> resetTutorialStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenContributeTutorialKey, false);
  }
  
  /// Get tutorial steps for contribute screen
  static List<TutorialStep> getContributeTutorialSteps() {
    return [
      TutorialStep(
        title: 'Welcome to Route Creation!',
        description: 'Let\'s learn how to create and share transit routes with the community.',
        targetKey: 'map',
        animationAsset: 'map_overview',
      ),
      TutorialStep(
        title: 'Step 1: Select Starting Point',
        description: 'Tap on the map to mark where your route begins.',
        targetKey: 'map',
        animationAsset: 'tap_start_point',
      ),
      TutorialStep(
        title: 'Step 2: Choose Transport Mode',
        description: 'Select how you\'ll travel in this segment (bus, jeepney, walk, etc.).',
        targetKey: 'mode_selector',
        animationAsset: 'select_mode',
      ),
      TutorialStep(
        title: 'Step 3: Add Route Points',
        description: 'Tap to add more points along your route. The app will connect them automatically using snap-to-road.',
        targetKey: 'map',
        animationAsset: 'add_route_points',
      ),
      TutorialStep(
        title: 'Step 4: Add Instructions',
        description: 'For each segment, add helpful instructions like "Take the blue jeepney" or "Walk to the corner".',
        targetKey: 'step_form',
        animationAsset: 'add_instructions',
      ),
      TutorialStep(
        title: 'Step 5: Complete Your Route',
        description: 'Add as many segments as needed, then tap "Finish Route" when done.',
        targetKey: 'finish_button',
        animationAsset: 'finish_route',
      ),
      TutorialStep(
        title: 'Step 6: Fill Route Details',
        description: 'Add a description, estimated time, price, and schedule to help others.',
        targetKey: 'route_form',
        animationAsset: 'fill_details',
      ),
      TutorialStep(
        title: 'Step 7: Add Photos & Voice Notes',
        description: 'You can add landmark photos and record voice instructions to make your route easier to follow.',
        targetKey: 'media_buttons',
        animationAsset: 'add_media',
      ),
      TutorialStep(
        title: 'Step 8: Preview Your Route',
        description: 'Preview how your route will look to others before submitting it.',
        targetKey: 'preview_button',
        animationAsset: 'preview_route',
      ),
      TutorialStep(
        title: 'Ready to Go!',
        description: 'Now you know how to create routes. Your contributions help everyone navigate better!',
        targetKey: 'submit_button',
        animationAsset: 'submit_route',
      ),
    ];
  }
  
  /// Get example route data
  static Map<String, dynamic> getExampleRouteData() {
    return {
      'startLocation': 'SM North EDSA',
      'endLocation': 'Trinoma Mall',
      'shortDescription': 'Quick route from SM North to Trinoma via pedestrian walkway',
      'eta': '15',
      'price': 'Free',
      'schedule': '5AM-10PM daily',
      'steps': [
        {
          'mode': 'Walk',
          'instruction': 'Exit SM North EDSA at the main entrance',
          'details': 'Head towards the pedestrian walkway connecting to Trinoma'
        },
        {
          'mode': 'Walk',
          'instruction': 'Cross the pedestrian walkway over EDSA',
          'details': 'The walkway is covered and has moving walkways in some sections'
        },
        {
          'mode': 'Walk',
          'instruction': 'Enter Trinoma Mall',
          'details': 'The entrance leads directly to the Ground Floor'
        }
      ]
    };
  }
  
  /// Get example route with path points
  static route_model.Route getExampleRoute() {
    // Example route from SM North EDSA to Trinoma
    final List<LatLng> pathPoints = [
      LatLng(14.6572, 121.0317), // SM North EDSA
      LatLng(14.6575, 121.0320),
      LatLng(14.6580, 121.0325),
      LatLng(14.6585, 121.0330),
      LatLng(14.6590, 121.0335),
      LatLng(14.6595, 121.0340), // Trinoma Mall
    ];
    
    final List<route_model.Step> steps = [
      route_model.Step(
        mode: 'Walk',
        instruction: 'Exit SM North EDSA at the main entrance',
        details: 'Head towards the pedestrian walkway connecting to Trinoma',
      ),
      route_model.Step(
        mode: 'Walk',
        instruction: 'Cross the pedestrian walkway over EDSA',
        details: 'The walkway is covered and has moving walkways in some sections',
      ),
      route_model.Step(
        mode: 'Walk',
        instruction: 'Enter Trinoma Mall',
        details: 'The entrance leads directly to the Ground Floor',
      ),
    ];
    
    return route_model.Route(
      id: 'example-route',
      startLocation: 'SM North EDSA',
      endLocation: 'Trinoma Mall',
      shortDescription: 'Quick route from SM North to Trinoma via pedestrian walkway',
      steps: steps,
      startLat: pathPoints.first.latitude,
      startLng: pathPoints.first.longitude,
      endLat: pathPoints.last.latitude,
      endLng: pathPoints.last.longitude,
      pathPoints: pathPoints,
      stepBoundaries: [1, 3, 5],
      eta: '15',
      price: 'Free',
      schedule: '5AM-10PM daily',
    );
  }
}

class TutorialStep {
  final String title;
  final String description;
  final String targetKey;
  final String? animationAsset;
  
  TutorialStep({
    required this.title,
    required this.description,
    required this.targetKey,
    this.animationAsset,
  });
}
