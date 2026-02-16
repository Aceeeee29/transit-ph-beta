import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/route.dart' as route_model;
import '../services/media_service.dart' hide ImagePreviewWidget, AudioPreviewWidget;
import 'media_preview_widgets.dart';

class RouteFormStepper extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController startLocationController;
  final TextEditingController endLocationController;
  final TextEditingController shortDescriptionController;
  final TextEditingController etaController;
  final TextEditingController priceController;
  final TextEditingController scheduleController;
  final List<route_model.Step> steps;
  final VoidCallback onSubmit;
  final VoidCallback onReset;
  final String selectionMode;

  const RouteFormStepper({
    super.key,
    required this.formKey,
    required this.startLocationController,
    required this.endLocationController,
    required this.shortDescriptionController,
    required this.etaController,
    required this.priceController,
    required this.scheduleController,
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

  @override
  Widget build(BuildContext context) {
    return Stepper(
      currentStep: _activeStep,
      onStepTapped: (step) => setState(() => _activeStep = step),
      controlsBuilder: (context, details) {
        return Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Row(
            children: [
              if (_activeStep < 2)
                ElevatedButton(
                  onPressed: details.onStepContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Next'),
                ),
              if (_activeStep > 0) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: details.onStepCancel,
                  child: const Text('Back'),
                ),
              ],
              const Spacer(),
              if (_activeStep == 2 && widget.selectionMode == 'done')
                ElevatedButton(
                  onPressed: widget.onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Submit Route'),
                ),
              if (widget.selectionMode != 'done')
                ElevatedButton(
                  onPressed: widget.onReset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Reset'),
                ),
            ],
          ),
        );
      },
      onStepContinue: () {
        if (_activeStep < 2) {
          setState(() {
            _activeStep++;
          });
        }
      },
      onStepCancel: () {
        if (_activeStep > 0) {
          setState(() {
            _activeStep--;
          });
        }
      },
      steps: [
        // Step 1: Basic Information
        Step(
          title: const Text('Basic Information'),
          subtitle: const Text('Route start and end points'),
          content: Column(
            children: [
              TextFormField(
                controller: widget.startLocationController,
                decoration: const InputDecoration(
                  labelText: 'Starting Location (tap map to select or type)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.endLocationController,
                decoration: const InputDecoration(
                  labelText: 'End Location (tap map to select or type)',
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
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Short description is required' : null,
              ),
            ],
          ),
          isActive: _activeStep == 0,
        ),
        
        // Step 2: Route Details
        Step(
          title: const Text('Route Details'),
          subtitle: const Text('Time, price, and schedule'),
          content: Column(
            children: [
              TextFormField(
                controller: widget.etaController,
                decoration: const InputDecoration(
                  labelText: 'Estimated Time of Arrival (ETA) in minutes',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) =>
                    value?.isEmpty ?? true ? 'ETA is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.priceController,
                decoration: const InputDecoration(
                  labelText: 'Price (e.g., PHP 50 or Free)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Price is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.scheduleController,
                decoration: const InputDecoration(
                  labelText: 'Schedule (e.g., 6AM-10PM daily)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Schedule is required' : null,
              ),
            ],
          ),
          isActive: _activeStep == 1,
        ),
        
        // Step 3: Media and Steps
        Step(
          title: const Text('Media & Steps'),
          subtitle: const Text('Add photos and voice notes'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Steps added: ${widget.steps.length}', 
                style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              // Landmark Photo
              const Text('Landmark Photo:', 
                style: TextStyle(fontWeight: FontWeight.bold)),
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
                    onDelete: () => setState(() => _landmarkImage = null),
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // Voice Note
              const Text('Voice Instructions:', 
                style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _toggleRecording,
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                    label: Text(_isRecording ? 'Stop Recording' : 'Record Voice Note'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red : Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              if (_voiceNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: AudioPreviewWidget(
                    audioFile: _voiceNote!,
                    onReplace: _toggleRecording,
                    onDelete: () => setState(() => _voiceNote = null),
                  ),
                ),
            ],
          ),
          isActive: _activeStep == 2,
        ),
      ],
    );
  }
  
  Future<void> _pickLandmarkImage() async {
    final image = await MediaService.pickImageFromGallery();
    if (image != null) {
      setState(() {
        _landmarkImage = image;
      });
    }
  }
  
  Future<void> _takeLandmarkPhoto() async {
    final image = await MediaService.takePhoto();
    if (image != null) {
      setState(() {
        _landmarkImage = image;
      });
    }
  }
  
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      final recordedFile = await MediaService.stopRecording();
      if (recordedFile != null) {
        setState(() {
          _voiceNote = recordedFile;
          _isRecording = false;
        });
      } else {
        setState(() {
          _isRecording = false;
        });
      }
    } else {
      // Start recording
      final success = await MediaService.startRecording();
      if (success) {
        setState(() {
          _isRecording = true;
        });
        
        // Show a snackbar to indicate recording
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
}
