import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationLanguage {
  final String code;
  final String label;

  const TranslationLanguage({required this.code, required this.label});
}

class TranslationService {
  static const List<TranslationLanguage> supportedLanguages = [
    TranslationLanguage(code: 'en', label: 'English'),
    TranslationLanguage(code: 'tl', label: 'Filipino / Tagalog'),
    TranslationLanguage(code: 'es', label: 'Spanish'),
    TranslationLanguage(code: 'ja', label: 'Japanese'),
    TranslationLanguage(code: 'ko', label: 'Korean'),
    TranslationLanguage(code: 'zh', label: 'Chinese'),
    TranslationLanguage(code: 'fr', label: 'French'),
    TranslationLanguage(code: 'de', label: 'German'),
    TranslationLanguage(code: 'it', label: 'Italian'),
    TranslationLanguage(code: 'ar', label: 'Arabic'),
    TranslationLanguage(code: 'hi', label: 'Hindi'),
  ];

  static Future<String> translate({
    required String text,
    required String targetLanguage,
    required String sourceLanguage,
  }) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw Exception(
        'ML Kit translation plugin is only available on Android and iOS builds.',
      );
    }

    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw Exception('Enter text to translate.');
    }

    if (sourceLanguage == targetLanguage) {
      return cleanText;
    }

    final source = _asTranslateLanguage(sourceLanguage);
    final target = _asTranslateLanguage(targetLanguage);

    if (source == null || target == null) {
      throw Exception('Unsupported language selected for ML Kit.');
    }

    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );

    try {
      final translated = await translator.translateText(cleanText);
      if (translated.trim().isEmpty) {
        throw Exception('ML Kit returned an empty translation.');
      }
      return translated.trim();
    } finally {
      await translator.close();
    }
  }

  static TranslateLanguage? _asTranslateLanguage(String code) {
    const map = <String, TranslateLanguage>{
      'en': TranslateLanguage.english,
      'tl': TranslateLanguage.tagalog,
      'es': TranslateLanguage.spanish,
      'ja': TranslateLanguage.japanese,
      'ko': TranslateLanguage.korean,
      'zh': TranslateLanguage.chinese,
      'fr': TranslateLanguage.french,
      'de': TranslateLanguage.german,
      'it': TranslateLanguage.italian,
      'ar': TranslateLanguage.arabic,
      'hi': TranslateLanguage.hindi,
    };

    return map[code];
  }
}
