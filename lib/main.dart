import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDeepLinks());
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  String? _extractQuickToken(Uri? uri) {
    if (uri == null) return null;

    final qpToken = uri.queryParameters['token']?.trim();
    if (qpToken != null && qpToken.isNotEmpty) {
      return qpToken;
    }

    if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'q') {
      final token = uri.pathSegments[1].trim();
      return token.isEmpty ? null : token;
    }

    if (uri.scheme == 'transitph') {
      if (uri.host == 'quick' && uri.pathSegments.isNotEmpty) {
        final token = uri.pathSegments.first.trim();
        return token.isEmpty ? null : token;
      }

      if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'quick') {
        final token = uri.pathSegments[1].trim();
        return token.isEmpty ? null : token;
      }
    }
    return null;
  }

  void _openQuickRouteToken(String token) {
    _navigatorKey.currentState?.pushNamed('/q/$token');
  }

  Future<void> _initDeepLinks() async {
    if (kIsWeb) {
      return;
    }

    _appLinks ??= AppLinks();

    try {
      final initialUri = await _appLinks!.getInitialLink();
      final token = _extractQuickToken(initialUri);
      if (token != null) {
        _openQuickRouteToken(token);
      }
    } catch (_) {}

    _deepLinkSub = _appLinks!.uriLinkStream.listen((uri) {
      final token = _extractQuickToken(uri);
      if (token != null) {
        _openQuickRouteToken(token);
      }
    });
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
      onGenerateRoute: (settings) {
        final name = settings.name ?? '/';

        if (name == '/') {
          final queryToken = Uri.base.queryParameters['quickRouteToken'];
          return MaterialPageRoute(
            builder: (_) => AuthGate(quickRouteToken: queryToken),
          );
        }

        if (name == '/main') {
          final args = settings.arguments;
          bool isAdmin = false;
          String? quickRouteToken;

          if (args is bool) {
            isAdmin = args;
          } else if (args is Map<String, dynamic>) {
            isAdmin = args['isAdmin'] as bool? ?? false;
            quickRouteToken = args['quickRouteToken'] as String?;
          }

          return MaterialPageRoute(
            builder: (_) => MainScreen(
              isAdmin: isAdmin,
              quickRouteToken: quickRouteToken,
            ),
          );
        }

        if (name.startsWith('/q/')) {
          final uri = Uri.parse(name);
          final token = uri.pathSegments.length >= 2 ? uri.pathSegments[1] : '';
          return MaterialPageRoute(
            builder: (_) => AuthGate(quickRouteToken: token),
          );
        }

        return MaterialPageRoute(builder: (_) => const AuthGate());
      },
    );
  }
}