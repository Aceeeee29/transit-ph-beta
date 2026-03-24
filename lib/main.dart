import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/main_screen.dart';
import 'services/moderation_service.dart';
import 'services/settings_service.dart';
import 'widgets/update_dialog.dart';
import 'config.dart';

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

  // Load .env first — everything else depends on it
  await dotenv.load();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Supabase with keys from .env
  await Supabase.initialize(
    url: Config.supabaseUrl,
    anonKey: Config.supabaseAnonKey,
  );

  // Initialize moderation service listeners
  ModerationService.init();

  // Prime user preference cache so distance displays use the last selected unit.
  await SettingsService.loadPreferences();

  runApp(const TransitPHApp());
}

class TransitPHApp extends StatefulWidget {
  const TransitPHApp({super.key});

  @override
  State<TransitPHApp> createState() => _TransitPHAppState();
}

class _TransitPHAppState extends State<TransitPHApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    await UpdateDialog.checkAndShow(ctx);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'TransitPH',
      theme: buildTheme(),
      initialRoute: '/',
      routes: appRoutes,
    );
  }
}