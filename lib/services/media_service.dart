import 'dart:io';
import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

/// Thrown when a post media upload fails — carries a user-facing message
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
  static FirebaseStorage get _storage => FirebaseStorage.instance;
  static bool _isRecording = false;
  static bool _isPlaying = false;

  /// Max file size accepted by storage.rules (50MB).
  static const int maxUploadBytes = 50 * 1024 * 1024;

  /// Common preflight checks shared by image/video uploads.
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

  static Never _throwForFirebaseError(
    Object e,
    String kind,
    String context,
  ) {
    debugPrint('[MediaService] $context failed: $e');
    if (e is MediaUploadException) throw e;
    if (e is TimeoutException) {
      throw MediaUploadException(
        'Upload timed out. Check your connection and try again.',
        e.toString(),
      );
    }
    if (e is FirebaseException) {
      switch (e.code) {
        case 'unauthenticated':
          throw MediaUploadException(
            'You must be signed in to attach $kind.',
            e.toString(),
          );
        case 'unauthorized':
        case 'permission-denied':
        case 'denied':
          throw MediaUploadException(
            'Server rejected the upload (permission denied). Storage may not be enabled yet — try again later or contact support.',
            e.toString(),
          );
        case 'quota-exceeded':
          throw MediaUploadException(
            'Server storage quota exceeded. Try again later.',
            e.toString(),
          );
        case 'retry-limit-exceeded':
        case 'unavailable':
        case 'network-request-failed':
        case 'unknown':
          throw MediaUploadException(
            'Upload failed — check your internet connection and try again. (If it keeps failing, Storage may not be enabled on the server.)',
            e.toString(),
          );
        case 'object-not-found':
          throw MediaUploadException(
            'Upload failed unexpectedly. Please re-select the file.',
            e.toString(),
          );
      }
    }
    throw MediaUploadException(
      'Failed to upload $kind. Check your connection and try again.',
      e.toString(),
    );
  }

  /// Upload a post image to Firebase Storage and return its download URL.
  /// Throws [MediaUploadException] with a specific message on failure.
  static Future<String> uploadPostImage(File file, String postId) async {
    const kind = 'photo';
    try {
      await _checkUploadable(file, kind);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}';
      final ref = _storage.ref().child('posts/$postId/images/$fileName');
      final ext = path.extension(file.path).toLowerCase();
      final contentType = ext == '.png'
          ? 'image/png'
          : ext == '.gif'
              ? 'image/gif'
              : ext == '.webp'
                  ? 'image/webp'
                  : 'image/jpeg';
      await ref
          .putFile(file, SettableMetadata(contentType: contentType))
          .timeout(const Duration(minutes: 2));
      return await ref.getDownloadURL();
    } catch (e) {
      _throwForFirebaseError(e, kind, 'uploadPostImage');
    }
  }

  /// Upload a post video to Firebase Storage and return its download URL.
  /// Throws [MediaUploadException] with a specific message on failure.
  static Future<String> uploadPostVideo(File file, String postId) async {
    const kind = 'video';
    try {
      await _checkUploadable(file, kind);
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}';
      final ref = _storage.ref().child('posts/$postId/videos/$fileName');
      final ext = path.extension(file.path).toLowerCase();
      final contentType = ext == '.mov'
          ? 'video/quicktime'
          : ext == '.webm'
              ? 'video/webm'
              : 'video/mp4';
      await ref
          .putFile(file, SettableMetadata(contentType: contentType))
          .timeout(const Duration(minutes: 2));
      return await ref.getDownloadURL();
    } catch (e) {
      _throwForFirebaseError(e, kind, 'uploadPostVideo');
    }
  }

  /// True when [url] looks like a remote (http/https) URL vs a local path.
  static bool isRemoteUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
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

  /// Pick a video from the gallery
  static Future<File?> pickVideoFromGallery() async {
    final XFile? video = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );

    if (video != null) {
      return File(video.path);
    }

    return null;
  }

  /// Record a video with the camera
  static Future<File?> recordVideo() async {
    final XFile? video = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 5),
    );

    if (video != null) {
      return File(video.path);
    }

    return null;
  }

  /// Start recording audio (simulated for now)
  static Future<bool> startRecording() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      return false;
    }

    // Simulate starting recording
    _isRecording = true;
    return true;
  }

  /// Stop recording and return the file (simulated for now)
  static Future<File?> stopRecording() async {
    if (_isRecording) {
      _isRecording = false;

      // Create a dummy file to simulate recording
      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final file = File(filePath);
      await file.writeAsString('Simulated audio content');

      return file;
    }
    return null;
  }

  /// Initialize audio player (simulated)
  static Future<void> initAudioPlayer() async {
    // Simulated initialization
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Play audio file (simulated)
  static Future<void> playAudio(String filePath) async {
    _isPlaying = true;
    // Simulate playing for 3 seconds
    await Future.delayed(const Duration(seconds: 3));
    _isPlaying = false;
  }

  /// Stop audio playback (simulated)
  static Future<void> stopAudio() async {
    _isPlaying = false;
  }

  /// Check if audio is playing (simulated)
  static bool get isPlaying => _isPlaying;

  /// Save a temporary file to a permanent location
  static Future<File> saveFilePermanently(File tempFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = path.basename(tempFile.path);
    final savedFile = await tempFile.copy('${appDir.path}/$fileName');
    return savedFile;
  }

  /// Get a unique file name
  static String getUniqueFileName(String originalName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.extension(originalName);
    final baseName = path.basenameWithoutExtension(originalName);
    return '${baseName}_$timestamp$extension';
  }

  /// Get file type from path
  static MediaType getFileType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.gif'].contains(extension)) {
      return MediaType.image;
    } else if (['.mp4', '.mov', '.avi', '.mkv'].contains(extension)) {
      return MediaType.video;
    } else if (['.mp3', '.m4a', '.aac', '.wav'].contains(extension)) {
      return MediaType.audio;
    } else {
      return MediaType.unknown;
    }
  }
}

