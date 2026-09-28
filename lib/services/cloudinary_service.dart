import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Thrown when a Cloudinary upload fails — carries a user-facing message
/// plus the raw details for logs.
class CloudinaryUploadException implements Exception {
  final String userMessage;
  final String details;

  const CloudinaryUploadException(this.userMessage, [this.details = '']);

  @override
  String toString() => 'CloudinaryUploadException: $userMessage $details';
}

/// Unsigned media uploads to Cloudinary (no backend/API secret needed —
/// safe for a client-only Flutter app). Credentials come from .env:
/// CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET.
class CloudinaryService {
  static const int maxUploadBytes = 50 * 1024 * 1024;

  static String get _cloudName => dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
  static String get _uploadPreset =>
      dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? '';

  static Future<void> _checkUploadable(File file, String kind) async {
    if (!await file.exists()) {
      throw CloudinaryUploadException(
        'Selected $kind is no longer available. Please re-select it.',
        'file missing: ${file.path}',
      );
    }
    final size = await file.length();
    if (size <= 0) {
      throw CloudinaryUploadException(
        'Selected $kind is empty. Please choose another file.',
        'zero-byte file: ${file.path}',
      );
    }
    if (size > maxUploadBytes) {
      final mb = (size / (1024 * 1024)).toStringAsFixed(1);
      throw CloudinaryUploadException(
        'This $kind is $mb MB — over the 50 MB limit. Pick a smaller file.',
        'oversize file: $size bytes',
      );
    }
  }

  static Future<String> _upload({
    required File file,
    required String kind,
    required String resourceType,
    String? folder,
  }) async {
    await _checkUploadable(file, kind);

    if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
      throw const CloudinaryUploadException(
        'Media upload isn\'t configured yet. Please contact support.',
        'CLOUDINARY_CLOUD_NAME or CLOUDINARY_UPLOAD_PRESET missing from .env',
      );
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload',
    );

    try {
      final request =
          http.MultipartRequest('POST', uri)
            ..fields['upload_preset'] = _uploadPreset
            ..files.add(await http.MultipartFile.fromPath('file', file.path));
      if (folder != null) request.fields['folder'] = folder;

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 2),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        debugPrint(
          '[CloudinaryService] upload failed (${response.statusCode}): ${response.body}',
        );
        throw CloudinaryUploadException(
          'Upload failed — check your internet connection and try again.',
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final url = decoded['secure_url'] as String?;
      if (url == null || url.isEmpty) {
        throw const CloudinaryUploadException(
          'Upload failed unexpectedly. Please re-select the file.',
          'missing secure_url in Cloudinary response',
        );
      }
      return url;
    } on CloudinaryUploadException {
      rethrow;
    } catch (e) {
      debugPrint('[CloudinaryService] upload($kind) failed: $e');
      throw CloudinaryUploadException(
        'Failed to upload $kind. Check your connection and try again.',
        e.toString(),
      );
    }
  }

  /// Upload an image and return its Cloudinary URL.
  static Future<String> uploadImage(File file, {String? folder}) {
    return _upload(
      file: file,
      kind: 'photo',
      resourceType: 'image',
      folder: folder,
    );
  }

  /// Upload a video and return its Cloudinary URL.
  static Future<String> uploadVideo(File file, {String? folder}) {
    return _upload(
      file: file,
      kind: 'video',
      resourceType: 'video',
      folder: folder,
    );
  }
}
