import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../services/follow_trip_simulator.dart';

/// Debug builds only: the button that opens [showFollowSimulatorSheet].
class FollowSimulatorButton extends StatelessWidget {
  final List<LatLng> path;

  const FollowSimulatorButton({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: FollowTripSimulator.instance.isRunning,
      builder:
          (context, running, _) => FloatingActionButton.small(
            heroTag: 'follow-simulator',
            tooltip: 'Simulate trip (debug)',
            backgroundColor: running ? Colors.deepPurple : Colors.white,
            onPressed:
                running
                    ? FollowTripSimulator.instance.stop
                    : () => showFollowSimulatorSheet(context, path),
            child: Icon(
              running ? Icons.stop_rounded : Icons.science_outlined,
              color: running ? Colors.white : Colors.deepPurple,
            ),
          ),
    );
  }
}

Future<void> showFollowSimulatorSheet(
  BuildContext context,
  List<LatLng> path,
) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => _SimulatorSheet(path: path),
  );
}

class _SimulatorSheet extends StatefulWidget {
  final List<LatLng> path;

  const _SimulatorSheet({required this.path});

  @override
  State<_SimulatorSheet> createState() => _SimulatorSheetState();
}

class _SimulatorSheetState extends State<_SimulatorSheet> {
  static const _speeds = {'Walk': 5.0, 'Jeepney': 20.0, 'Bus': 30.0};
  static const _timeScales = [1.0, 4.0, 10.0];

  String _speed = 'Jeepney';
  double _timeScale = 4;
  bool _startAway = false;
  bool _detour = false;
  bool _jitter = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Simulate trip (debug only)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              'Replaces GPS with a simulated trip along this route.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _speeds.entries)
                  ChoiceChip(
                    label: Text('${entry.key} ${entry.value.round()} km/h'),
                    selected: _speed == entry.key,
                    onSelected: (_) => setState(() => _speed = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final scale in _timeScales)
                  ChoiceChip(
                    label: Text('${scale.round()}x time'),
                    selected: _timeScale == scale,
                    onSelected: (_) => setState(() => _timeScale = scale),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Start 250 m away from the route'),
              value: _startAway,
              onChanged: (v) => setState(() => _startAway = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Leave the route partway (detour)'),
              subtitle: const Text(
                'Walk speed: reroute. Vehicle speed: "vehicle may be detouring".',
              ),
              value: _detour,
              onChanged: (v) => setState(() => _detour = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('GPS jitter (up to 8 m)'),
              value: _jitter,
              onChanged: (v) => setState(() => _jitter = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start simulation'),
                onPressed: () {
                  FollowTripSimulator.instance.start(
                    path: widget.path,
                    speedKmh: _speeds[_speed]!,
                    timeScale: _timeScale,
                    startAway: _startAway,
                    detour: _detour,
                    jitterMeters: _jitter ? 8 : 0,
                  );
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
