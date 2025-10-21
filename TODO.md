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
- [x] Test: Run app, select route, add sample reports (e.g., Heavy traffic, Accident), verify display, file persistence, reload app to check load.
- [x] Edge cases: Handle no reports, multiple reports, file not existing (create empty), invalid JSON (fallback to empty).

Next step: Proceed with updating lib/models/route.dart.

# Gamification Features Implementation

## Overview
Adding achievements, badges, levels, and progress tracking to motivate users. Includes popup notifications for achievements.

## Steps to Complete

- [x] Create new models in lib/models/: user.dart (User class with points, level, badges), achievement.dart (Achievement class), badge.dart (Badge class).
- [x] Update lib/screens/profile_screen.dart: Add display for level, badges, progress bars, achievements list.
- [x] Update lib/screens/main_screen.dart: Remove leaderboard from navigation.
- [x] Update pubspec.yaml: Add dependencies shared_preferences, flutter_local_notifications.
- [x] Implement gamification logic: Add point earning in home_screen.dart (for searches), contribute_screen.dart (for contributions), route_map_screen.dart (for reports). Use shared_preferences to persist user data.
- [x] Add achievement unlocking logic: Check conditions after actions, unlock badges/achievements, show popup notification (SnackBar at top that auto-disappears).
- [x] Integrate progress tracking: Show progress bars in profile for next level/badge.
- [x] Test: Run app, perform actions to earn points/badges, verify profile updates, popup notifications.
- [x] Edge cases: Handle no achievements, multiple unlocks, persistence on app restart.
- [x] Implement achievement notification overlay: Add NotificationOverlay widget to show achievement notifications as overlays instead of SnackBars. Update route_map_screen.dart to use NotificationOverlay for unlocked items after reporting.

Next step: Test the implementation.
