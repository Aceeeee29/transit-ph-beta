import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class MediaService {
  static final ImagePicker _imagePicker = ImagePicker();
  static bool _isRecording = false;
  static bool _isPlaying = false;
  
  /// Pick an image from the gallery
  static Future<File?> pickImageFromGallery() async {
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
      final filePath = '${tempDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
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
    } else if (['.mp3', '.m4a', '.aac', '.wav'].contains(extension)) {
      return MediaType.audio;
    } else {
      return MediaType.unknown;
    }
  }
}

enum MediaType {
  image,
  audio,
  unknown,
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
      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
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
                label: const Text('Delete', style: TextStyle(color: Colors.red)),
                onPressed: widget.onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
