import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:math' show Point;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../models/place.dart';
import '../../services/map_style_service.dart';
import '../../theme/app_colors.dart';
import 'map_pin_images.dart';

part 'transit_map_handles.dart';
part 'transit_map_layers.dart';

// ─── What goes on the map ───────────────────────────────────────────────────

enum MapLineStyle { solid, dotted, dashed }

/// A line, drawn over the lines before it in the list.
class MapLine {
  final List<LatLng> points;
  final Color color;
  final double width;
  final MapLineStyle style;

  const MapLine(
    this.points, {
    required this.color,
    required this.width,
    this.style = MapLineStyle.solid,
  });
}

/// A round marker (a stop, the next target), with an optional number.
class MapDot {
  final LatLng point;
  final double radius;
  final Color color;
  final Color strokeColor;
  final double strokeWidth;
  final String? label;

  /// Given an id, a tap on it goes to [TransitMap.onMarkerTap].
  final String? id;

  const MapDot(
    this.point, {
    required this.radius,
    this.color = Colors.white,
    required this.strokeColor,
    this.strokeWidth = 3,
    this.label,
    this.id,
  });
}

/// One of [MapPinImages]' pictures on the map.
class MapIcon {
  final LatLng point;
  final String image;

  /// Pins stand on their point; everything else is centered on it.
  final bool anchorBottom;
  final String? label;
  final String? id;

  const MapIcon(
    this.point,
    this.image, {
    this.anchorBottom = false,
    this.label,
    this.id,
  });
}

/// A marker the user can drag (the drawing map's route handles).
class MapHandle {
  final String id;
  final LatLng point;
  final String image;
  final String? label;

  /// Its size on screen, for how near a touch must land.
  final double size;
  final ValueChanged<LatLng> onDragEnd;

  /// Long-press instead of dragging; without it a long press starts a drag.
  final VoidCallback? onLongPress;

  const MapHandle({
    required this.id,
    required this.point,
    required this.image,
    required this.size,
    required this.onDragEnd,
    this.label,
    this.onLongPress,
  });
}

/// The place pins. Highlighted categories (the chips) show at every zoom,
/// smaller far out; the rest from street level. The open place shows even
/// with the pins off.
class MapPlaces {
  final List<Place> places;
  final Set<PlaceCategory> highlighted;
  final Place? selected;

  const MapPlaces({
    this.places = const [],
    this.highlighted = const {},
    this.selected,
  });
}

/// The traveler: an arrow lying on the map that points where they face, or
/// a dot while that isn't known. It glides from fix to fix instead of
/// jumping.
class MapUser {
  final LatLng position;
  final double accuracyMeters;

  /// Where they face, in degrees from north; null shows the dot.
  final double? headingDegrees;
  final double speedMps;

  const MapUser(
    this.position, {
    this.accuracyMeters = 0,
    this.headingDegrees,
    this.speedMps = 0,
  });

  /// Below this the device is treated as standing still.
  static const stillSpeedMps = 0.6;
}

/// Where the camera is. Zooms are the app's numbers (see [TransitMap]).
class TransitMapCamera {
  final LatLng center;
  final double zoom;
  final double bearing;
  final double tilt;

  const TransitMapCamera(
    this.center,
    this.zoom, {
    this.bearing = 0,
    this.tilt = 0,
  });
}

// ─── Camera ─────────────────────────────────────────────────────────────────

/// Moves a [TransitMap]'s camera. Calls made before the map is ready wait
/// for it.
class TransitMapController {
  /// MapLibre's tiles are twice the size of the old map's, so the same view
  /// is one zoom level lower there.
  static const zoomOffset = 1.0;

  _TransitMapState? _state;
  TransitMapCamera? _camera;
  Future<void> Function()? _pending;

  ml.MapLibreMapController? get _ml => _state?._ml;

  /// Where the camera last settled (or was last sent).
  TransitMapCamera? get camera => _camera;

