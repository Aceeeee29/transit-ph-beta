import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

/// Keeps the native launch splash (the logo on navy) up until AuthGate has
/// a real screen to show (Home, login, terms...), so riders go straight
/// from the logo to it without the loading spinner in between.
class LaunchSplash {
  LaunchSplash._();

  // On a network Firestore can't reach, the account check takes ~10 s; past
  // this the spinner screen shows instead so the app doesn't look frozen.
  static const _maxHold = Duration(seconds: 6);

  static bool _held = false;

  /// Call once in main(), before runApp. Flutter draws nothing until
  /// [release].
  static void hold(WidgetsBinding binding) {
    FlutterNativeSplash.preserve(widgetsBinding: binding);
    _held = true;
    Timer(_maxHold, release);
  }

  /// Takes the splash down; the screen built now is the first one drawn.
  /// Safe to call from build and more than once.
  static void release() {
    if (!_held) return;
    _held = false;
    // Not mid-build: removing lets the first frame through.
    scheduleMicrotask(FlutterNativeSplash.remove);
  }
}
