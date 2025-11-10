# TODO: Improve Route Polylines in TransitPH App

## Visual Enhancements
- [x] Update polylines in `contribute_screen.dart` to add borders, increase thickness, and use rounded caps/joins for better aesthetics.
- [x] Update polylines in `route_map_screen.dart` to match the visual improvements from contribute screen.

## Street-Fitting Integration
- [x] Add OpenRouteService API integration in `contribute_screen.dart` to fetch road-based routes between tapped points.
- [x] Implement API key handling (use free tier, prompt user if needed).
- [x] Modify `_onMapTap` to call API for routing instead of straight lines.
- [x] Update pathPoints to use API-fetched coordinates.
- [x] Handle API errors gracefully (fallback to straight lines if API fails).

## Testing and Followup
- [ ] Test visual changes on both screens.
- [ ] Test API integration with sample routes.
- [ ] Ensure no breaking changes to existing functionality.
- [ ] Update dependencies if needed (add any required packages for API calls).