enum MediaType { image, video, audio, unknown }

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

/// Widget to display audio controls for voice notes
class AudioPreviewWidget extends StatefulWidget {
  final File audioFile;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  const AudioPreviewWidget({
    super.key,
    required this.audioFile,
    required this.onReplace,
    required this.onDelete,
  });

  @override
  State<AudioPreviewWidget> createState() => _AudioPreviewWidgetState();
}

class _AudioPreviewWidgetState extends State<AudioPreviewWidget> {
  bool _isPlaying = false;
  double _playbackProgress = 0.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    MediaService.initAudioPlayer();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    MediaService.stopAudio();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await MediaService.stopAudio();
      _progressTimer?.cancel();
      setState(() {
        _isPlaying = false;
        _playbackProgress = 0.0;
      });
    } else {
      setState(() {
        _isPlaying = true;
      });

      // Start a timer to simulate progress
      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        setState(() {
          _playbackProgress += 0.01;
          if (_playbackProgress >= 1.0) {
            _playbackProgress = 0.0;
            _isPlaying = false;
            timer.cancel();
          }
        });
      });

      await MediaService.playAudio(widget.audioFile.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Play/Pause button
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: _togglePlayback,
                color: Colors.blue,
              ),

              // Progress bar
              Expanded(
                child: LinearProgressIndicator(
                  value: _playbackProgress,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),

              // Duration text
              const SizedBox(width: 8),
              Text(
                '0:${(_playbackProgress * 30).toInt().toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Replace button
              TextButton.icon(
                icon: const Icon(Icons.mic, size: 16),
                label: const Text('Re-record'),
                onPressed: widget.onReplace,
              ),
              const SizedBox(width: 8),
              // Delete button
              TextButton.icon(
                icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                label: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: widget.onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
