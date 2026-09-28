import 'package:flutter/foundation.dart';
import 'translation_service.dart';

/// Drives on-the-fly translation of the app's own UI text, keyed to the
/// user's Settings > Preferences > Language choice. Reuses the same
/// on-device ML Kit engine that powers the Quick Translator, so it only
/// works on Android/iOS — elsewhere (web/desktop) it silently stays English.
class AppLanguageService {
  static const Map<String, String> _labelToCode = {
    'English': 'en',
    'Filipino': 'tl',
    'Spanish': 'es',
  };
  static const Map<String, String> _codeToLabel = {
    'en': 'English',
    'tl': 'Filipino',
    'es': 'Spanish',
  };

  static final ValueNotifier<String> languageCode = ValueNotifier<String>('en');
  static final Map<String, String> _cache = {};

  static bool get isEnglish => languageCode.value == 'en';

  /// Display label for the currently selected language (e.g. "Filipino").
  static String get currentLanguageLabel =>
      _codeToLabel[languageCode.value] ?? 'English';

  static String codeForLabel(String? label) => _labelToCode[label] ?? 'en';

  /// Call whenever preferences load or save so the whole app stays in sync.
  static void syncFromLanguageLabel(String? label) {
    final code = codeForLabel(label);
    if (code != languageCode.value) {
      languageCode.value = code;
    }
  }

  /// Translate [text] from English to the current app language.
  /// Falls back to the original [text] on any failure (unsupported
  /// platform, or no network for the first-time model download).
  static Future<String> translate(String text) async {
    final target = languageCode.value;
    if (target == 'en' || text.trim().isEmpty) return text;

    final key = '$target::$text';
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final result = await TranslationService.translate(
        text: text,
        sourceLanguage: 'en',
        targetLanguage: target,
      );
      _cache[key] = result;
      return result;
    } catch (_) {
      return text;
    }
  }
}
