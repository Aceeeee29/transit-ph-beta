import 'dart:async';

import 'package:flutter/material.dart';

import '../models/location_search_result.dart';
import '../models/route.dart' as route_model;
import '../services/place_search_service.dart';
import '../theme/app_colors.dart';
import '../widgets/search/route_option_card.dart';
import '../widgets/translated_text.dart';

/// What was picked in [MapSearchScreen].
sealed class MapSearchResult {
  const MapSearchResult();
}

/// Show this place on the map.
class MapSearchPlace extends MapSearchResult {
  final LocationSearchResult place;
  const MapSearchPlace(this.place);
}

/// Open this community route.
class MapSearchRoute extends MapSearchResult {
  final route_model.Route route;
  const MapSearchRoute(this.route);
}

/// Plan a trip to whatever was typed.
class MapSearchDirections extends MapSearchResult {
  final String query;
  const MapSearchDirections(this.query);
}

/// The Map tab's search: places (our landmarks, then OpenStreetMap) and
/// community routes in one list, like Google Maps.
class MapSearchScreen extends StatefulWidget {
  final List<route_model.Route> routes;

  const MapSearchScreen({super.key, required this.routes});

  @override
  State<MapSearchScreen> createState() => _MapSearchScreenState();
}

class _MapSearchScreenState extends State<MapSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<LocationSearchResult> _places = [];
  bool _loadingPlaces = false;

  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;

  String get _query => _controller.text.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _places = [];
        _loadingPlaces = false;
      });
      return;
    }
    setState(() => _loadingPlaces = true);
    // Nominatim allows about one request per second.
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final found = await PlaceSearchService.suggest(query);
      if (!mounted || query != _query) return;
      setState(() {
        _places = found;
        _loadingPlaces = false;
      });
    });
  }

  List<route_model.Route> get _matchingRoutes {
    final q = _query.toLowerCase();
    if (q.length < 2) return const [];
    return widget.routes
        .where(
          (r) =>
              r.startLocation.toLowerCase().contains(q) ||
              r.endLocation.toLowerCase().contains(q) ||
              r.shortDescription.toLowerCase().contains(q),
        )
        .take(5)
        .toList();
  }

  void _pick(MapSearchResult result) => Navigator.of(context).pop(result);

  @override
  Widget build(BuildContext context) {
    final routes = _matchingRoutes;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back_rounded, color: _textPrimary),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: _textPrimary, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Search places or routes',
                        hintStyle: TextStyle(
                          color: _textSecondary,
                          fontSize: 16,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceAlt,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon:
                            _query.isEmpty
                                ? null
                                : IconButton(
                                  tooltip: 'Clear',
                                  onPressed: () {
                                    _controller.clear();
                                    _onChanged('');
                                  },
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                    color: _textSecondary,
                                  ),
                                ),
                      ),
                      onChanged: _onChanged,
                      onSubmitted: (_) {
                        // Enter goes to the best place, like a map app.
                        if (_places.isNotEmpty) {
                          _pick(MapSearchPlace(_places.first));
                        } else if (_query.isNotEmpty) {
                          _pick(MapSearchDirections(_query));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child:
                  _query.isEmpty
                      ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: TranslatedText(
                            'Find a place, a landmark or a community route.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _textSecondary),
                          ),
                        ),
                      )
                      : ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.directions_rounded,
                              color: AppColors.accent,
                            ),
                            title: Text('Directions to "$_query"'),
                            onTap: () => _pick(MapSearchDirections(_query)),
                          ),
                          _sectionTitle('Places'),
                          if (_loadingPlaces && _places.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          else if (_places.isEmpty)
                            _emptyNote(
                              _query.length < 3
                                  ? 'Keep typing to find places.'
                                  : 'No places found.',
                            ),
                          for (final place in _places)
                            ListTile(
                              leading: Icon(
                                PlaceSearchService.landmarkAt(
                                          place.latitude,
                                          place.longitude,
                                        ) !=
                                        null
                                    ? Icons.star_outline_rounded
                                    : Icons.place_outlined,
                                color: _textSecondary,
                              ),
                              title: Text(
                                place.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _pick(MapSearchPlace(place)),
                            ),
                          if (routes.isNotEmpty) ...[
                            _sectionTitle('Community routes'),
                            for (final route in routes)
                              RouteOptionRow(
                                headline:
                                    '${route.startLocation} → ${route.endLocation}',
                                details: route.shortDescription,
                                modes: collapseModes(
                                  route.steps.map((s) => s.mode),
                                ),
                                onTap: () => _pick(MapSearchRoute(route)),
                              ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: TranslatedText(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: _textSecondary,
      ),
    ),
  );

  Widget _emptyNote(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: TranslatedText(
      text,
      style: TextStyle(fontSize: 13, color: _textSecondary),
    ),
  );
}
