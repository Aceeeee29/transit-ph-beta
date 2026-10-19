import 'package:flutter/material.dart';

/// One color and icon per transport mode, shared by every route view
/// (rider, generated and find-a-way) so a jeepney looks the same in all.
class RouteModes {
  RouteModes._();

  static Color color(String? mode) {
    switch (mode) {
      case 'Walk':
        return Colors.green.shade600;
      case 'Jeepney':
        return Colors.blue.shade600;
      case 'Bus':
        return Colors.red.shade600;
      case 'Train':
        return Colors.purple.shade600;
      case 'Tricycle':
        return Colors.orange.shade600;
      case 'FX/Van':
        return Colors.amber.shade700;
      case 'Ferry':
        return Colors.lightBlue.shade600;
      default:
        return Colors.blue.shade600;
    }
  }

  static IconData icon(String? mode) {
    switch (mode) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Jeepney':
        return Icons.directions_bus_rounded;
      case 'Bus':
        return Icons.directions_bus_filled_rounded;
      case 'Train':
        return Icons.train_rounded;
      case 'Tricycle':
        return Icons.two_wheeler_rounded;
      case 'FX/Van':
        return Icons.airport_shuttle_rounded;
      case 'Ferry':
        return Icons.directions_boat_rounded;
      default:
        return Icons.directions_bus_rounded;
    }
  }
}
