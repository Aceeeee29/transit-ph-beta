/// Made-up guides credited for generated routes, so a suggestion reads like
/// a tip from a person instead of a machine.
class RouteGuide {
  RouteGuide._();

  static const names = ['Juan', 'Neneng', 'Erling Haaland', 'Alberto'];

  /// The guide for a trip; the same trip always gets the same one. [trip] is
  /// any text that identifies it (a simple hash, stable across app runs,
  /// unlike String.hashCode).
  static String nameFor(String trip) {
    var hash = 0;
    for (final unit in trip.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return names[hash % names.length];
  }
}
