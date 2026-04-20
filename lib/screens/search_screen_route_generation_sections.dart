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

        DijkstraRouteAlternative? pickFrom(List<DijkstraRouteAlternative> pool) {
          for (final alt in pool) {
            final sig = _alternativeRouteSignature(alt);
            if (selectedSeen.contains(sig)) continue;
            return alt;
          }
          for (final alt in merged) {
            final sig = _alternativeRouteSignature(alt);
            if (selectedSeen.contains(sig)) continue;
            return alt;
          }
          return null;
        }

        void addLabeled(String label, DijkstraRouteAlternative? alt) {
          if (alt == null) return;
          final sig = _alternativeRouteSignature(alt);
          if (!selectedSeen.add(sig)) return;
          selected.add(alt);
          labelsByIndex[selected.length - 1] = label;
        }

        final balancedPick = pickFrom(pools[0]);
        addLabeled('Balanced', balancedPick);

        final byTime = List<DijkstraRouteAlternative>.from(merged)
          ..sort((a, b) => a.estimatedTimeMinutes.compareTo(b.estimatedTimeMinutes));
        addLabeled('Fastest', pickFrom(byTime));

        final byFare = List<DijkstraRouteAlternative>.from(merged)
          ..sort((a, b) => a.estimatedFarePhp.compareTo(b.estimatedFarePhp));
        addLabeled('Budget', pickFrom(byFare));

        final hasTrainAlready = selected.any(_alternativeHasTrain);
        if (!hasTrainAlready) {
          final trainPick = pickFrom(merged.where(_alternativeHasTrain).toList());
          addLabeled('Train', trainPick);
        }

        alternatives = selected;

        final tripIdSignatures = <String>{};
        for (var i = 0; i < alternatives.length; i++) {
          final signature = _alternativeTripIdSignature(alternatives[i]);
          if (signature.isEmpty || tripIdSignatures.add(signature)) continue;

          fallbackAlternatives[i] = await RoutingService.buildWalkFallbackRoute(
            origin: origin,
            destination: destLatLng,
            note: 'Showing walking fallback route for visual variety.',
          );
        }
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
