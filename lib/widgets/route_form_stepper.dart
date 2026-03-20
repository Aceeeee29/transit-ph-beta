import 'dart:io';
import 'package:flutter/material.dart';
import '../models/route.dart' as route_model;
import '../services/media_service.dart'
    hide ImagePreviewWidget, AudioPreviewWidget;
import 'media_preview_widgets.dart';

class RouteFormStepper extends StatefulWidget {
  final TextEditingController startLocationController;
  final TextEditingController endLocationController;
  final TextEditingController shortDescriptionController;
  final List<route_model.Step> steps;
  final VoidCallback onSubmit;
  final VoidCallback onReset;
  final String selectionMode;

  const RouteFormStepper({
    super.key,
    required this.startLocationController,
    required this.endLocationController,
    required this.shortDescriptionController,
    required this.steps,
    required this.onSubmit,
    required this.onReset,
    required this.selectionMode,
  });

  @override
  State<RouteFormStepper> createState() => _RouteFormStepperState();
}

class _RouteFormStepperState extends State<RouteFormStepper> {
  int _activeStep = 0;
  File? _landmarkImage;
  File? _voiceNote;
  bool _isRecording = false;

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _accent = Color(0xFF2E7CF6);
  static const _warning = Color(0xFFFFB547);
  static const _danger = Color(0xFFE05C6A);
  static const _border = Color(0xFFD4E4F7);
  static const _surfaceAlt = Color(0xFFEAF2FF);

  @override
  Widget build(BuildContext context) {
    return Stepper(
      currentStep: _activeStep,
      onStepTapped: (step) => setState(() => _activeStep = step),
      controlsBuilder: (context, details) {
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_activeStep < 1)
                    ElevatedButton(
                      onPressed: details.onStepContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Next'),
                    ),
                  if (_activeStep == 0) ...[
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _clearBasicInfo,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _danger,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                  if (_activeStep > 0) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Back'),
                    ),
                  ],
                ],
              ),

              // ── Submit for Review button — only on last step when map is done ──
              if (_activeStep == 1 && widget.selectionMode == 'done') ...[
                const SizedBox(height: 12),

                // Pending review info banner
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: _warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: _warning),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Your route will be reviewed by a moderator before it appears publicly.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7A92B2),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Submit for Review button
                ElevatedButton.icon(
                  onPressed: widget.onSubmit,
                  icon: const Icon(Icons.pending_actions_rounded,
                      size: 18, color: Colors.white),
                  label: const Text(
                    'Submit for Review',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _warning,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ],
          ),
        );
      },
      onStepContinue: () {
        if (_activeStep < 1) setState(() => _activeStep++);
      },
      onStepCancel: () {
        if (_activeStep > 0) setState(() => _activeStep--);
      },
      steps: [
        // ── Step 1: Basic Information ─────────────────────────────────────────
        Step(
          title: const Text('Basic Information'),
          subtitle: const Text('Route start and end points'),
          content: Column(
            children: [
              TextFormField(
                controller: widget.startLocationController,
                decoration: const InputDecoration(
                  labelText:
                      'Starting Location (tap map to select or type)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.endLocationController,
                decoration: const InputDecoration(
                  labelText:
                      'End Location (tap map to select or type)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.shortDescriptionController,
                decoration: const InputDecoration(
                  labelText: 'Short Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          isActive: _activeStep == 0,
        ),

        // ── Step 2: Media and Steps ───────────────────────────────────────────
        Step(
          title: const Text('Media & Steps'),
          subtitle: const Text('Add photos and voice notes'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Steps count chip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_rounded,
                        size: 14, color: _accent),
                    const SizedBox(width: 6),
                    Text(
                      'Steps added: ${widget.steps.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Landmark Photo ───────────────────────────────────────────
              const Text(
                'Landmark Photo:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickLandmarkImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Choose Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _takeLandmarkPhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              if (_landmarkImage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: ImagePreviewWidget(
                    imageFile: _landmarkImage!,
                    onReplace: _pickLandmarkImage,
                    onDelete: () =>
                        setState(() => _landmarkImage = null),
                  ),
                ),

              const SizedBox(height: 16),

              // ── Voice Note ───────────────────────────────────────────────
              const Text(
                'Voice Instructions:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _toggleRecording,
                icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                label: Text(
                  _isRecording
                      ? 'Stop Recording'
                      : 'Record Voice Note',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isRecording ? Colors.red : Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              if (_voiceNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: AudioPreviewWidget(
                    audioFile: _voiceNote!,
                    onReplace: _toggleRecording,
                    onDelete: () =>
                        setState(() => _voiceNote = null),
                  ),
                ),
            ],
          ),
          isActive: _activeStep == 1,
        ),
      ],
    );
  }

  Future<void> _pickLandmarkImage() async {
    final image = await MediaService.pickImageFromGallery();
    if (image != null) setState(() => _landmarkImage = image);
  }

  Future<void> _takeLandmarkPhoto() async {
    final image = await MediaService.takePhoto();
    if (image != null) setState(() => _landmarkImage = image);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final recordedFile = await MediaService.stopRecording();
      setState(() {
        _voiceNote = recordedFile;
        _isRecording = false;
      });
    } else {
      final success = await MediaService.startRecording();
      if (success) {
        setState(() => _isRecording = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording voice note...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _clearBasicInfo() {
    widget.startLocationController.clear();
    widget.endLocationController.clear();
    widget.shortDescriptionController.clear();
  }
}