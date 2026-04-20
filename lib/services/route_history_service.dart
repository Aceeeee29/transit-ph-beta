import 'package:latlong2/latlong.dart';
import '../models/route.dart' as route_model;

// Class to represent a state in the route history
class RouteHistoryState {
  final List<LatLng> pathPoints;
  final List<route_model.Step> steps;
  final List<int> stepBoundaries;
  final String selectionMode;

  RouteHistoryState({
    required this.pathPoints,
    required this.steps,
    required this.stepBoundaries,
    required this.selectionMode,
  });
}

class RouteHistoryService {
  final List<RouteHistoryState> _history = [];
  int _currentIndex = -1;

  /// Add a new state to the history
  void addState(
    List<LatLng> pathPoints,
    List<route_model.Step> steps,
    List<int> stepBoundaries,
    String selectionMode,
  ) {
    // If we're not at the end of the history, remove all states after the
    // current one
    if (_currentIndex < _history.length - 1) {
      _history.removeRange(_currentIndex + 1, _history.length);
    }

    // Create a deep copy of the current state, preserving all Step fields
    final pathPointsCopy = List<LatLng>.from(pathPoints);
    final stepsCopy = List<route_model.Step>.from(
      steps.map(
        (step) => route_model.Step(
          mode: step.mode,
          instruction: step.instruction,
          details: step.details,
          is24_7: step.is24_7,
          startTime: step.startTime,
          endTime: step.endTime,
          actualFare: step.actualFare,
          alternateRouteSuggestion: step.alternateRouteSuggestion,
        ),
      ),
    );
    final stepBoundariesCopy = List<int>.from(stepBoundaries);

    // Add the new state to the history
    _history.add(
      RouteHistoryState(
        pathPoints: pathPointsCopy,
        steps: stepsCopy,
        stepBoundaries: stepBoundariesCopy,
        selectionMode: selectionMode,
      ),
    );

    _currentIndex = _history.length - 1;

    // Limit history size to prevent memory issues
    if (_history.length > 20) {
      _history.removeAt(0);
      _currentIndex--;
    }
  }

  /// Check if undo is available
  bool get canUndo => _currentIndex > 0;

  /// Check if redo is available
  bool get canRedo => _currentIndex < _history.length - 1;

  /// Undo the last action
  RouteHistoryState? undo() {
    if (!canUndo) return null;
    _currentIndex--;
    return _history[_currentIndex];
  }

  /// Redo the previously undone action
  RouteHistoryState? redo() {
    if (!canRedo) return null;
    _currentIndex++;
    return _history[_currentIndex];
  }

  /// Get the current state
  RouteHistoryState? getCurrentState() {
    if (_currentIndex < 0 || _history.isEmpty) return null;
    return _history[_currentIndex];
  }

  /// Clear the history
  void clear() {
    _history.clear();
    _currentIndex = -1;
  }
}