  Future<void> moveTo(
    LatLng center, {
    double? zoom,
    double? bearing,
    double? tilt,
    Duration duration = const Duration(milliseconds: 600),
    bool linear = false,
  }) async {
    _followTarget = null;
    final controller = _ml;
    final known = _camera;
    _camera = TransitMapCamera(
      center,
      zoom ?? known?.zoom ?? 14,
      bearing: bearing ?? known?.bearing ?? 0,
      tilt: tilt ?? known?.tilt ?? 0,
    );
    if (controller == null || !(_state?._styleReady ?? false)) {
      _pending =
          () => moveTo(
            center,
            zoom: zoom,
            bearing: bearing,
            tilt: tilt,
            duration: Duration.zero,
          );
      return;
    }
    final state = _state!;
    final inside = state._insideCenter(
      center,
      (zoom ?? known?.zoom ?? 14) - zoomOffset,
    );
    await state._openLimitsForMove();
    final target = _toMl(inside);
    final ml.CameraUpdate update;
    if (bearing != null || tilt != null) {
      final camera = _camera!;
      update = ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: target,
          zoom: camera.zoom - zoomOffset,
          bearing: camera.bearing,
          tilt: camera.tilt,
        ),
      );
    } else if (zoom != null) {
      update = ml.CameraUpdate.newLatLngZoom(target, zoom - zoomOffset);
    } else {
      update = ml.CameraUpdate.newLatLng(target);
    }
    await _run(update, duration, linear);
  }

  /// Following the traveler: glides to [target] over [duration] at a
  /// constant speed, so back-to-back calls (one per GPS fix) blend into
  /// continuous motion. [turnTo] can turn the camera on the way.
  Future<void> follow(
    LatLng target, {
    required double zoom,
    required double bearing,
    required double tilt,
    Duration duration = const Duration(milliseconds: 900),
  }) async {
    final moving = moveTo(
      target,
      zoom: zoom,
      bearing: bearing,
      tilt: tilt,
      duration: duration,
      linear: true,
    );
    // After moveTo has started (it forgets the last follow).
    _followTarget = target;
    _followEnds = DateTime.now().add(duration);
    await moving;
  }

  /// Turns the camera to [bearing] while following, without breaking the
  /// glide to the last [follow] target: the same target, in the time left
  /// (a new camera move replaces the one under way).
  Future<void> turnTo(double bearing) async {
    final known = _camera;
    final target = _followTarget ?? known?.center;
    if (known == null || target == null) return;
    final left = _followEnds.difference(DateTime.now());
    const shortest = Duration(milliseconds: 250);
    final followTarget = _followTarget;
    final followEnds = _followEnds;
    final moving = moveTo(
      target,
      zoom: known.zoom,
      bearing: bearing,
      tilt: known.tilt,
      duration: left > shortest ? left : shortest,
      linear: true,
    );
    _followTarget = followTarget;
    _followEnds = followEnds;
    await moving;
  }

  LatLng? _followTarget;
  DateTime _followEnds = DateTime(0);

  /// Leans the camera to [tilt] degrees (0 is flat).
  Future<void> tiltTo(double tilt) async {
    final known = _camera;
    if (known != null) {
      _camera = TransitMapCamera(
        known.center,
        known.zoom,
        bearing: known.bearing,
        tilt: tilt,
      );
    }
    final controller = _ml;
    if (controller == null) return;
    await controller.animateCamera(
      ml.CameraUpdate.tiltTo(tilt),
      duration: const Duration(milliseconds: 500),
    );
  }

  /// Shows all of [points] inside [padding] (logical pixels), no closer
  /// than [maxZoom]; with [flat], north up and untilted.
  Future<void> fitPoints(
    List<LatLng> points, {
    EdgeInsets padding = const EdgeInsets.all(40),
    double maxZoom = 17,
    Duration duration = const Duration(milliseconds: 600),
    bool flat = false,
  }) async {
    if (points.isEmpty) return;
    final state = _state;
    final controller = _ml;
    if (state == null || controller == null || !state._styleReady) {
      _pending =
          () => fitPoints(
            points,
            padding: padding,
            maxZoom: maxZoom,
            duration: Duration.zero,
            flat: flat,
          );
      return;
    }
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    if (north - south < 1e-5 && east - west < 1e-5) {
      return moveTo(points.first, zoom: maxZoom, duration: duration);
    }
    await state._openLimitsForMove();
    if (flat) {
      // North up and flat first: bounds fitted under a tilt or turn land
      // off to one side.
      final camera = await controller.queryCameraPosition();
      if (camera != null && (camera.tilt > 0 || camera.bearing != 0)) {
        await controller.moveCamera(
          ml.CameraUpdate.newCameraPosition(
            ml.CameraPosition(target: camera.target, zoom: camera.zoom),
          ),
        );
      }
    }
    await _run(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(south, west),
          northeast: ml.LatLng(north, east),
        ),
        // Logical pixels: the plugin scales them to the screen itself.
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      ),
      duration,
      false,
    );
    final position = await controller.queryCameraPosition();
    if (position != null && position.zoom + zoomOffset > maxZoom) {
      await controller.moveCamera(ml.CameraUpdate.zoomTo(maxZoom - zoomOffset));
    }
    await state._onCameraIdle();
  }

  Future<void> _run(
    ml.CameraUpdate update,
    Duration duration,
    bool linear,
  ) async {
    final controller = _ml;
    if (controller == null) return;
    if (duration == Duration.zero) {
      await controller.moveCamera(update);
    } else if (linear) {
      await controller.easeCamera(
        update,
        duration: duration,
        interpolation: ml.CameraAnimationInterpolation.linear,
      );
    } else {
      await controller.animateCamera(update, duration: duration);
    }
  }

  /// The map came up: run what was asked before it did.
  Future<void> _onReady() async {
    final pending = _pending;
    _pending = null;
    await pending?.call();
  }
}

