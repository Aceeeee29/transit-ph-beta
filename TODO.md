# Route Issue Reporting Feature Implementation

## Overview
Adding user-reported issues (traffic, accidents, etc.) to routes in RouteMapScreen. Reports will be stored locally in reports.json (Map<String, List<Report>> keyed by route.id). Types based on user-specified categories: Traffic-Related (Heavy traffic/congestion, Road closure/construction, Detour/alternative route, Slow-moving vehicles), Safety-Related (Accident/crash, Hazard on road, Crime/suspicious activity), Transit-Specific (Bus/train delay, Cancelled service, Crowding/full capacity), Weather-Related (Flooding/water logging, Landslide/mudslide, Storm/lightning hazard).

## Steps to Complete

- [x] Update lib/models/route.dart: Add Report class with type (String), description (String?), timestamp (DateTime). Add List<Report>? reports to Route constructor (default empty).
- [x] Implement persistence: Create reports.json in project root. Add functions to load/save reports (Map<String, List<Report>> by route.id) using dart:io and json.
- [x] Update lib/screens/route_map_screen.dart:
  - Load reports for current route in initState (merge with route.reports if exists).
  - Add report button to AppBar (Icons.report_problem).
  - On press, show bottom sheet/dialog with selectable report types (use ListView with RadioListTile for categories/subtypes, TextField for additional description).
  - On submit, create Report, add to loaded reports list, save to file, update UI with setState, show SnackBar confirmation.
  - Add section below steps to display reports (e.g., ExpansionTile or ListView of Cards showing type, desc, formatted time).
- [] Test: Run app, select route, add sample reports (e.g., Heavy traffic, Accident), verify display, file persistence, reload app to check load.
- [] Edge cases: Handle no reports, multiple reports, file not existing (create empty), invalid JSON (fallback to empty).

Next step: Proceed with updating lib/models/route.dart.
