import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// The traveler's location as a blue dot with an accuracy circle and, while
/// moving, a direction cone. Instead of jumping to every GPS fix, the dot
/// glides between fixes and ignores the small wander of a standing device.
class UserLocationLayer extends StatefulWidget {
  final LatLng? position;
  final double accuracyMeters;
  final double headingDegrees;
  final double speedMps;

  const UserLocationLayer({
    super.key,
    required this.position,
    required this.accuracyMeters,
    required this.headingDegrees,
    required this.speedMps,
  });

  /// Below this the device is treated as standing still.
  static const stillSpeedMps = 0.6;

  /// The direction cone only shows while actually moving; when still, GPS
  /// heading is noise.
  static const headingSpeedMps = 1.0;

  @override
  State<UserLocationLayer> createState() => _UserLocationLayerState();
}

class _UserLocationLayerState extends State<UserLocationLayer>
    with SingleTickerProviderStateMixin {
  /// About one GPS interval, linear: each glide ends as the next fix
  /// arrives, so the dot moves continuously instead of hop-and-stop.
  static const _glide = Duration(milliseconds: 900);

  /// Further than this is a real jump (e.g. resuming after a gap): no glide.
  static const _snapMeters = 150.0;
  static const _distance = Distance();
  static const _blue = Color(0xFF2E7CF6);

  late final AnimationController _controller;
  LatLng? _from;
  LatLng? _to;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _glide)
      ..addListener(() => setState(() {}));
    _to = widget.position;
  }

  @override
  void didUpdateWidget(UserLocationLayer old) {
    super.didUpdateWidget(old);
    final next = widget.position;
    if (next == null) {
      _to = null;
      return;
    }
    final shown = _shownPosition;
    if (shown == null) {
      _to = next;
      return;
    }
    final moved = _distance.as(LengthUnit.Meter, shown, next);
    if (moved == 0) return;

    // Standing still: GPS wanders a few metres between fixes; hold the dot
    // unless the fix moved further than its own accuracy suggests.
    final stillDeadband = math.max(4.0, widget.accuracyMeters * 0.5);
    if (widget.speedMps < UserLocationLayer.stillSpeedMps &&
        moved < stillDeadband) {
      return;
    }

    if (moved > _snapMeters) {
      _controller.stop();
      _from = null;
      _to = next;
      return;
    }
    _from = shown;
    _to = next;
    _controller.forward(from: 0);
  }

  LatLng? get _shownPosition {
    final to = _to;
    final from = _from;
    if (to == null) return null;
    if (from == null || !_controller.isAnimating) return to;
    final t = _controller.value;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = _shownPosition;
    if (point == null) return const SizedBox.shrink();
    final showHeading = widget.speedMps >= UserLocationLayer.headingSpeedMps;

    return Stack(
      children: [
        CircleLayer(
          circles: [
            CircleMarker(
              point: point,
              radius: widget.accuracyMeters.clamp(5.0, 60.0),
              useRadiusInMeter: true,
              color: _blue.withValues(alpha: 0.12),
              borderColor: _blue.withValues(alpha: 0.3),
              borderStrokeWidth: 1,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (showHeading)
                    Transform.rotate(
                      angle: widget.headingDegrees * math.pi / 180,
                      child: const CustomPaint(
                        size: Size(56, 56),
                        painter: _HeadingConePainter(_blue),
                      ),
                    ),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A soft wedge pointing up (north before rotation) from the dot's centre.
class _HeadingConePainter extends CustomPainter {
  final Color color;

  const _HeadingConePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    const halfAngle = 0.45;
    final path =
        Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(
            Rect.fromCircle(center: center, radius: radius),
            -math.pi / 2 - halfAngle,
            halfAngle * 2,
            false,
          )
          ..close();
    final paint =
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HeadingConePainter old) => old.color != color;
}
