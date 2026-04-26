import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String get openRouteServiceApiKey =>
      dotenv.env['OPENROUTESERVICE_API_KEY'] ?? '';

  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? '';

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  static String get quickRouteBaseUrl =>
      dotenv.env['QUICK_ROUTE_BASE_URL'] ?? '';
}