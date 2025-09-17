class Route {
  final String id;
  final String startLocation;
  final String endLocation;
  final String shortDescription;
  final List<Step> steps;

  Route({
    required this.id,
    required this.startLocation,
    required this.endLocation,
    required this.shortDescription,
    required this.steps,
  });
}

class Step {
  final String mode;
  final String instruction;
  final String details;

  Step({
    required this.mode,
    required this.instruction,
    required this.details,
  });
}
