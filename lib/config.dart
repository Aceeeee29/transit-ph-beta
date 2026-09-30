import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String get openRouteServiceApiKey =>
      dotenv.env['OPENROUTESERVICE_API_KEY'] ?? '';

  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? '';

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// Firebase Hosting serves `/q/{token}` (see firebase.json → quick.html).
  static const _defaultQuickRouteBaseUrl = 'https://transitph-75da4.web.app';

  static String get quickRouteBaseUrl {
    final fromEnv = dotenv.env['QUICK_ROUTE_BASE_URL']?.trim() ?? '';
    return fromEnv.isNotEmpty ? fromEnv : _defaultQuickRouteBaseUrl;
  }
}