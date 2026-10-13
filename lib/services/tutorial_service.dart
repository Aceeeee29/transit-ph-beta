import 'dart:ui';
import 'package:latlong2/latlong.dart';
import '../models/route.dart' as route_model;
import 'gamification_service.dart';

class TutorialService {
  /// Check if the user has seen the contribute tutorial
  static Future<bool> hasSeenContributeTutorial() async {
    try {
      final user = await GamificationService.loadUser();
      return user.hasSeenTutorial;
    } catch (_) {
      return false;
    }
  }

  /// Mark the contribute tutorial as seen
  static Future<void> markContributeTutorialAsSeen() async {
    try {
      final user = await GamificationService.loadUser();
      user.hasSeenTutorial = true;
      await GamificationService.saveUser(user);
    } catch (_) {}
  }

  /// Reset tutorial status (for testing)
  static Future<void> resetTutorialStatus() async {
    try {
      final user = await GamificationService.loadUser();
      user.hasSeenTutorial = false;
      await GamificationService.saveUser(user);
    } catch (_) {}
  }

  /// Get tutorial steps for contribute screen
  static List<TutorialStep> getContributeTutorialSteps() {
    // Using manual positions for better control
    // Assuming typical screen size, positions are approximate
    return [
      TutorialStep(
        title: 'Welcome to Route Creation!',
        description:
            'Let\'s learn how to create and share transit routes with the community.',
        targetKey: 'map',
        animationAsset: 'map_overview',
        customPosition: const Offset(200, 150), // Center of map area
        customSize: const Size(400, 300),
      ),
      TutorialStep(
        title: 'Step 1: Select Starting Point',
        description: 'Tap on the map to mark where your route begins.',
        targetKey: 'map',
        animationAsset: 'tap_start_point',
        customPosition: const Offset(200, 150),
        customSize: const Size(400, 300),
      ),
      TutorialStep(
        title: 'Step 2: Choose Transport Mode',
        description:
            'Select how you\'ll travel in this segment (bus, jeepney, walk, etc.).',
        targetKey: 'mode_selector',
        animationAsset: 'select_mode',
        customPosition: const Offset(20, 100), // Top left controls
        customSize: const Size(200, 100),
      ),
      TutorialStep(
        title: 'Step 3: Add Route Points',
        description:
            'Tap to add more points along your route. The app will connect them automatically using snap-to-road.',
        targetKey: 'map',
        animationAsset: 'add_route_points',
        customPosition: const Offset(200, 150),
        customSize: const Size(400, 300),
      ),
      TutorialStep(
        title: 'Step 4: Add Instructions',
        description:
            'For each segment, add helpful instructions like "Take the blue jeepney" or "Walk to the corner".',
        targetKey: 'mode_selector',
        animationAsset: 'add_instructions',
        customPosition: const Offset(20, 100),
        customSize: const Size(200, 100),
      ),
      TutorialStep(
        title: 'Step 5: Complete Your Route',
        description:
            'Add as many segments as needed, then tap "Finish Route" when done.',
        targetKey: 'submit_button',
        animationAsset: 'finish_route',
        customPosition: const Offset(150, 500), // Bottom form area
        customSize: const Size(150, 50),
      ),
      TutorialStep(
        title: 'Step 6: Select Route Tags',
        description:
            'Choose tags that best match who this route helps and the route style (budget, fast, accessible, etc.).',
        targetKey: 'route_form',
        animationAsset: 'select_tags',
        customPosition: const Offset(50, 400), // Form area
        customSize: const Size(300, 200),
      ),
      TutorialStep(
        title: 'Step 7: Fill Route Details',
        description:
            'Add a description, estimated time, price, and schedule to help others.',
        targetKey: 'route_form',
        animationAsset: 'fill_details',
        customPosition: const Offset(50, 400), // Form area
        customSize: const Size(300, 200),
      ),
      TutorialStep(
        title: 'Step 8: Preview Your Route',
        description:
            'Preview how your route will look to others before submitting it.',
        targetKey: 'preview_button',
        animationAsset: 'preview_route',
        customPosition: const Offset(20, 80), // App bar preview button
        customSize: const Size(100, 40),
      ),
      TutorialStep(
        title: 'Ready to Go!',
        description:
            'Now you know how to create routes. Your contributions help everyone navigate better!',
        targetKey: 'submit_button',
        animationAsset: 'submit_route',
        customPosition: const Offset(150, 500),
        customSize: const Size(150, 50),
      ),
    ];
  }

