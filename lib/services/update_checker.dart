import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

class UpdateChecker {
  static const String _keyLatestVersion = 'latest_version';
  static const String _keyUpdateUrl = 'update_url';
  static const String _keyForceUpdate = 'force_update';
  static const String _keyUpdateMessage = 'update_message';

  static const String _configCollection = 'app_config';
  static const String _configDoc = 'update_checker';

  static Future<UpdateInfo> checkForUpdate() async {
    const defaultMessage =
        'A new version of TransitPH is available. Please update to enjoy '
        'the latest features and improvements.';

    final remoteConfig = FirebaseRemoteConfig.instance;

    final firestoreConfig = await _readFromFirestore();
    final remoteConfigData = await _readFromRemoteConfig(
      remoteConfig,
      defaultMessage,
    );

    final latestVersion =
        (firestoreConfig?[_keyLatestVersion] as String?) ??
        (remoteConfigData?[_keyLatestVersion] as String?) ??
        '1.0.0';
    final updateUrl =
        (firestoreConfig?[_keyUpdateUrl] as String?) ??
        (remoteConfigData?[_keyUpdateUrl] as String?) ??
        '';
    final forceUpdate =
        (firestoreConfig?[_keyForceUpdate] as bool?) ??
        (remoteConfigData?[_keyForceUpdate] as bool?) ??
        false;
    final updateMessage =
        (firestoreConfig?[_keyUpdateMessage] as String?) ??
        (remoteConfigData?[_keyUpdateMessage] as String?) ??
        '';

    if (latestVersion.trim().isEmpty) {
      return const UpdateInfo(
        updateAvailable: false,
        forceUpdate: false,
        updateUrl: '',
        updateMessage: '',
      );
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();

    final updateAvailable = _isNewerVersion(
      current: currentVersion,
      latest: latestVersion.trim(),
    );

    return UpdateInfo(
      updateAvailable: updateAvailable,
      forceUpdate: forceUpdate,
      updateUrl: updateUrl.trim(),
      updateMessage: updateMessage.trim(),
    );
  }

  static Future<Map<String, Object?>?> _readFromFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_configCollection)
          .doc(_configDoc)
          .get();

      if (!snap.exists) return null;

      final data = snap.data() ?? <String, dynamic>{};
      return {
        _keyLatestVersion: _asString(data[_keyLatestVersion], fallback: '1.0.0'),
        _keyUpdateUrl: _asString(data[_keyUpdateUrl]),
        _keyForceUpdate: _asBool(data[_keyForceUpdate]),
        _keyUpdateMessage: _asString(data[_keyUpdateMessage]),
      };
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, Object?>?> _readFromRemoteConfig(
    FirebaseRemoteConfig remoteConfig,
    String defaultMessage,
  ) async {
    await remoteConfig.setDefaults({
      _keyLatestVersion: '1.0.0',
      _keyUpdateUrl: '',
      _keyForceUpdate: false,
      _keyUpdateMessage: defaultMessage,
    });

    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(minutes: 1),
      ),
    );

    try {
      await remoteConfig.fetchAndActivate();
    } catch (_) {}

    return {
      _keyLatestVersion: remoteConfig.getString(_keyLatestVersion).trim(),
      _keyUpdateUrl: remoteConfig.getString(_keyUpdateUrl).trim(),
      _keyForceUpdate: remoteConfig.getBool(_keyForceUpdate),
      _keyUpdateMessage: remoteConfig.getString(_keyUpdateMessage).trim(),
    };
  }

  static bool _isNewerVersion({
    required String current,
    required String latest,
  }) {
    try {
      final cur = _parseVersion(current);
      final lat = _parseVersion(latest);

      for (int i = 0; i < 3; i++) {
        if (lat[i] > cur[i]) return true;
        if (lat[i] < cur[i]) return false;
      }
      return false;
    } catch (_) {
      return latest != current && latest.isNotEmpty;
    }
  }

  static List<int> _parseVersion(String version) {
    final parts = version.split('.');
    return List.generate(3, (i) => i < parts.length ? int.parse(parts[i]) : 0);
  }

  static String _asString(Object? value, {String fallback = ''}) {
    if (value is String) return value.trim();
    if (value == null) return fallback;
    return value.toString().trim();
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }
}
