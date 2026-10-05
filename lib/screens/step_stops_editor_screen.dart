import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/camanava_places.dart';
import '../models/route.dart' as route_model;
import '../services/route_follow_engine.dart';
import '../services/supabase_route_service.dart';
import '../widgets/translated_text.dart';

/// Edits the designated stops of one contributed step: tap the step's line
/// to add a stop, tap a stop to rename it or change pickup/drop-off, or pull
/// suggestions from transit data. Pops with the edited stops in order along
/// the line, or null when cancelled.
class StepStopsEditorScreen extends StatefulWidget {
  final String mode;
  final Color color;
  final List<LatLng> path;
  final List<route_model.RouteStop> initialStops;

  const StepStopsEditorScreen({
    super.key,
    required this.mode,
    required this.color,
    required this.path,
    required this.initialStops,
  });

  @override
  State<StepStopsEditorScreen> createState() => _StepStopsEditorScreenState();
}

class _StepStopsEditorScreenState extends State<StepStopsEditorScreen> {
  /// A tap this close to the line adds a stop there (snapped onto it).
  static const _tapToLineMeters = 60.0;

  /// A new stop this close to an existing one is treated as the same stop.
  static const _sameStopMeters = 30.0;

  static const _distance = Distance();

  late final RouteFollowEngine _line = RouteFollowEngine(widget.path);
  late List<route_model.RouteStop> _stops = _sorted(widget.initialStops);
  bool _isSuggesting = false;

  double _alongOf(route_model.RouteStop stop) =>
      _line.nearestInRange(stop.point, 0, _line.totalMeters)?.along ?? 0;

  List<route_model.RouteStop> _sorted(List<route_model.RouteStop> stops) =>
      [...stops]..sort((a, b) => _alongOf(a).compareTo(_alongOf(b)));

  bool _isNearExisting(LatLng point) => _stops.any(
    (s) => _distance.as(LengthUnit.Meter, s.point, point) < _sameStopMeters,
  );

  void _onMapTap(TapPosition _, LatLng tapped) {
    final match = _line.nearestInRange(tapped, 0, _line.totalMeters);
    if (match == null || match.distance > _tapToLineMeters) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText('Tap on or near the line to add a stop.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_isNearExisting(match.point)) return;
    final stop = route_model.RouteStop(
      lat: match.point.latitude,
      lng: match.point.longitude,
      name:
          nearestCamanavaPlaceName(match.point, maxMeters: 150) ??
          'Stop ${_stops.length + 1}',
    );
    setState(() => _stops = _sorted([..._stops, stop]));
    _editStop(stop);
  }

  Future<void> _editStop(route_model.RouteStop stop) async {
    final result = await showModalBottomSheet<_StopEdit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StopEditSheet(stop: stop),
    );
    if (!mounted || result == null) return;
    setState(() {
      final index = _stops.indexOf(stop);
      if (index < 0) return;
      if (result.delete) {
        _stops = [..._stops]..removeAt(index);
      } else {
        _stops = [..._stops]..[index] = result.stop!;
      }
    });
  }

