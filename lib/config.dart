import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String get openRouteServiceApiKey => dotenv.env['OPENROUTESERVICE_API_KEY'] ?? '';
}