ml.LatLng _toMl(LatLng p) => ml.LatLng(p.latitude, p.longitude);

// ─── The map ────────────────────────────────────────────────────────────────

/// The app's map: the base map (clean, classic or night, from the phone's
/// own tile server) drawn by MapLibre, which pans and zooms smoothly and
/// can tilt into 3D, with the app's pins, lines and markers over it.
///
/// Zoom numbers everywhere in the app are the old map's (flutter_map's);
/// this widget converts ([TransitMapController.zoomOffset]).
class TransitMap extends StatefulWidget {
  final TransitMapController controller;
  final LatLng initialCenter;
  final double initialZoom;

  /// Shown whole when the map opens, instead of [initialCenter].
  final List<LatLng>? initialFit;
  final EdgeInsets initialFitPadding;

  final double minZoom;
  final double maxZoom;

  /// Where the camera's center may go.
  final ({LatLng southWest, LatLng northEast})? bounds;

  /// The view between [keepInsidePadding]'s edges stays within this area:
  /// zooming out stops once the area fills the view, and the map doesn't
  /// pan off it (a pan that ends outside glides back).
  final ({LatLng southWest, LatLng northEast})? keepInside;
  final EdgeInsets keepInsidePadding;

  /// Metro Manila, the area the maps keep to.
  static const metroManila = (
    southWest: LatLng(14.34, 120.91),
    northEast: LatLng(14.79, 121.14),
  );

  /// [area] grown to take in [points] too, with a little room around the
  /// ones outside it (a route that leaves Metro Manila, the traveler
  /// elsewhere).
  static ({LatLng southWest, LatLng northEast}) areaWith(
    ({LatLng southWest, LatLng northEast}) area,
    Iterable<LatLng?> points,
  ) {
    const room = 0.01;
    var south = area.southWest.latitude, north = area.northEast.latitude;
    var west = area.southWest.longitude, east = area.northEast.longitude;
    for (final p in points) {
      if (p == null) continue;
      south = math.min(south, p.latitude - room);
      north = math.max(north, p.latitude + room);
      west = math.min(west, p.longitude - room);
      east = math.max(east, p.longitude + room);
    }
    return (southWest: LatLng(south, west), northEast: LatLng(north, east));
  }

  final MapPlaces? places;
  final List<MapLine> lines;
  final List<MapDot> dots;
  final List<MapIcon> icons;
  final List<MapHandle> handles;
  final MapUser? user;

  /// A tap on the map itself (not on a pin, marker or handle).
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<Place>? onPlaceTap;
  final ValueChanged<String>? onMarkerTap;

  /// Where the traveler faces, as it changes (a smoothed compass): turns
  /// [user]'s arrow without rebuilding the screen. Overrides
  /// [MapUser.headingDegrees] when it has a value.
  final ValueListenable<double?>? userHeading;

  /// The user started panning, zooming or turning the map.
  final VoidCallback? onUserGesture;
  final ValueChanged<TransitMapCamera>? onCameraIdle;

  final bool rotateGestures;

  /// Logical pixels from the top right corner.
  final Point<double> compassMargin;

  /// Logical pixels from the bottom left corner.
  final Point<double> attributionMargin;

  const TransitMap({
    super.key,
    required this.controller,
    required this.initialCenter,
    this.initialZoom = 12,
    this.initialFit,
    this.initialFitPadding = const EdgeInsets.all(40),
    this.minZoom = 5,
    this.maxZoom = 18,
    this.bounds,
    this.keepInside,
    this.keepInsidePadding = EdgeInsets.zero,
    this.places,
    this.lines = const [],
    this.dots = const [],
    this.icons = const [],
    this.handles = const [],
    this.user,
    this.userHeading,
    this.onTap,
    this.onPlaceTap,
    this.onMarkerTap,
    this.onUserGesture,
    this.onCameraIdle,
    this.rotateGestures = true,
    this.compassMargin = const Point(16, 16),
    this.attributionMargin = const Point(8, 8),
  });

