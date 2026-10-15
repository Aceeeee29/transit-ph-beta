import 'package:flutter/material.dart';

import '../models/ors_route_result.dart';
import '../models/place.dart';
import '../models/route.dart' as route_model;

/// A route shown in the Map tab: a community route or a generated one.
class MapTabRoute {
  /// Exactly one of these is set.
  final route_model.Route? route;
  final OrsRouteResult? generated;

  final String originName;
  final String destinationName;
  final bool enableRouteIntegrity;
  final bool showDownloadButton;

  /// Distinguishes two openings of the same route, so the view restarts.
  final int serial;

  /// Where back goes after the route closes, e.g. the search it was
  /// picked from; null means the map.
  final void Function(BuildContext context)? onBack;

  const MapTabRoute._({
    this.route,
    this.generated,
    required this.originName,
    required this.destinationName,
    required this.enableRouteIntegrity,
    required this.showDownloadButton,
    required this.serial,
    this.onBack,
  });
}

/// State the Map tab's views share: the route on screen (if any), and the
/// place pins' category filter and visibility, which stay the same whether
/// you browse, contribute or follow.
class MapTabController extends ChangeNotifier {
  MapTabController._();
  static final MapTabController instance = MapTabController._();

  MapTabRoute? _current;
  MapTabRoute? get current => _current;
  int _serial = 0;

  /// The page that hosts the Map tab; opening a route pops back to it.
  Route<dynamic>? hostRoute;

  /// The highlighted place categories (the chips): their pins show at
  /// every zoom, the rest only from street level. The map opens with none.
  final ValueNotifier<Set<PlaceCategory>> placeCategories = ValueNotifier(
    const {},
  );
  final ValueNotifier<bool> showPins = ValueNotifier(true);

  void toggleCategory(PlaceCategory category) {
    final next = Set<PlaceCategory>.from(placeCategories.value);
    if (!next.remove(category)) next.add(category);
    placeCategories.value = next;
  }

  /// "All": highlights every category, or clears them when all already are.
  void toggleAllCategories() {
    placeCategories.value =
        placeCategories.value.length == PlaceCategory.values.length
            ? const {}
            : PlaceCategory.values.toSet();
  }

  void showRoute(
    route_model.Route route, {
    bool enableRouteIntegrity = true,
    bool showDownloadButton = true,
    void Function(BuildContext context)? onBack,
  }) {
    _current = MapTabRoute._(
      route: route,
      originName: route.startLocation,
      destinationName: route.endLocation,
      enableRouteIntegrity: enableRouteIntegrity,
      showDownloadButton: showDownloadButton,
      serial: ++_serial,
      onBack: onBack,
    );
    notifyListeners();
  }

  void showGenerated(
    OrsRouteResult result, {
    required String originName,
    required String destinationName,
    bool showDownloadButton = true,
    void Function(BuildContext context)? onBack,
  }) {
    _current = MapTabRoute._(
      generated: result,
      originName: originName,
      destinationName: destinationName,
      enableRouteIntegrity: false,
      showDownloadButton: showDownloadButton,
      serial: ++_serial,
      onBack: onBack,
    );
    notifyListeners();
  }

  /// Back to browsing. A route being followed keeps running.
  void close() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// The route view's back: closes the route, then returns to where it was
  /// opened from (e.g. the search options) when that was recorded.
  void back(BuildContext context) {
    final onBack = _current?.onBack;
    close();
    onBack?.call(context);
  }

  /// Closes pages pushed over the Map tab's host, so the route shows.
  void _returnToHost(BuildContext context) {
    final host = hostRoute;
    if (host == null || !host.isActive) return;
    Navigator.of(context).popUntil((route) => route == host);
  }

  /// Opens a community route in the Map tab from anywhere in the app.
  static void openRoute(
    BuildContext context,
    route_model.Route route, {
    bool enableRouteIntegrity = true,
    bool showDownloadButton = true,
    void Function(BuildContext context)? onBack,
  }) {
    instance._returnToHost(context);
    instance.showRoute(
      route,
      enableRouteIntegrity: enableRouteIntegrity,
      showDownloadButton: showDownloadButton,
      onBack: onBack,
    );
  }

  /// Opens a generated route in the Map tab from anywhere in the app.
  static void openGenerated(
    BuildContext context,
    OrsRouteResult result, {
    required String originName,
    required String destinationName,
    bool showDownloadButton = true,
    void Function(BuildContext context)? onBack,
  }) {
    instance._returnToHost(context);
    instance.showGenerated(
      result,
      originName: originName,
      destinationName: destinationName,
      showDownloadButton: showDownloadButton,
      onBack: onBack,
    );
  }
}