  Future<void> _suggestStops() async {
    setState(() => _isSuggesting = true);
    List<({String name, LatLng point, double alongMeters})> found;
    try {
      found = await SupabaseRouteService.findStopsAlongPath(widget.path);
    } catch (_) {
      found = const [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText(
              'Could not load transit stops. Check your connection.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
    if (!mounted) return;
    final fresh = found.where((f) => !_isNearExisting(f.point)).toList();
    if (fresh.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(
            'No other known transit stops along this line.',
          ),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SuggestionsSheet(names: [for (final f in fresh) f.name]),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() {
      _stops = _sorted([
        ..._stops,
        for (final i in picked)
          route_model.RouteStop(
            lat: fresh[i].point.latitude,
            lng: fresh[i].point.longitude,
            name: fresh[i].name,
          ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bounds = LatLngBounds.fromPoints(widget.path);
    return Scaffold(
      appBar: AppBar(
        title: TranslatedText('${widget.mode} stops'),
        actions: [
          TextButton.icon(
            onPressed: _isSuggesting ? null : _suggestStops,
            icon:
                _isSuggesting
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const TranslatedText('Suggest'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: widget.color.withValues(alpha: 0.08),
            child: const TranslatedText(
              'Tap the line to add a stop. Tap a stop to rename it or set '
              'whether passengers board or get off there.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(40),
                ),
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app.transitph_beta',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.path,
                      color: Colors.black,
                      strokeWidth: 8,
                    ),
                    Polyline(
                      points: widget.path,
                      color: widget.color,
                      strokeWidth: 6,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < _stops.length; i++)
                      Marker(
                        point: _stops[i].point,
                        width: 30,
                        height: 30,
                        child: GestureDetector(
                          onTap: () => _editStop(_stops[i]),
                          child: _StopDot(
                            number: i + 1,
                            color: widget.color,
                            stop: _stops[i],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TranslatedText(
                      _stops.isEmpty
                          ? 'No stops yet'
                          : '${_stops.length} stop(s)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_stops),
                    child: const TranslatedText('Save stops'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopDot extends StatelessWidget {
  final int number;
  final Color color;
  final route_model.RouteStop stop;

  const _StopDot({
    required this.number,
    required this.color,
    required this.stop,
  });

  @override
  Widget build(BuildContext context) {
    // Grey border: a stop where passengers can't board, only get off (or
    // the reverse) — still shown, just marked as restricted.
    final restricted = !stop.pickup || !stop.dropoff;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: restricted ? Colors.grey.shade500 : color,
          width: 3,
        ),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StopEdit {
  final route_model.RouteStop? stop;
  final bool delete;

  const _StopEdit.update(this.stop) : delete = false;
  const _StopEdit.delete() : stop = null, delete = true;
}

class _StopEditSheet extends StatefulWidget {
  final route_model.RouteStop stop;

  const _StopEditSheet({required this.stop});

  @override
  State<_StopEditSheet> createState() => _StopEditSheetState();
}

class _StopEditSheetState extends State<_StopEditSheet> {
  late final _name = TextEditingController(text: widget.stop.name);
  late bool _pickup = widget.stop.pickup;
  late bool _dropoff = widget.stop.dropoff;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Stop name'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const TranslatedText('Passengers can board here'),
            value: _pickup,
            onChanged: (v) => setState(() => _pickup = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const TranslatedText('Passengers can get off here'),
            value: _dropoff,
            onChanged: (v) => setState(() => _dropoff = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed:
                    () => Navigator.of(context).pop(const _StopEdit.delete()),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const TranslatedText(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  final name = _name.text.trim();
                  Navigator.of(context).pop(
                    _StopEdit.update(
                      widget.stop.copyWith(
                        name: name.isEmpty ? widget.stop.name : name,
                        pickup: _pickup,
                        dropoff: _dropoff,
                      ),
                    ),
                  );
                },
                child: const TranslatedText('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionsSheet extends StatefulWidget {
  final List<String> names;

  const _SuggestionsSheet({required this.names});

  @override
  State<_SuggestionsSheet> createState() => _SuggestionsSheetState();
}

class _SuggestionsSheetState extends State<_SuggestionsSheet> {
  late final Set<int> _picked = {
    for (var i = 0; i < widget.names.length; i++) i,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: TranslatedText(
                'Known transit stops along this line',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TranslatedText(
                'Keep only the ones this vehicle actually stops at.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < widget.names.length; i++)
                    CheckboxListTile(
                      dense: true,
                      value: _picked.contains(i),
                      title: Text(widget.names[i]),
                      onChanged:
                          (v) => setState(
                            () => v == true ? _picked.add(i) : _picked.remove(i),
                          ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      () => Navigator.of(context).pop(
                        _picked.toList()..sort(),
                      ),
                  child: const TranslatedText('Add selected stops'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
