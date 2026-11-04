import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Slows down password guessing on this phone.
///
/// Every wrong password locks the sign-in button for a while: 15 seconds
/// the first time, then double each time after, up to 15 minutes. The count
/// is saved so closing the app doesn't reset it. Firebase has its own limit
/// on the server; this only makes the app behave well before that kicks in.
class LoginThrottle {
  static const _failsKey = 'login_throttle_fails';
  static const _lockedUntilKey = 'login_throttle_locked_until';
  static const _lastFailKey = 'login_throttle_last_fail';
  // Key used by the first version, which counted 5 tries per lock.
  static const _oldLockoutsKey = 'login_throttle_lockouts';

  static const _firstLock = Duration(seconds: 15);
  static const _longestLock = Duration(minutes: 15);
  // Firebase doesn't say how long its own block lasts, so wait a bit.
  static const _serverBlockLock = Duration(minutes: 2);
  // A day with no wrong tries starts the count fresh.
  static const _forgetAfter = Duration(hours: 24);

  /// Shown while locked when there's no other error to show, e.g. after
  /// reopening the app mid-lock.
  static const lockMessage =
      'Sign-in is paused after a wrong try. Wait for the timer, then try again.';

  /// Only wrong email or password counts. Network errors don't.
  static bool _isWrongCredential(String code) =>
      code == 'wrong-password' ||
      code == 'user-not-found' ||
      code == 'invalid-credential' ||
      code == 'invalid-login-credentials';

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFail = prefs.getInt(_lastFailKey);
    if (lastFail != null &&
        DateTime.now().millisecondsSinceEpoch - lastFail >
            _forgetAfter.inMilliseconds) {
      await _clear(prefs);
    }
    return prefs;
  }

  static Future<void> _clear(SharedPreferences prefs) async {
    await prefs.remove(_failsKey);
    await prefs.remove(_lockedUntilKey);
    await prefs.remove(_lastFailKey);
    await prefs.remove(_oldLockoutsKey);
  }

  /// Time left on the lock, or zero when sign-in is open.
  static Future<Duration> remainingLock() async {
    final prefs = await _prefs();
    final until = prefs.getInt(_lockedUntilKey) ?? 0;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  /// Counts a failed sign-in and returns the new lock, or zero if none.
  static Future<Duration> recordFailure(String code) async {
    if (code == 'too-many-requests') return _lockFor(_serverBlockLock);
    if (!_isWrongCredential(code)) return remainingLock();

    final prefs = await _prefs();
    final fails = prefs.getInt(_failsKey) ?? 0;
    await prefs.setInt(_failsKey, fails + 1);
    // 15s, 30s, 1m, 2m, 4m, 8m, then 15m. The cap on the shift keeps the
    // number small; the min() does the real capping.
    final seconds = math.min(
      _firstLock.inSeconds << math.min(fails, 10),
      _longestLock.inSeconds,
    );
    return _lockFor(Duration(seconds: seconds));
  }

  static Future<Duration> _lockFor(Duration lock) async {
    final prefs = await _prefs();
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = math.max(
      prefs.getInt(_lockedUntilKey) ?? 0,
      now + lock.inMilliseconds,
    );
    await prefs.setInt(_lockedUntilKey, until);
    await prefs.setInt(_lastFailKey, now);
    return Duration(milliseconds: until - now);
  }

  /// Call after a correct password.
  static Future<void> reset() async {
    await _clear(await SharedPreferences.getInstance());
  }

  static String formatLock(Duration left) {
    final seconds = (left.inMilliseconds + 999) ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

/// Keeps a login screen's countdown ticking while sign-in is locked.
mixin LoginLockCountdown<T extends StatefulWidget> on State<T> {
  Duration lockLeft = Duration.zero;
  Timer? _lockTimer;

  bool get isLocked => lockLeft > Duration.zero;

  /// Reads the saved lock. Returns true if sign-in is locked right now.
  /// Both login screens share one lock, so check again before each try.
  Future<bool> refreshLock() async {
    final left = await LoginThrottle.remainingLock();
    if (mounted) _startCountdown(left);
    return left > Duration.zero;
  }

  /// Counts a failed sign-in and starts the countdown if it locks.
  Future<void> noteSignInFailure(String code) async {
    final left = await LoginThrottle.recordFailure(code);
    if (mounted) _startCountdown(left);
  }

  void _startCountdown(Duration left) {
    _lockTimer?.cancel();
    setState(() => lockLeft = left);
    if (left <= Duration.zero) return;

    final end = DateTime.now().add(left);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = end.difference(DateTime.now());
      if (remaining <= Duration.zero) timer.cancel();
      setState(
        () => lockLeft = remaining > Duration.zero ? remaining : Duration.zero,
      );
    });
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }
}
