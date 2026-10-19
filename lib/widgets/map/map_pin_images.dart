import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/place.dart';
import '../map_tab/place_widgets.dart';

/// The pictures on the MapLibre map (MapLibre can't show widgets on the
/// map itself): the same neutral place pins as [PlacePin], route start and
/// end markers, the drawing map's handles, the red pin of a searched place
/// and the traveler's blue dot (the arrow is a 3D shape instead). Drawn at
/// the screen's [pixelRatio], so MapLibre shows them at their logical size.
class MapPinImages {
  MapPinImages._();

  static const _blue = Color(0xFF0B8FD6);

  /// The image name of a place pin.
  static String placePin(PlaceCategory category, {bool selected = false}) =>
      'tph-pin-${category.name}${selected ? '-selected' : ''}';

  static const foundPin = 'tph-found';
  static const userDot = 'tph-me';
  static const coordMark = 'tph-coord';

  /// A drawn route's start (green pin) and end (red flag).
  static const routeStart = 'tph-route-start';
  static const routeEnd = 'tph-route-end';

  /// A route view's end: a small red pin, smaller than the traveler's dot
  /// up close. (The start is a [MapDot].)
  static const tripEnd = 'tph-trip-end';

  /// A place searched on the drawing map.
  static const searched = 'tph-searched';

  /// The drawing map's handles: the route's stops (start green, end red,
  /// between blue, numbered by a label), a via point, and the "+" on each
  /// piece.
  static const handleStart = 'tph-handle-start';
  static const handleEnd = 'tph-handle-end';
  static const handleMiddle = 'tph-handle-middle';
  static const handleVia = 'tph-handle-via';
  static const handleInsert = 'tph-handle-insert';

  /// Every image by name.
  static Future<Map<String, Uint8List>> all(double pixelRatio) async {
    return {
      for (final category in PlaceCategory.values) ...{
        placePin(category): await _placePin(category, false, pixelRatio),
        placePin(category, selected: true): await _placePin(
          category,
          true,
          pixelRatio,
        ),
      },
      foundPin: await _icon(Icons.place, Colors.red, 44, pixelRatio),
      coordMark: await _icon(Icons.add, _blue, 40, pixelRatio),
      userDot: await _userDot(pixelRatio),
      routeStart: await _icon(Icons.location_on, Colors.green, 40, pixelRatio),
      routeEnd: await _icon(Icons.flag, Colors.red, 40, pixelRatio),
      tripEnd: await _icon(
        Icons.location_on,
        Colors.red.shade600,
        26,
        pixelRatio,
      ),
      searched: await _icon(Icons.my_location_rounded, _blue, 34, pixelRatio),
      handleStart: await _handle(Colors.green, 36, pixelRatio),
      handleEnd: await _handle(Colors.red, 36, pixelRatio),
      handleMiddle: await _handle(_blue, 36, pixelRatio),
      handleVia: await _handle(
        _blue.withValues(alpha: 0.9),
        22,
        pixelRatio,
        border: 2,
        icon: Icons.drag_indicator_rounded,
      ),
      handleInsert: await _insertHandle(pixelRatio),
    };
  }

  /// A drawing handle: a [color] dot with a white ring.
  static Future<Uint8List> _handle(
    Color color,
    double size,
    double pixelRatio, {
    double border = 2.4,
    IconData? icon,
  }) {
    const pad = 8.0;
    return _draw(size + pad * 2, pixelRatio, (canvas) {
      final center = Offset(size / 2 + pad, size / 2 + pad);
      _shadow(canvas, center + const Offset(0, 3), size / 2, 7);
      canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);
      canvas.drawCircle(center, size / 2 - border, Paint()..color = color);
      if (icon != null) _paintIcon(canvas, icon, Colors.white, 12, center);
    });
  }

  static Future<Uint8List> _insertHandle(double pixelRatio) {
    const size = 16.0, pad = 2.0;
    return _draw(size + pad * 2, pixelRatio, (canvas) {
      const center = Offset(size / 2 + pad, size / 2 + pad);
      canvas.drawCircle(
        center,
        size / 2,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        center,
        size / 2 - 0.8,
        Paint()
          ..color = _blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      _paintIcon(canvas, Icons.add_rounded, _blue, 11, center);
    });
  }

  static void _shadow(
    Canvas canvas,
    Offset center,
    double radius,
    double blur,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
  }

  static Future<Uint8List> _placePin(
    PlaceCategory category,
    bool selected,
    double pixelRatio,
  ) {
    final size = selected ? placePinSelectedSize : placePinSize;
    // Room around the dot for its glow.
    final pad = selected ? 10.0 : 5.0;
    return _draw(size + pad * 2, pixelRatio, (canvas) {
      final center = Offset(size / 2 + pad, size / 2 + pad);
      final radius = size / 2;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = placeNeutralColor.withValues(alpha: selected ? 0.6 : 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, selected ? 5 : 2.5),
      );
      canvas.drawCircle(center, radius, Paint()..color = placeNeutralColor);
      canvas.drawCircle(
        center,
        radius - (selected ? 1.25 : 0.75),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1.5,
      );
      _paintIcon(
        canvas,
        category.icon,
        Colors.white,
        selected ? 19 : 13,
        center,
      );
    });
  }

  static Future<Uint8List> _icon(
    IconData icon,
    Color color,
    double size,
    double pixelRatio,
  ) {
    return _draw(size, pixelRatio, (canvas) {
      _paintIcon(canvas, icon, color, size, Offset(size / 2, size / 2));
    });
  }

  /// The traveler: an 18 px blue dot in a white ring, like the old map's.
  static Future<Uint8List> _userDot(double pixelRatio) {
    const size = 18.0, pad = 6.0;
    return _draw(size + pad * 2, pixelRatio, (canvas) {
      const center = Offset(size / 2 + pad, size / 2 + pad);
      _shadow(canvas, center + const Offset(0, 1), size / 2, 4);
      canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);
      canvas.drawCircle(center, size / 2 - 3, Paint()..color = _blue);
    });
  }

  static void _paintIcon(
    Canvas canvas,
    IconData icon,
    Color color,
    double size,
    Offset center,
  ) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      ),
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  static Future<Uint8List> _draw(
    double logicalSize,
    double pixelRatio,
    void Function(Canvas canvas) paint,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    paint(canvas);
    final px = (logicalSize * pixelRatio).ceil();
    final image = await recorder.endRecording().toImage(px, px);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}
