import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'cloudinary_service.dart';

/// Thrown when a profile photo upload fails — carries a user-facing message
/// plus the raw details for logs.
class MediaUploadException implements Exception {
  final String userMessage;
  final String details;

  const MediaUploadException(this.userMessage, [this.details = '']);

  @override
  String toString() => 'MediaUploadException: $userMessage $details';
}

class MediaService {
  static final ImagePicker _imagePicker = ImagePicker();

  /// Largest photo accepted for upload (50MB).
  static const int maxUploadBytes = 50 * 1024 * 1024;

  /// Preflight checks before an upload.
  /// Throws [MediaUploadException] with a specific message on failure.
  static Future<void> _checkUploadable(File file, String kind) async {
    if (!await file.exists()) {
      throw MediaUploadException(
        'Selected $kind is no longer available. Please re-select it.',
        'file missing: ${file.path}',
      );
    }
    final size = await file.length();
    if (size <= 0) {
      throw MediaUploadException(
        'Selected $kind is empty. Please choose another file.',
        'zero-byte file: ${file.path}',
      );
    }
    if (size > maxUploadBytes) {
      final mb = (size / (1024 * 1024)).toStringAsFixed(1);
      throw MediaUploadException(
        'This $kind is $mb MB — over the 50 MB limit. Pick a smaller file.',
        'oversize file: $size bytes',
      );
    }
  }

  static Never _throwForUploadError(Object e, String kind, String context) {
    debugPrint('[MediaService] $context failed: $e');
    if (e is MediaUploadException) throw e;
    if (e is CloudinaryUploadException) {
      throw MediaUploadException(e.userMessage, e.details);
    }
    if (e is TimeoutException) {
      throw MediaUploadException(
        'Upload timed out. Check your connection and try again.',
        e.toString(),
      );
    }
    throw MediaUploadException(
      'Failed to upload $kind. Check your connection and try again.',
      e.toString(),
    );
  }

  /// Upload a profile picture to Cloudinary and return its URL.
  /// Throws [MediaUploadException] with a specific message on failure.
  static Future<String> uploadProfilePhoto(File file, String uid) async {
    const kind = 'photo';
    try {
      await _checkUploadable(file, kind);
      return await CloudinaryService.uploadImage(
        file,
        folder: 'users/$uid/profile',
      );
    } catch (e) {
      _throwForUploadError(e, kind, 'uploadProfilePhoto');
    }
  }

  /// Pick an image from the gallery
  static Future<File?> pickImageFromGallery() async {
    if (!kIsWeb) {
      PermissionStatus status = PermissionStatus.granted;

      if (Platform.isAndroid || Platform.isIOS) {
        status = await Permission.photos.request();
      }

      if (!status.isGranted) {
        return null;
      }
    }

    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (image != null) {
      return File(image.path);
    }

    return null;
  }

  /// Take a photo with the camera
  static Future<File?> takePhoto() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        return null;
      }
    }

    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (image != null) {
      return File(image.path);
    }

    return null;
  }
}

/// Widget to display an image with options to view, replace, or delete
class ImagePreviewWidget extends StatelessWidget {
  final File imageFile;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  const ImagePreviewWidget({
    super.key,
    required this.imageFile,
    required this.onReplace,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Image preview
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: FileImage(imageFile),
              fit: BoxFit.cover,
            ),
          ),
        ),

        // Controls overlay
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              // Replace button
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.7),
                radius: 16,
                child: IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  onPressed: onReplace,
                  tooltip: 'Replace',
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 8),
              // Delete button
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.7),
                radius: 16,
                child: IconButton(
                  icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
