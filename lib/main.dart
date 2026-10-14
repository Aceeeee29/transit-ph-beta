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
import 'services/location_service.dart';
import 'services/moderation_service.dart';
import 'services/offline_tile_service.dart';
import 'services/map_style_service.dart';
import 'services/settings_service.dart';
import 'config.dart';
import 'theme/app_colors.dart';

/// The app's theme, light or dark (Settings > Appearance). Most screens
/// take their colors from [AppColors]; this covers Material's own widgets
/// (dialogs, sheets, menus, fields, snack bars).
ThemeData buildTheme({bool dark = false}) {
  final palette = dark ? AppPalette.dark : AppPalette.light;
  var scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  if (dark) {
    scheme = scheme.copyWith(
      surface: palette.surface,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textSecondary,
      surfaceContainerLowest: palette.bg,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surface,
      surfaceContainerHighest: palette.surfaceAlt,
      outline: palette.border,
      outlineVariant: palette.border,
    );
  }
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: dark ? palette.bg : Colors.grey.shade100,
    appBarTheme:
        dark
            ? AppBarTheme(
              backgroundColor: palette.surface,
              foregroundColor: palette.textPrimary,
            )
            : null,
    dividerColor: dark ? palette.border : null,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // The card color, as white is by day: many fields sit borderless
      // inside cards, where any other fill shows as a box.
      fillColor: dark ? palette.surface : Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark ? palette.border : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      prefixIconColor: dark ? palette.textSecondary : Colors.grey.shade600,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
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
  // Only the copy on the phone is awaited: waiting on Firestore here kept the
  // screen blank for ~10 s on networks it can't reach quickly.
  await SettingsService.loadCachedPreferences();
  unawaited(SettingsService.loadPreferences());

  // Map look (classic or clean) and light or dark appearance, kept on the
  // device; loaded before the first frame so the app opens in its colors.
  await MapStyleService.instance.load();
  // Saved OpenStreetMap pictures from older versions (some are their
  // "Access blocked" notice); nothing reads them any more.
  unawaited(OfflineTileService.removeOldPictureTiles());

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
    _applyAppearance();
    MapStyleService.instance.isDark.addListener(_onAppearanceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDeepLinks());
    // Needs an attached activity, hence after the first frame.
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => LocationService.requestPermissionIfUndecided(),
      );
    }
  }

  @override
  void dispose() {
    MapStyleService.instance.isDark.removeListener(_onAppearanceChanged);
    _deepLinkSub?.cancel();
    super.dispose();
  }

  void _applyAppearance() {
    AppColors.palette =
        MapStyleService.instance.isDark.value
            ? AppPalette.dark
            : AppPalette.light;
  }

  void _onAppearanceChanged() {
    setState(_applyAppearance);
    // Screens read their colors from AppColors rather than the theme, so
    // nothing tells them to redraw: mark every widget for a rebuild. Each
    // keeps its state, so the open screen stays where it is.
    void markAll(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markAll);
    }

    (context as Element).visitChildren(markAll);
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'TransitPH',
      theme: buildTheme(dark: AppColors.isDark),
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
            builder:
                (_) => MainScreen(
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
