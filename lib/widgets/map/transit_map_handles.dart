part of 'transit_map.dart';

/// A handle being dragged: where it shows, and how far from the finger.
class _Drag {
  final MapHandle handle;
  final Offset grab;

  _Drag(this.handle, this.grab);
}

int _handlesKey(List<MapHandle> handles) => Object.hashAll(
  handles.map((h) => Object.hash(h.id, h.point, h.image, h.label)),
);

/// Dragging [TransitMap.handles]. MapLibre draws them; a touch that lands
/// on one is taken by Flutter instead of the map (so the map doesn't pan),
/// and a copy of the handle follows the finger. Where each handle sits on
/// screen is looked up whenever the camera settles; while the map moves,
/// touches go to the map.
extension _TransitMapHandles on _TransitMapState {
  void _onHandlesChanged() {
    final key = _handlesKey(widget.handles);
    if (key == _handlesSeen) return;
    _handlesSeen = key;
    // Redrawn after a drop: the real handle is where the copy was.
    _dropTimer?.cancel();
    _drop = null;
    _handleSpots.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshHandleSpots());
  }

  Future<void> _refreshHandleSpots() async {
    final controller = _ml;
    final handles = widget.handles;
    if (controller == null || !_styleReady || handles.isEmpty) {
      _handleSpots.clear();
      return;
    }
    final key = _handlesKey(handles);
    final points = await controller.toScreenLocationBatch([
      for (final handle in handles) _toMl(handle.point),
    ]);
    if (!mounted || key != _handlesKey(widget.handles)) return;
    final ratio = _pixelRatio;
    _handleSpots
      ..clear()
      ..addAll({
        for (var i = 0; i < handles.length && i < points.length; i++)
          handles[i].id: Offset(
            points[i].x.toDouble() / ratio,
            points[i].y.toDouble() / ratio,
          ),
      });
  }

  /// The handle under [at], nearest first, with some room around it.
  MapHandle? _handleAt(Offset at) {
    if (_ml?.isCameraMoving ?? true) return null;
    MapHandle? best;
    var bestDistance = double.infinity;
    for (final handle in widget.handles) {
      final spot = _handleSpots[handle.id];
      if (spot == null) continue;
      final distance = (spot - at).distance;
      if (distance <= handle.size / 2 + 8 && distance < bestDistance) {
        best = handle;
        bestDistance = distance;
      }
    }
    return best;
  }

  Widget _buildHandleLayer() {
    final drag = _drag;
    final drop = _drop;
    final shown = drag?.handle ?? drop;
    return _HitWhere(
      hits: (at) => _drag != null || _handleAt(at) != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Taps on a handle stay off the map.
        onTap: () {},
        onPanDown: (d) => _pressed = _handleAt(d.localPosition),
        onPanStart: (d) {
          final handle = _pressed;
          if (handle != null) _startDrag(handle, d.localPosition);
        },
        onPanUpdate: (d) => _moveDrag(d.localPosition),
        onPanEnd: (_) => _endDrag(),
        onPanCancel: () {
          if (_drag != null) _update(() => _drag = null);
        },
        onLongPressStart: (d) {
          final handle = _handleAt(d.localPosition);
          if (handle == null) return;
          final onLongPress = handle.onLongPress;
          if (onLongPress != null) {
            onLongPress();
          } else {
            _startDrag(handle, d.localPosition);
          }
        },
        onLongPressMoveUpdate: (d) => _moveDrag(d.localPosition),
        onLongPressEnd: (_) => _endDrag(),
        child:
            shown == null
                ? const SizedBox.expand()
                : ValueListenableBuilder<Offset>(
                  valueListenable: _dragAt,
                  builder:
                      (context, at, _) => Stack(
                        children: [
                          Positioned(
                            left: at.dx,
                            top: at.dy,
                            child: IgnorePointer(
                              child: FractionalTranslation(
                                translation: const Offset(-0.5, -0.5),
                                child: Transform.scale(
                                  scale: drag != null ? 1.15 : 1,
                                  child: _handlePicture(shown),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                ),
      ),
    );
  }

  Widget _handlePicture(MapHandle handle) {
    final bytes = _TransitMapState._images?[handle.image];
    if (bytes == null) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.memory(bytes, scale: _pixelRatio, gaplessPlayback: true),
        if (handle.label != null)
          Text(
            handle.label!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  void _startDrag(MapHandle handle, Offset finger) {
    final spot = _handleSpots[handle.id] ?? finger;
    _dropTimer?.cancel();
    _dragAt.value = spot;
    _update(() {
      _drop = null;
      _drag = _Drag(handle, spot - finger);
    });
  }

  void _moveDrag(Offset finger) {
    final drag = _drag;
    if (drag == null) return;
    _dragAt.value = finger + drag.grab;
  }

  /// The copy stays where it was dropped until the handles are redrawn
  /// (snapping the line to roads can take a moment).
  Future<void> _endDrag() async {
    final drag = _drag;
    if (drag == null) return;
    final at = _dragAt.value;
    _update(() {
      _drag = null;
      _drop = drag.handle;
    });
    _dropTimer?.cancel();
    _dropTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _drop != null) _update(() => _drop = null);
    });
    final controller = _ml;
    if (controller == null) return;
    final ratio = _pixelRatio;
    final point = await controller.toLatLng(
      Point(at.dx * ratio, at.dy * ratio),
    );
    if (!mounted) return;
    drag.handle.onDragEnd(LatLng(point.latitude, point.longitude));
  }
}

/// Lets touches through to what's below except where [hits] says so.
class _HitWhere extends SingleChildRenderObjectWidget {
  final bool Function(Offset at) hits;

  const _HitWhere({required this.hits, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitWhere(hits);

  @override
  void updateRenderObject(BuildContext context, _RenderHitWhere renderObject) {
    renderObject.hits = hits;
  }
}

class _RenderHitWhere extends RenderProxyBox {
  bool Function(Offset at) hits;

  _RenderHitWhere(this.hits);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!hits(position)) return false;
    return super.hitTest(result, position: position);
  }
}
