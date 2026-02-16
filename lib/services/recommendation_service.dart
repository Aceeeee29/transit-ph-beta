import '../models/route.dart' as route_model;
import 'search_service.dart';
import 'location_service.dart';

class RecommendationService {
  /// Get recommended routes based on search history
  static Future<List<route_model.Route>> getBasedOnSearchHistory(
    List<route_model.Route> allRoutes,
    int limit,
  ) async {
    final recentSearches = await SearchService.getRecentSearches();
    
    if (recentSearches.isEmpty) {
      return [];
    }

    // Score routes based on search history relevance
    final scoredRoutes = <route_model.Route, int>{};
    
    for (final route in allRoutes) {
      int score = 0;
      final searchLower = recentSearches.take(3).map((s) => s.toLowerCase());
      
      for (final search in searchLower) {
        if (route.endLocation.toLowerCase().contains(search) ||
            route.startLocation.toLowerCase().contains(search) ||
            route.shortDescription.toLowerCase().contains(search)) {
          score += 3;
        }
      }
      
      if (score > 0) {
        scoredRoutes[route] = score;
      }
    }

    // Sort by score and return top results
    final sortedRoutes = scoredRoutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedRoutes.take(limit).map((e) => e.key).toList();
  }

  /// Get popular routes (by views + upvotes - downvotes)
  static List<route_model.Route> getPopularRoutes(
    List<route_model.Route> allRoutes,
    int limit,
  ) {
    final sortedRoutes = List<route_model.Route>.from(allRoutes);
    sortedRoutes.sort((a, b) {
      final scoreA = a.views + a.upvotes - a.downvotes;
      final scoreB = b.views + b.upvotes - b.downvotes;
      return scoreB.compareTo(scoreA);
    });
    return sortedRoutes.take(limit).toList();
  }

  /// Get routes suitable for rush hour (prioritize alternatives like train/jeepney over bus)
  static List<route_model.Route> getRushHourAlternatives(
    List<route_model.Route> allRoutes,
    int limit,
  ) {
    if (!LocationService.isRushHour()) {
      return [];
    }

    // Prioritize routes with multiple transport modes and train options
    final scoredRoutes = <route_model.Route, int>{};
    
    for (final route in allRoutes) {
      int score = 0;
      
      // Prefer routes with more steps (more alternatives)
      score += route.steps.length * 2;
      
      // Prefer train over bus during rush hour
      for (final step in route.steps) {
        if (step.mode.toLowerCase().contains('train')) {
          score += 10;
        }
        if (step.mode.toLowerCase().contains('jeepney')) {
          score += 5;
        }
      }
      
      scoredRoutes[route] = score;
    }

    final sortedRoutes = scoredRoutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedRoutes.take(limit).map((e) => e.key).toList();
  }

  /// Get time-based recommendations
  static Map<String, List<route_model.Route>> getTimeBasedRecommendations(
    List<route_model.Route> allRoutes,
  ) {
    final timeOfDay = LocationService.getTimeOfDayDescription();
    final recommendations = <String, List<route_model.Route>>{};
    
    // Get popular routes
    recommendations['popular'] = getPopularRoutes(allRoutes, 5);
    
    // Get rush hour alternatives if applicable
    if (LocationService.isRushHour()) {
      recommendations['rushHour'] = getRushHourAlternatives(allRoutes, 5);
    }
    
    // Add time-based section
    recommendations['timeOfDay'] = _getRoutesForTimeOfDay(allRoutes, timeOfDay);
    
    return recommendations;
  }

  /// Get routes appropriate for the current time of day
  static List<route_model.Route> _getRoutesForTimeOfDay(
    List<route_model.Route> allRoutes,
    String timeOfDay,
  ) {
    // For now, return popular routes filtered by common commuter destinations
    final commuterRoutes = allRoutes.where((route) {
      final desc = route.shortDescription.toLowerCase();
      return desc.contains('work') ||
          desc.contains('school') ||
          desc.contains('university') ||
          desc.contains('office') ||
          desc.contains('downtown') ||
          desc.contains('terminal');
    }).toList();
    
    if (commuterRoutes.isEmpty) {
      return getPopularRoutes(allRoutes, 5);
    }
    
    return commuterRoutes.take(5).toList();
  }

  /// Get all recommendations combined
  static Future<Map<String, List<route_model.Route>>> getAllRecommendations(
    List<route_model.Route> allRoutes,
  ) async {
    final recommendations = <String, List<route_model.Route>>{};
    
    // Get search history based recommendations
    recommendations['forYou'] = await getBasedOnSearchHistory(allRoutes, 5);
    
    // Get popular routes
    recommendations['popular'] = getPopularRoutes(allRoutes, 5);
    
    // Get rush hour alternatives if applicable
    if (LocationService.isRushHour()) {
      recommendations['rushHourAlternatives'] = getRushHourAlternatives(allRoutes, 5);
    }
    
    // If no personalized recommendations, use popular routes
    if (recommendations['forYou']!.isEmpty) {
      recommendations['forYou'] = getPopularRoutes(allRoutes, 5);
    }
    
    return recommendations;
  }
}
