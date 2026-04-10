import 'package:flutter/material.dart';

import '../models/route.dart' as route_model;
import '../repositories/offline_route_repository.dart';
import '../repositories/route_cache_repository.dart';
import '../services/offline_tile_service.dart';
import 'ors_route_map_screen.dart';
import 'route_map_screen.dart';

class DownloadedRoutesScreen extends StatefulWidget {
  const DownloadedRoutesScreen({super.key});

  @override
  State<DownloadedRoutesScreen> createState() => _DownloadedRoutesScreenState();
}

class _DownloadedRoutesScreenState extends State<DownloadedRoutesScreen> {
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  late Future<List<route_model.Route>> _routesFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _routesFuture = _loadAllOfflineRoutes();
  }

  Future<List<route_model.Route>> _loadAllOfflineRoutes() async {
    final loaded = await Future.wait([
      OfflineRouteRepository.getDownloadedRoutes(),
      RouteCacheRepository.getCachedGeneratedRoutes(),
    ]);

    final merged = <String, route_model.Route>{};
    for (final route in loaded[0]) {
      merged[route.id] = route;
    }
    for (final route in loaded[1]) {
      merged[route.id] = route;
    }
    return merged.values.toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _routesFuture = _loadAllOfflineRoutes();
    });
    await _routesFuture;
  }

  Future<void> _openRoute(route_model.Route route) async {
    if (RouteCacheRepository.isGeneratedRouteId(route.id)) {
      final payload = await RouteCacheRepository.getCachedGeneratedRoutePayload(
        route.id,
      );
      if (!mounted) return;
      if (payload != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrsRouteMapScreen(
              result: payload.result,
              originName: payload.originName,
              destinationName: payload.destinationName,
              showDownloadButton: false,
            ),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteMapScreen(
          route: route,
          enableRouteIntegrity: false,
          showDownloadButton: false,
        ),
      ),
    );
  }

  Future<void> _deleteRoute(route_model.Route route) async {
    if (route.id.startsWith('generated_cache__')) {
      await RouteCacheRepository.deleteCachedGeneratedRoute(route.id);
    } else {
      await OfflineRouteRepository.deleteRoute(route.id);
    }
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloaded route deleted.')),
    );
  }

  Future<void> _confirmDeleteRoute(route_model.Route route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Downloaded Route'),
        content: const Text('Remove this route from offline storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteRoute(route);
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Downloaded Routes'),
        content: const Text(
          'This will remove all offline routes stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await Future.wait([
      OfflineRouteRepository.clearAllDownloadedRoutes(),
      RouteCacheRepository.clearAllLocalCache(),
      OfflineTileService.clearAllTiles(),
    ]);
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All downloaded routes deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 15,
              color: _textSecondary,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.download_for_offline_rounded,
                color: _accent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Downloaded Routes',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _confirmClearAll,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _border),
                ),
                child: const Icon(
                  Icons.delete_sweep_outlined,
                  size: 17,
                  color: _textSecondary,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: FutureBuilder<List<route_model.Route>>(
        future: _routesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  'Failed to load downloaded routes: ${snapshot.error}',
                  style: const TextStyle(color: _textPrimary),
                ),
              ),
            );
          }

          final routes = snapshot.data ?? const <route_model.Route>[];
          final filteredRoutes = routes.where((route) {
            final q = _searchQuery.trim().toLowerCase();
            if (q.isEmpty) return true;
            return route.startLocation.toLowerCase().contains(q) ||
                route.endLocation.toLowerCase().contains(q) ||
                route.shortDescription.toLowerCase().contains(q);
          }).toList();

          if (routes.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              color: _accent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 120),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.download_done_rounded,
                          size: 34,
                          color: _textSecondary,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No downloaded routes yet',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Open a route while online and tap Download.',
                          style: TextStyle(color: _textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: _accent,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border, width: 1.5),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    style: const TextStyle(color: _textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: _accent,
                        size: 19,
                      ),
                      hintText: 'Search downloaded routes...',
                      hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (filteredRoutes.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: const Text(
                      'No routes found for your search.',
                      style: TextStyle(color: _textSecondary),
                    ),
                  ),
                ...filteredRoutes.map((route) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        leading: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _border),
                          ),
                          child: const Icon(
                            Icons.download_done_rounded,
                            color: _accent,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          '${route.startLocation} to ${route.endLocation}',
                          style: const TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          route.shortDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _textSecondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => _confirmDeleteRoute(route),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: Colors.red.withOpacity(0.25),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 17,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chevron_right,
                              color: _textSecondary,
                            ),
                          ],
                        ),
                        onTap: () {
                          _openRoute(route);
                        },
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
