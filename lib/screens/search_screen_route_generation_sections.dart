part of 'search_screen.dart';

extension _SearchScreenRouteGenerationSections on _SearchScreenState {
  Future<void> _fetchOrsRouteSection() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoadingOrs = true;
      _orsError = false;
      _orsErrorMessage = '';
      _orsResult = null;
      _lastOrsQuery = query;
    });

    try {
      LatLng origin;
      String originName;

      if (_useCurrentLocation) {
        final position = await LocationService.getCurrentPosition();
        if (position == null) {
          setState(() {
            _isLoadingOrs = false;
            _orsError = true;
            _orsErrorMessage =
                'Could not get your current location. Check location permissions.';
          });
          return;
        }
        origin = LatLng(position.latitude, position.longitude);
        originName =
            await LocationService.getAddressFromCoordinates(
              position.latitude,
              position.longitude,
            ) ??
            'Current Location';
      } else {
        final originText = _originController.text.trim();
        if (originText.isEmpty) {
          setState(() {
            _isLoadingOrs = false;
            _orsError = true;
            _orsErrorMessage = 'Please enter a starting point.';
          });
          return;
        }
        final originLatLng = await _geocodePhilippines(originText);
        if (originLatLng == null) {
          setState(() {
            _isLoadingOrs = false;
            _orsError = true;
            _orsErrorMessage =
                'Could not find "$originText". Try a more specific address.';
          });
          return;
        }
        origin = originLatLng;
        originName = originText;
      }

      final destLatLng = await _geocodePhilippines(query);
      if (destLatLng == null) {
        setState(() {
          _isLoadingOrs = false;
          _orsError = true;
          _orsErrorMessage = 'Could not find "$query". Try a more specific name.';
        });
        return;
      }

      List<DijkstraRouteAlternative> alternatives = [];
      var fallbackAlternatives = <int, OrsRouteResult>{};
      var labelsByIndex = <int, String>{};
      try {
        final pools = await Future.wait([
          RoutingService.getRouteAlternatives(
            origin: origin,
            destination: destLatLng,
            optimization: 'balanced',
            maxAlternatives: 8,
          ),
          RoutingService.getRouteAlternatives(
            origin: origin,
            destination: destLatLng,
            optimization: 'fastest',
            maxAlternatives: 8,
          ),
          RoutingService.getRouteAlternatives(
            origin: origin,
            destination: destLatLng,
            optimization: 'budget',
            maxAlternatives: 8,
          ),
        ]);

        final merged = <DijkstraRouteAlternative>[];
        final mergedSeen = <String>{};
        for (final pool in pools) {
          for (final alt in pool) {
            final sig = _alternativeRouteSignature(alt);
            if (!mergedSeen.add(sig)) continue;
            merged.add(alt);
          }
        }

        final selected = <DijkstraRouteAlternative>[];
        final selectedSeen = <String>{};

        void addLabeled(String label, DijkstraRouteAlternative? alt) {
          if (alt == null) return;
          final sig = _alternativeRouteSignature(alt);

          final existingIndex = selected.indexWhere(
            (candidate) => _alternativeRouteSignature(candidate) == sig,
          );
          if (existingIndex >= 0) {
            final existingLabel = labelsByIndex[existingIndex] ?? '';
            if (existingLabel.isEmpty) {
              labelsByIndex[existingIndex] = label;
              return;
            }

            final parts =
                existingLabel
                    .split(' • ')
                    .where((part) => part.trim().isNotEmpty)
                    .toList();
            if (!parts.contains(label)) {
              parts.add(label);
              labelsByIndex[existingIndex] = parts.join(' • ');
            }
            return;
          }

          selectedSeen.add(sig);
          selected.add(alt);
          labelsByIndex[selected.length - 1] = label;
        }

        void addUnlabeledUnique(DijkstraRouteAlternative? alt) {
          if (alt == null) return;
          final sig = _alternativeRouteSignature(alt);
          if (!selectedSeen.add(sig)) return;
          selected.add(alt);
        }

        final balancedPick = pools[0].isEmpty ? null : pools[0].first;
        addLabeled('Balanced', balancedPick);

        final byTime = List<DijkstraRouteAlternative>.from(merged)
          ..sort((a, b) => a.estimatedTimeMinutes.compareTo(b.estimatedTimeMinutes));
        addLabeled(
          'Fastest',
          byTime.isEmpty ? null : byTime.first,
        );

        final byFare = List<DijkstraRouteAlternative>.from(merged)
          ..sort((a, b) => a.estimatedFarePhp.compareTo(b.estimatedFarePhp));
        addLabeled(
          'Budget',
          byFare.isEmpty ? null : byFare.first,
        );

        // Keep at least three visible options (when available) without
        // distorting the core labels.
        for (final alt in byTime) {
          if (selected.length >= 3) break;
          addUnlabeledUnique(alt);
        }
        for (final alt in byFare) {
          if (selected.length >= 3) break;
          addUnlabeledUnique(alt);
        }
        for (final alt in merged) {
          if (selected.length >= 3) break;
          addUnlabeledUnique(alt);
        }

        final hasTrainAlready = selected.any(_alternativeHasTrain);
        if (!hasTrainAlready) {
          final trainPick = _pickStrictAlternativeFromPool(
            merged.where(_alternativeHasTrain).toList(),
            selectedSeen,
          );
          addLabeled('Train', trainPick);
        }

        final hasCarouselAlready = selected.any(_alternativeHasCarousel);
        if (!hasCarouselAlready) {
          final carouselPick = _pickStrictAlternativeFromPool(
            merged.where(_alternativeHasCarousel).toList(),
            selectedSeen,
          );
          addLabeled('Carousel', carouselPick);
        }

        alternatives = selected;
      } catch (e) {
        debugPrint('[SearchScreen] Alternative lookup failed: $e');
       }
      final result =
          fallbackAlternatives[0] ??
          (alternatives.isNotEmpty
              ? await RoutingService.buildRouteFromDijkstraAlternative(
                origin: origin,
                destination: destLatLng,
                alternative: alternatives.first.result,
                preferredMode: 'Auto',
              )
              : await RoutingService.getRoute(
                originName: originName,
                origin: origin,
                destinationName: query,
                destination: destLatLng,
                mode: 'Auto',
              ));

      await RouteCacheRepository.put(
        originName,
        query,
        'Auto',
        'supabase-gtfs-v11',
        result,
      );

      setState(() {
        _isLoadingOrs = false;
        _orsResult = result;
        _routeAlternatives = alternatives;
        _fallbackAlternativeRoutes = fallbackAlternatives;
        _alternativeLabels = labelsByIndex;
        _selectedAlternativeIndex = 0;
        _lastOriginForAlternatives = origin;
        _lastDestinationForAlternatives = destLatLng;
        _lastGeneratedOriginName = originName;
        _lastGeneratedDestinationName = query;
      });
    } on RoutingException catch (e) {
      setState(() {
        _isLoadingOrs = false;
        _orsError = true;
        _orsErrorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoadingOrs = false;
        _orsError = true;
        _orsErrorMessage = 'Unexpected error: $e';
      });
    }
  }
}
