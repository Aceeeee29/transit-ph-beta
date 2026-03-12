import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Holds the result of an update check.
class UpdateInfo {
  final bool updateAvailable;
  final bool forceUpdate;
  final String updateUrl;
  final String updateMessage;

  const UpdateInfo({
    required this.updateAvailable,
    required this.forceUpdate,
    required this.updateUrl,
    required this.updateMessage,
  });
}

/// Checks for app updates using Firebase Remote Config.
///
/// Remote Config parameters expected:
///   - latest_version  (String)  — e.g. "1.2.0"
///   - update_url      (String)  — deep/store link for the update
///   - force_update    (Boolean) — whether the user must update immediately
///   - update_message  (String)  — message shown inside the update dialog
class UpdateChecker {
  // Remote Config parameter keys.
  static const String _keyLatestVersion = 'latest_version';
  static const String _keyUpdateUrl = 'update_url';
  static const String _keyForceUpdate = 'force_update';
  static const String _keyUpdateMessage = 'update_message';

  /// Initialises Remote Config with sensible defaults and fetch settings,
  /// then fetches & activates the latest values from Firebase.
  ///
  /// Returns an [UpdateInfo] describing whether an update is available.
  static Future<UpdateInfo> checkForUpdate() async {
    final remoteConfig = FirebaseRemoteConfig.instance;

    // ── 1. Set default values so the app works even without a network call. ──
    await remoteConfig.setDefaults({
      _keyLatestVersion: '1.0.0',
      _keyUpdateUrl: '',
      _keyForceUpdate: false,
      _keyUpdateMessage:
          'A new version of TransitPH is available. Please update to enjoy '
          'the latest features and improvements.',
    });

    // ── 2. Configure fetch settings. ──
    // minimumFetchInterval is intentionally short (1 minute) to simplify
    // testing during development. For production, raise this to 12 hours:
    //   const Duration(hours: 12)
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(minutes: 1),
      ),
    );

    // ── 3. Fetch the latest values from Firebase and activate them. ──
    try {
      await remoteConfig.fetchAndActivate();
    } catch (e) {
      // If the fetch fails (e.g. no internet), we fall back to cached /
      // default values and skip the update prompt gracefully.
      return const UpdateInfo(
        updateAvailable: false,
        forceUpdate: false,
        updateUrl: '',
        updateMessage: '',
      );
    }

    // ── 4. Read the Remote Config values. ──
    final latestVersion = remoteConfig.getString(_keyLatestVersion).trim();
    final updateUrl = remoteConfig.getString(_keyUpdateUrl).trim();
    final forceUpdate = remoteConfig.getBool(_keyForceUpdate);
    final updateMessage = remoteConfig.getString(_keyUpdateMessage).trim();

    // ── 5. Get the version currently installed on the device. ──
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();

    // ── 6. Compare versions using semantic versioning logic. ──
    final updateAvailable = _isNewerVersion(
      current: currentVersion,
      latest: latestVersion,
    );

    return UpdateInfo(
      updateAvailable: updateAvailable,
      forceUpdate: forceUpdate,
      updateUrl: updateUrl,
      updateMessage: updateMessage,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns true when [latest] is strictly greater than [current].
  ///
  /// Parses both strings as "major.minor.patch" integers, falling back to a
  /// plain string comparison if parsing fails.
  static bool _isNewerVersion({
    required String current,
    required String latest,
  }) {
    try {
      final cur = _parseVersion(current);
      final lat = _parseVersion(latest);

      // Compare major, then minor, then patch.
      for (int i = 0; i < 3; i++) {
        if (lat[i] > cur[i]) return true;
        if (lat[i] < cur[i]) return false;
      }
      return false; // versions are equal
    } catch (_) {
      // Fall back to a plain string comparison.
      return latest != current && latest.isNotEmpty;
    }
  }

  /// Parses a version string such as "1.2.3" into a list of three integers.
  static List<int> _parseVersion(String version) {
    final parts = version.split('.');
    return List.generate(3, (i) => i < parts.length ? int.parse(parts[i]) : 0);
  }
}
