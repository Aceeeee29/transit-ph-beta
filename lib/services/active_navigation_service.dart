import 'package:flutter/foundation.dart';
import '../models/route.dart' as route_model;

/// Tracks whether the user has an in-progress "follow route" navigation
/// session, so it can survive leaving RouteMapScreen (e.g. via back) and be
/// resumed later from a persistent banner elsewhere in the app.
class ActiveNavigationService extends ChangeNotifier {
  ActiveNavigationService._();
  static final ActiveNavigationService instance = ActiveNavigationService._();

  route_model.Route? _route;
  bool _enableRouteIntegrity = true;
  bool _showDownloadButton = true;

  route_model.Route? get activeRoute => _route;
  bool get enableRouteIntegrity => _enableRouteIntegrity;
  bool get showDownloadButton => _showDownloadButton;
  bool get isActive => _route != null;

  void start(
    route_model.Route route, {
    bool enableRouteIntegrity = true,
    bool showDownloadButton = true,
  }) {
    _route = route;
    _enableRouteIntegrity = enableRouteIntegrity;
    _showDownloadButton = showDownloadButton;
    notifyListeners();
  }

  void stop() {
    if (_route == null) return;
    _route = null;
    notifyListeners();
  }
}