  /// The route Load Example fills in: a real CAMANAVA commute (LRT-1
  /// Monumento to Our Lady of Fatima University by MacArthur Highway
  /// jeepney), with each step drawn along the street.
  static route_model.Route getExampleRoute() {
    const walkToJeep = [
      LatLng(14.654300, 120.983813), // LRT-1 Monumento Station
      LatLng(14.655500, 120.983850),
      LatLng(14.656400, 120.983930),
      LatLng(14.656782, 120.984040),
      LatLng(14.656848, 120.984199),
      LatLng(14.657032, 120.984332),
      LatLng(14.657271, 120.984319),
      LatLng(14.657456, 120.984139),
      LatLng(14.657630, 120.984045),
      LatLng(14.658032, 120.984051), // MacArthur Highway, north of the monument
    ];
    const jeepney = [
      LatLng(14.658032, 120.984051),
      LatLng(14.659410, 120.984100),
      LatLng(14.661264, 120.984152),
      LatLng(14.662576, 120.984195),
      LatLng(14.663655, 120.984224),
      LatLng(14.664780, 120.984262),
      LatLng(14.665165, 120.984270),
      LatLng(14.665296, 120.984261),
      LatLng(14.665429, 120.984242),
      LatLng(14.665623, 120.984195),
      LatLng(14.665706, 120.984161),
      LatLng(14.665834, 120.984094),
      LatLng(14.665955, 120.984016),
      LatLng(14.666899, 120.983139),
      LatLng(14.667701, 120.982416),
      LatLng(14.667841, 120.982316),
      LatLng(14.668003, 120.982226),
      LatLng(14.668235, 120.982137),
      LatLng(14.668475, 120.982086),
      LatLng(14.668632, 120.982070),
      LatLng(14.669753, 120.982081),
      LatLng(14.669801, 120.982046),
      LatLng(14.671360, 120.982063),
      LatLng(14.672451, 120.982086),
      LatLng(14.672784, 120.982070),
      LatLng(14.672993, 120.982027),
      LatLng(14.673113, 120.981993),
      LatLng(14.674304, 120.981535),
      LatLng(14.675468, 120.981089),
      LatLng(14.676507, 120.980686),
      LatLng(14.677523, 120.980302),
      LatLng(14.677582, 120.980313),
      LatLng(14.678058, 120.980143), // In front of Fatima University
    ];
    const walkToCampus = [
      LatLng(14.678058, 120.980143),
      LatLng(14.678120, 120.980500),
      LatLng(14.678099, 120.980963), // Our Lady of Fatima University
    ];

    // Consecutive steps share their meeting point.
    final pathPoints = [
      ...walkToJeep,
      ...jeepney.skip(1),
      ...walkToCampus.skip(1),
    ];
    final jeepStart = walkToJeep.length - 1;
    final jeepEnd = jeepStart + jeepney.length - 1;

    final steps = [
      route_model.Step(
        mode: 'Walk',
        instruction: 'Walk to the jeepney stop on MacArthur Highway',
        details:
            'Exit LRT-1 Monumento Station and walk north past the '
            'Bonifacio Monument to the start of MacArthur Highway.',
        controlPoints: [walkToJeep.first, walkToJeep.last],
      ),
      route_model.Step(
        mode: 'Jeepney',
        instruction: 'Ride a jeepney with a "Malinta" signboard',
        details:
            'Stay on MacArthur Highway northbound and tell the driver '
            '"Para sa Fatima". Pay the minimum fare.',
        actualFare: 13,
        boarding: route_model.StepBoarding.flexible,
        controlPoints: [jeepney.first, jeepney.last],
      ),
      route_model.Step(
        mode: 'Walk',
        instruction: 'Walk to the university gate',
        details: 'Cross to the campus side of MacArthur Highway.',
        controlPoints: [walkToCampus.first, walkToCampus.last],
      ),
    ];

    return route_model.Route(
      id: 'example-route',
      startLocation: 'LRT-1 Monumento Station',
      endLocation: 'Our Lady of Fatima University',
      shortDescription:
          'Jeepney up MacArthur Highway from Monumento to Fatima University '
          'in Valenzuela.',
      steps: steps,
      startLat: pathPoints.first.latitude,
      startLng: pathPoints.first.longitude,
      endLat: pathPoints.last.latitude,
      endLng: pathPoints.last.longitude,
      pathPoints: pathPoints,
      stepBoundaries: [jeepStart, jeepEnd, pathPoints.length - 1],
      eta: '20',
      price: '₱13',
      schedule: '5AM-11PM daily',
      audienceTags: const ['Student'],
    );
  }
}

class TutorialStep {
  final String title;
  final String description;
  final String targetKey;
  final String? animationAsset;
  final Offset? customPosition;
  final Size? customSize;

  TutorialStep({
    required this.title,
    required this.description,
    required this.targetKey,
    this.animationAsset,
    this.customPosition,
    this.customSize,
  });
}
