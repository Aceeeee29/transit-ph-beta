# Profile Screen Polish TODO

## 1. Update Models
- [x] Add new fields to User model: totalDistance (double), co2Saved (double), mostActiveRegion (String?), streakDays (int)
- [x] Add progress (int), maxProgress (int), rarity (String) to Achievement model
- [x] Add contributorId (String) to Route model

## 2. Enhance Services
- [x] Add calculateCo2Saved method to RouteMetricsService
- [x] Create RouteService with getRoutesByUser method for Firestore queries
- [x] Update GamificationService to calculate and save new user stats

## 3. Update Dependencies
- [x] Add share_plus to pubspec.yaml for social sharing (removed as per user request)

## 4. Create New Screens
- [x] Create leaderboard_screen.dart for simple leaderboard display (removed as per user request)

## 5. Update Existing Screens
- [x] Modify contribute_screen.dart to accept optional route for editing
- [x] Update profile_screen.dart to display new stats, enhanced achievements with progress bars/rarity, and populated contributions with metrics/edit buttons

## 6. Testing
- [x] Test profile screen functionality after implementation
- [x] Verify CO2 calculations and stats accuracy
- [x] Ensure social sharing and leaderboard integration work properly
