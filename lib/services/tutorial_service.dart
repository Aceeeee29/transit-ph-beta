import 'package:flutter/material.dart';
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

  /// The contribute tutorial: one card per part of drawing a route, in the
  /// order it's done. [TutorialStep.image] holds a screenshot once added.
  static List<TutorialStep> getContributeTutorialSteps() {
    return const [
      TutorialStep(
        title: 'Set the start',
        description:
            'Pick the vehicle, then tap the map where riders begin. Search a '
            'place first to jump there.',
        icon: Icons.touch_app_rounded,
        image: 'assets/tutorial/contribute_1.jpg',
        focus: 0.35,
      ),
      TutorialStep(
        title: 'Draw the line',
        description:
            'Keep tapping along the road; the line follows the street. Undo '
            'takes back a point, and you can drag the dots to fix a turn.',
        icon: Icons.gesture_rounded,
        image: 'assets/tutorial/contribute_2.jpg',
        focus: 0,
      ),
      TutorialStep(
        title: 'Save the step',
        description:
            'Press Save step, then write what riders do ("Ride the jeep with '
            'the Monumento signboard") and add the fare, hours and stops.',
        icon: Icons.directions_bus_rounded,
        image: 'assets/tutorial/contribute_3.jpg',
        focus: -0.2,
      ),
      TutorialStep(
        title: 'Add the next ride',
        description:
            'Changing vehicles? Tap to start the next step where this one '
            'ended. When the whole trip is drawn, press Finish.',
        icon: Icons.alt_route_rounded,
        image: 'assets/tutorial/contribute_4.jpg',
        focus: 0,
      ),
      TutorialStep(
        title: 'Fill in Basic Info',
        description:
            'Type where the route starts and ends, like "SM Valenzuela" and '
            '"Monumento", then press Next to pick tags.',
        icon: Icons.edit_note_rounded,
        image: 'assets/tutorial/contribute_5.jpg',
        focus: 0.55,
      ),
      TutorialStep(
        title: 'Describe it and finish',
        description:
            'Add a short description, then press Finish Route. A moderator '
            'reviews new routes before they appear for everyone.',
        icon: Icons.send_rounded,
        image: 'assets/tutorial/contribute_6.jpg',
        focus: 0.8,
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

/// One card of a tutorial: a screenshot (or, until there is one, an icon),
/// a title and a line or two.
class TutorialStep {
  final String title;
  final String description;

  /// An asset path, e.g. 'assets/tutorial/contribute_1.png'.
  final String? image;

  /// Which part of a tall [image] the card zooms to: -1 the top, 0 the
  /// middle, 1 the bottom.
  final double focus;
  final IconData icon;

  const TutorialStep({
    required this.title,
    required this.description,
    this.image,
    this.focus = 0,
    this.icon = Icons.lightbulb_outline_rounded,
  });
}