  @override
  State<TransitMap> createState() => _TransitMapState();
}

class _TransitMapState extends State<TransitMap>
    with SingleTickerProviderStateMixin {
  /// One style per look, shared by every map.
  static final _styles = <String, Future<String>>{};
  static Future<Map<String, Uint8List>>? _imageLoad;
  static Map<String, Uint8List>? _images;

  ml.MapLibreMapController? _ml;
  String? _styleKey;
  Future<String>? _style;
  bool _styleReady = false;
  bool _opened = false;

  /// What each overlay source last got, so unchanged ones aren't resent.
  final _sent = <String, int>{};
  Future<void> _sending = Future.value();
  bool _sendScheduled = false;

  // ─── Drag handles (transit_map_handles.dart) ──────────────────────────────
  _Drag? _drag;
  final _dragAt = ValueNotifier<Offset>(Offset.zero);

  /// Dropped, until the handles are redrawn.
  MapHandle? _drop;
  Timer? _dropTimer;
  MapHandle? _pressed;
  int? _handlesSeen;

  /// Each handle's spot on screen (logical pixels).
  final _handleSpots = <String, Offset>{};

  double get _pixelRatio => MediaQuery.devicePixelRatioOf(context);

  /// setState for the extension in the part file.
  void _update(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    // The map on a TextureView that Flutter draws in directly. MapLibre's
    // default SurfaceView can only be shown through a virtual display,
    // which held panning near 40 fps.
    ml.MapLibreMap.useHybridComposition = true;
    widget.controller._state = this;
    widget.controller._camera ??= TransitMapCamera(
      widget.initialCenter,
      widget.initialZoom,
    );
    _glide = AnimationController(vsync: this, duration: _glideTime)
      ..addListener(_onGlideTick);
    _glideTo = widget.user?.position;
    _handlesSeen = _handlesKey(widget.handles);
    widget.userHeading?.addListener(_onUserHeading);
  }

  @override
  void didUpdateWidget(TransitMap old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller._state == this) old.controller._state = null;
      widget.controller._state = this;
    }
    if (old.userHeading != widget.userHeading) {
      old.userHeading?.removeListener(_onUserHeading);
      widget.userHeading?.addListener(_onUserHeading);
    }
    _onUserChanged(old.user);
    _onHandlesChanged();
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    widget.userHeading?.removeListener(_onUserHeading);
    _glide.dispose();
    _dragAt.dispose();
    _dropTimer?.cancel();
    _userLater?.cancel();
    super.dispose();
  }

  /// Widget tests have no MapLibre (a native view) and no tile server: a
  /// blank map stands in.
  static final _inTests =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Widget build(BuildContext context) {
    if (_inTests) {
      return SizedBox.expand(child: ColoredBox(color: AppColors.bg));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewSize = constraints.biggest;
        return _buildStyled();
      },
    );
  }

  Widget _buildStyled() {
    final styles = MapStyleService.instance;
    return ListenableBuilder(
      listenable: styles.changes,
      builder: (context, _) {
        final look = styles.look.value;
        final night = styles.isDark.value;
        final key = '${look.name}-$night';
        if (key != _styleKey) {
          _styleKey = key;
          _styleReady = false;
          _sent.clear();
          _style =
              _styles[key] ??= styles.maplibreStyle(
                look: look,
                night: night,
                extraSources: _Layers.sources(),
                extraLayers: _Layers.layers(night: night),
              );
        }
        return FutureBuilder<String>(
          future: _style,
          builder: (context, snapshot) {
            final style = snapshot.data;
            if (style == null) {
              return SizedBox.expand(child: ColoredBox(color: AppColors.bg));
            }
            _scheduleSend();
            return Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerEnd,
              onPointerCancel: _onPointerEnd,
              child: Stack(
                children: [
                  Positioned.fill(child: _buildMap(style)),
                  if (widget.handles.isNotEmpty || _drag != null)
                    Positioned.fill(child: _buildHandleLayer()),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMap(String style) {
    final camera = widget.controller._camera;
    final bounds = widget.bounds;
    final insideMinZoom = _insideMinZoom;
    final centerLimits =
        _insideLimits ??
        (bounds == null
            ? null
            : ml.LatLngBounds(
              southwest: _toMl(bounds.southWest),
              northeast: _toMl(bounds.northEast),
            ));
    return ml.MapLibreMap(
      styleString: style,
      initialCameraPosition: ml.CameraPosition(
        target: _toMl(camera?.center ?? widget.initialCenter),
        zoom:
            (camera?.zoom ?? widget.initialZoom) -
            TransitMapController.zoomOffset,
        bearing: camera?.bearing ?? 0,
        tilt: camera?.tilt ?? 0,
      ),
      minMaxZoomPreference: ml.MinMaxZoomPreference(
        math.max(
          widget.minZoom - TransitMapController.zoomOffset,
          insideMinZoom ?? double.negativeInfinity,
        ),
        widget.maxZoom - TransitMapController.zoomOffset,
      ),
      cameraTargetBounds:
          centerLimits == null
              ? ml.CameraTargetBounds.unbounded
              : ml.CameraTargetBounds(centerLimits),
      rotateGesturesEnabled: widget.rotateGestures,
      compassEnabled: true,
      compassViewPosition: ml.CompassViewPosition.topRight,
      // Logical pixels: the plugin scales these itself.
      compassViewMargins: widget.compassMargin,
      attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: widget.attributionMargin,
      onMapCreated: (controller) {
        _ml = controller;
        // MapLibre holds back every request while the phone has no
        // network, even to our own tile server on 127.0.0.1, so a cold
        // start offline drew a blank map. All its data comes from that
        // server, which handles being offline itself.
        unawaited(controller.forceOnlineMode().catchError((_) {}));
      },
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: _onMapClick,
      onCameraIdle: _onCameraIdle,
      // Camera moves reach Dart only where the arrow needs them.
      trackCameraPosition: widget.userHeading != null,
      onCameraMove: _onCameraMove,
    );
  }

  Future<void> _onStyleLoaded() async {
    final controller = _ml;
    if (controller == null) return;
    final images =
        _images ??= await (_imageLoad ??= MapPinImages.all(_pixelRatio));
    for (final MapEntry(:key, :value) in images.entries) {
      await controller.addImage(key, value);
    }
    if (!mounted) return;
    _styleReady = true;
    _sent.clear();
    _sendUser(force: true);
    _scheduleSend();
    if (!_opened) {
      _opened = true;
      final fit = widget.initialFit;
      if (fit != null && fit.isNotEmpty) {
        await widget.controller.fitPoints(
          fit,
          padding: widget.initialFitPadding,
          duration: Duration.zero,
        );
      }
    }
    await widget.controller._onReady();
    await _onCameraIdle();
  }

  Future<void> _onCameraIdle() async {
    final position = await _ml?.queryCameraPosition();
    if (position == null || !mounted) return;
    final camera = TransitMapCamera(
      LatLng(position.target.latitude, position.target.longitude),
      position.zoom + TransitMapController.zoomOffset,
      bearing: position.bearing,
      tilt: position.tilt,
    );
    widget.controller._camera = camera;
    _liveZoom = position.zoom;
    widget.onCameraIdle?.call(camera);
    _refreshHandleSpots();
    _keepViewInside(position);
    // The arrow is sized in meters for the zoom it was drawn at.
    _sendUser(force: true);
  }

  // ─── Keeping the view inside an area ──────────────────────────────────────

  Size _viewSize = Size.zero;

  /// Where the center may go at the zoom the camera last settled at.
  ml.LatLngBounds? _insideLimits;

  /// The part of the map the area must fill: inside the padding.
  Size? get _insideView {
    if (widget.keepInside == null || _viewSize.isEmpty) return null;
    final view = widget.keepInsidePadding.deflateSize(_viewSize);
    return view.isEmpty ? null : view;
  }

  /// Mercator y in degrees, so it scales like longitude on the map.
  static double _mercatorY(double lat) =>
      math.log(math.tan(math.pi / 4 + lat * math.pi / 360)) * 180 / math.pi;

  static double _latitudeOf(double y) =>
      math.atan(_sinh(y * math.pi / 180)) * 180 / math.pi;

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;

  /// Degrees across [pixels] at MapLibre [zoom] (512-pixel tiles).
  static double _degreesAcross(double pixels, double zoom) =>
      pixels * 360 / (512 * math.pow(2, zoom));

  /// Lowest MapLibre zoom: [TransitMap.keepInside] fills the view across
  /// and top to bottom, so nothing outside it shows (its far ends are
  /// reached by panning).
  double? get _insideMinZoom {
    final area = widget.keepInside;
    final view = _insideView;
    if (area == null || view == null) return null;
    final lngSpan = area.northEast.longitude - area.southWest.longitude;
    final ySpan =
        _mercatorY(area.northEast.latitude) -
        _mercatorY(area.southWest.latitude);
    double fit(double pixels, double span) =>
        math.log(pixels * 360 / (512 * span)) / math.ln2;
    return math.max(fit(view.width, lngSpan), fit(view.height, ySpan));
  }

  /// Where the center may go at MapLibre [zoom] for the view to stay in
  /// the area; on an axis where the view is wider, the middle.
  ml.LatLngBounds? _centerLimitsAt(double zoom) {
    final area = widget.keepInside;
    final view = _insideView;
    if (area == null || view == null) return null;
    final halfLng = _degreesAcross(view.width / 2, zoom);
    final halfY = _degreesAcross(view.height / 2, zoom);
    var west = area.southWest.longitude + halfLng;
    var east = area.northEast.longitude - halfLng;
    if (west > east) west = east = (west + east) / 2;
    var south = _mercatorY(area.southWest.latitude) + halfY;
    var north = _mercatorY(area.northEast.latitude) - halfY;
    if (south > north) south = north = (south + north) / 2;
    return ml.LatLngBounds(
      southwest: ml.LatLng(_latitudeOf(south), west),
      northeast: ml.LatLng(_latitudeOf(north), east),
    );
  }

  /// Once the camera settles: back inside if the view ended up past the
  /// area (zooming out widens it), then the center's limits for this zoom.
  void _keepViewInside(ml.CameraPosition position) {
    final limits = _centerLimitsAt(position.zoom);
    if (limits == null) return;
    final center = position.target;
    final lat = center.latitude.clamp(
      limits.southwest.latitude,
      limits.northeast.latitude,
    );
    final lng = center.longitude.clamp(
      limits.southwest.longitude,
      limits.northeast.longitude,
    );
    if ((lat - center.latitude).abs() > 1e-7 ||
        (lng - center.longitude).abs() > 1e-7) {
      // The next settle sets the limits.
      _ml?.animateCamera(
        ml.CameraUpdate.newLatLng(ml.LatLng(lat, lng)),
        duration: const Duration(milliseconds: 250),
      );
      return;
    }
    if (_sameBounds(_insideLimits, limits)) return;
    setState(() => _insideLimits = limits);
  }

  static bool _sameBounds(ml.LatLngBounds? a, ml.LatLngBounds? b) =>
      a != null &&
      b != null &&
      a.southwest == b.southwest &&
      a.northeast == b.northeast;

  /// Before a camera move by the app (a region, a search result): the
  /// limits are for the zoom the camera settled at, and would hold the
  /// move back (from all of Metro Manila, the center can't leave its
  /// middle). They open to the whole area for the move, and tighten again
  /// once it settles.
  Future<void> _openLimitsForMove() async {
    if (widget.keepInside == null) return;
    final open = _centerLimitsAt(
      widget.maxZoom - TransitMapController.zoomOffset,
    );
    if (open == null || _sameBounds(_insideLimits, open)) return;
    setState(() => _insideLimits = open);
    // The map gets the new limits during the frame, before the move.
    await WidgetsBinding.instance.endOfFrame;
  }

  /// [center] moved just enough for the view at MapLibre [zoom] to stay in
  /// [TransitMap.keepInside].
  LatLng _insideCenter(LatLng center, double zoom) {
    final limits = _centerLimitsAt(
      math.max(zoom, _insideMinZoom ?? double.negativeInfinity),
    );
    if (limits == null) return center;
    return LatLng(
      center.latitude.clamp(
        limits.southwest.latitude,
        limits.northeast.latitude,
      ),
      center.longitude.clamp(
        limits.southwest.longitude,
        limits.northeast.longitude,
      ),
    );
  }

  // ─── Taps and gestures ────────────────────────────────────────────────────

  /// A tap: a marker or pin under the finger (with some room around the
  /// small ones), else the map itself.
  Future<void> _onMapClick(Point<double> at, ml.LatLng coordinates) async {
    final controller = _ml;
    if (controller == null) return;
    Future<Object?> idAt(List<String> layers, double reach) async {
      final hits = await controller.queryRenderedFeaturesInRect(
        Rect.fromCenter(
          center: Offset(at.x, at.y),
          width: reach * _pixelRatio,
          height: reach * _pixelRatio,
        ),
        layers,
        null,
      );
      for (final hit in hits) {
        final id = ((hit as Map)['properties'] as Map?)?['id'];
        if (id != null) return id;
      }
      return null;
    }

    if (widget.onMarkerTap != null) {
      final id = await idAt([_Layers.iconLayer, _Layers.dotLayer], 16);
      if (!mounted) return;
      if (id is String) {
        widget.onMarkerTap!(id);
        return;
      }
    }
    final places = widget.places;
    if (places != null && widget.onPlaceTap != null) {
      final id = await idAt(_Layers.tappablePlaces, 20);
      if (!mounted) return;
      final place =
          places.selected?.id == id
              ? places.selected
              : places.places.where((p) => p.id == id).firstOrNull;
      if (place != null) {
        widget.onPlaceTap!(place);
        return;
      }
    }
    widget.onTap?.call(LatLng(coordinates.latitude, coordinates.longitude));
  }

  final _pointersDown = <int, Offset>{};
  bool _gestureReported = false;
  bool _touchOnHandle = false;

  void _onPointerDown(PointerDownEvent event) {
    if (_pointersDown.isEmpty) {
      _gestureReported = false;
      _touchOnHandle = _handleAt(event.localPosition) != null;
    }
    _pointersDown[event.pointer] = event.localPosition;
    if (_pointersDown.length > 1) _reportGesture();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final down = _pointersDown[event.pointer];
    if (down == null) return;
    if ((event.localPosition - down).distance > 8) _reportGesture();
  }

  void _onPointerEnd(PointerEvent event) {
    _pointersDown.remove(event.pointer);
  }

  /// Panning, pinching or turning the map, not dragging a handle.
  void _reportGesture() {
    if (_gestureReported || _touchOnHandle || _drag != null) return;
    _gestureReported = true;
    // Handles move on screen with the map: found again once it settles.
    _handleSpots.clear();
    widget.onUserGesture?.call();
  }

  // ─── Sending the overlays ─────────────────────────────────────────────────

  void _scheduleSend() {
    if (!_styleReady || _sendScheduled) return;
    _sendScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendScheduled = false;
      if (mounted) _sendChanged();
    });
  }

  /// Queued one after another, so a later update never lands first.
  void _send(String source, int key, Map<String, dynamic> Function() data) {
    if (_sent[source] == key) return;
    _sent[source] = key;
    final controller = _ml;
    if (controller == null) return;
    final json = data();
    _sending = _sending
        .then((_) => controller.setGeoJsonSource(source, json))
        .catchError((Object e) => debugPrint('[TransitMap] $source: $e'));
  }

  void _sendChanged() {
    if (!_styleReady) return;
    final places = widget.places;
    final shown = places?.places ?? const <Place>[];
    final highlighted = places?.highlighted ?? const <PlaceCategory>{};
    final selected = places?.selected;
    _send(
      _Layers.places,
      Object.hash(
        Object.hashAll(shown.map((p) => p.id)),
        Object.hashAllUnordered(highlighted),
        selected?.id,
      ),
      () => _Layers.collection([
        for (final place in shown)
          if (place.id != selected?.id)
            _Layers.placeFeature(
              place,
              highlighted: place.categories.any(highlighted.contains),
            ),
      ]),
    );
    _send(
      _Layers.selected,
      Object.hash(selected?.id, selected?.lat, selected?.lng),
      () => _Layers.collection([
        if (selected != null)
          _Layers.placeFeature(selected, highlighted: true, selected: true),
      ]),
    );
    _send(
      _Layers.lines,
      Object.hashAll(
        widget.lines.map(
          (l) =>
              Object.hash(l.color, l.width, l.style, Object.hashAll(l.points)),
        ),
      ),
      () => _Layers.lineFeatures(widget.lines),
    );
    _send(
      _Layers.dots,
      Object.hashAll(
        widget.dots.map(
          (d) => Object.hash(
            d.point,
            d.radius,
            d.color,
            d.strokeColor,
            d.strokeWidth,
            d.label,
            d.id,
          ),
        ),
      ),
      () => _Layers.dotFeatures(widget.dots),
    );
    _send(
      _Layers.icons,
      Object.hashAll(
        widget.icons.map(
          (i) => Object.hash(i.point, i.image, i.anchorBottom, i.label, i.id),
        ),
      ),
      () => _Layers.iconFeatures(widget.icons),
    );
    final hidden = _drag?.handle.id ?? _drop?.id;
    _send(
      _Layers.handles,
      Object.hash(_handlesKey(widget.handles), hidden),
      () => _Layers.handleFeatures(widget.handles, hiddenId: hidden),
    );
  }

  // ─── The traveler's dot ───────────────────────────────────────────────────

  /// About one GPS interval, linear: each glide ends as the next fix
  /// arrives, so the dot moves continuously instead of hop-and-stop.
  static const _glideTime = Duration(milliseconds: 900);

  /// Further than this is a real jump (e.g. resuming after a gap): no glide.
  static const _snapMeters = 150.0;
  static const _distance = Distance();

  late final AnimationController _glide;
  LatLng? _glideFrom;
  LatLng? _glideTo;
  DateTime _userSentAt = DateTime(0);
  bool _userSending = false;
  bool _userResend = false;
  Timer? _userLater;

  void _onUserHeading() => _sendUser();

  /// MapLibre zoom as the camera moves (screens with an arrow only), and
  /// the zoom the arrow was last drawn for.
  double? _liveZoom;
  double? _arrowZoom;

  /// The arrow is built in meters: while zooming it's redrawn as it goes,
  /// so it doesn't swell up (or shrink away) until the zoom settles.
  void _onCameraMove(ml.CameraPosition position) {
    _liveZoom = position.zoom;
    final drawn = _arrowZoom;
    if (drawn != null && (position.zoom - drawn).abs() > 0.03) _sendUser();
  }

  LatLng? get _userShown {
    final to = _glideTo;
    final from = _glideFrom;
    if (to == null) return null;
    if (from == null || !_glide.isAnimating) return to;
    final t = _glide.value;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  void _onUserChanged(MapUser? old) {
    final user = widget.user;
    final next = user?.position;
    if (next == null) {
      _glide.stop();
      _glideFrom = null;
      _glideTo = null;
      _sendUser(force: true);
      return;
    }
    final shown = _userShown;
    if (shown == null) {
      _glideTo = next;
      _sendUser(force: true);
      return;
    }
    final moved = _distance.as(LengthUnit.Meter, shown, next);
    if (moved == 0) {
      // Same spot; the heading or accuracy may still have changed.
      if (old?.headingDegrees != user!.headingDegrees ||
          old?.accuracyMeters != user.accuracyMeters ||
          old?.speedMps != user.speedMps) {
        _sendUser(force: true);
      }
      return;
    }
    // Standing still: GPS wanders a few metres between fixes; hold the dot
    // unless the fix moved further than its own accuracy suggests.
    final stillDeadband = math.max(4.0, user!.accuracyMeters * 0.5);
    if (user.speedMps < MapUser.stillSpeedMps && moved < stillDeadband) {
      return;
    }
    if (moved > _snapMeters) {
      _glide.stop();
      _glideFrom = null;
      _glideTo = next;
      _sendUser(force: true);
      return;
    }
    _glideFrom = shown;
    _glideTo = next;
    _glide.forward(from: 0);
  }

  void _onGlideTick() {
    _sendUser(force: _glide.isCompleted);
  }

  /// About 30 times a second while gliding: each is a message to the map.
  /// One at a time; one asked for meanwhile goes when it's done, with the
  /// dot where it is by then.
  void _sendUser({bool force = false}) {
    final controller = _ml;
    if (controller == null || !_styleReady) return;
    if (_userSending) {
      _userResend = true;
      return;
    }
    final now = DateTime.now();
    final wait = 33 - now.difference(_userSentAt).inMilliseconds;
    if (!force && wait > 0) {
      // Too soon: the latest goes a moment later, so the last turn of
      // the arrow isn't dropped.
      _userLater ??= Timer(Duration(milliseconds: wait), () {
        _userLater = null;
        if (mounted) _sendUser(force: true);
      });
      return;
    }
    _userLater?.cancel();
    _userLater = null;
    _userSentAt = now;
    final user = widget.user;
    final at = _userShown;
    final zoom =
        _liveZoom ??
        (widget.controller._camera?.zoom ?? 15) -
            TransitMapController.zoomOffset;
    _arrowZoom = zoom;
    final json =
        user == null || at == null
            ? _Layers.collection(const [])
            : _Layers.userFeatures(
              at,
              accuracyMeters: user.accuracyMeters,
              headingDegrees: widget.userHeading?.value ?? user.headingDegrees,
              zoom: zoom,
            );
    _userSending = true;
    controller
        .setGeoJsonSource(_Layers.user, json)
        .catchError((Object e) => debugPrint('[TransitMap] user: $e'))
        .whenComplete(() {
          _userSending = false;
          if (_userResend && mounted) {
            _userResend = false;
            _sendUser(force: true);
          }
        });
  }
}
