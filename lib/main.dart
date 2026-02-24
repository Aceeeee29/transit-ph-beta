import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/main_screen.dart';
import 'services/moderation_service.dart';

/// app's theme.
ThemeData buildTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue.shade700),
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.grey.shade100,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
      ),
      prefixIconColor: Colors.grey.shade600,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade700,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

/// App routes configuration.
final Map<String, WidgetBuilder> appRoutes = {
  '/': (context) => const AuthGate(),
  '/main': (context) {
    final args = ModalRoute.of(context)!.settings.arguments;
    final isAdmin = args is bool ? args : false;
    return MainScreen(isAdmin: isAdmin);
  },
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize moderation service listeners
  ModerationService.init();

  await dotenv.load();

  runApp(const TransitPHApp());
}

class TransitPHApp extends StatelessWidget {
  const TransitPHApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TransitPH',
      theme: buildTheme(),
      initialRoute: '/',
      routes: appRoutes,
    );
  }
}
