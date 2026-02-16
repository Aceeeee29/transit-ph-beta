import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/route.dart' as route_model;
import '../services/media_service.dart';
import '../services/route_metrics_service.dart';

class RouteStepperWidget extends StatefulWidget {
  final List<route_model.Step> steps;
  final List<LatLng> pathPoints;
  final List<int> stepBoundaries;
  final Function(List<route_model.Step>) onStepsChanged;
  final Function(int, int) onStepReordered;
  final Function(int) onStepDeleted;
  
  const RouteStepperWidget({
    super.key,
    required this.steps,
    required this.pathPoints,
    required this.stepBoundaries,
    required this.onStepsChanged,
    required this.onStepReordered,
    required this.onStepDeleted,
  });
  
  @override
  State<RouteStepperWidget> createState() => _RouteStepperWidgetState();
}

class _RouteStepperWidgetState extends State<RouteStepperWidget> {
  int _activeStep = 0;
  List<File?> _stepImages = [];
  
  @override
  void initState() {
    super.initState();
    _stepImages = List.generate(widget.steps.length, (_) => null);
  }
  
  @override
  void didUpdateWidget(RouteStepperWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.steps.length > _stepImages.length) {
      _stepImages = List.generate(widget.steps.length, (index) {
        return index < _stepImages.length ? _stepImages[index] : null;
      });
    }
  }
  
  Future<void> _pickImage(int stepIndex) async {
    final image = await MediaService.pickImageFromGallery();
    if (image != null) {
      setState(() {
        _stepImages[stepIndex] = image;
      });
    }
  }
  
  Future<void> _takePhoto(int stepIndex) async {
    final image = await MediaService.takePhoto();
    if (image != null) {
      setState(() {
        _stepImages[stepIndex] = image;
      });
    }
  }
  
  void _updateStep(int index, String instruction, String details) {
    final updatedSteps = List<route_model.Step>.from(widget.steps);
    updatedSteps[index] = route_model.Step(
      mode: widget.steps[index].mode,
      instruction: instruction,
      details: details,
    );
    widget.onStepsChanged(updatedSteps);
  }
  
  String _getStepDistance(int index) {
    if (widget.pathPoints.isEmpty || widget.stepBoundaries.isEmpty) {
      return '';
    }
    
    final startIdx = (index == 0) ? 0 : widget.stepBoundaries[index - 1];
    final endIdx = (index < widget.stepBoundaries.length) 
        ? widget.stepBoundaries[index] 
        : widget.pathPoints.length - 1;
    
    if (endIdx <= startIdx || startIdx >= widget.pathPoints.length || endIdx >= widget.pathPoints.length) {
      return '';
    }
    
    final stepPoints = widget.pathPoints.sublist(startIdx, endIdx + 1);
    final distance = RouteMetricsService.calculateRouteDistance(stepPoints);
    return RouteMetricsService.formatDistance(distance);
  }
  
  String _getStepEta(int index) {
    if (widget.pathPoints.isEmpty || widget.stepBoundaries.isEmpty || index >= widget.steps.length) {
      return '';
    }
    
    final startIdx = (index == 0) ? 0 : widget.stepBoundaries[index - 1];
    final endIdx = (index < widget.stepBoundaries.length) 
        ? widget.stepBoundaries[index] 
        : widget.pathPoints.length - 1;
    
    if (endIdx <= startIdx || startIdx >= widget.pathPoints.length || endIdx >= widget.pathPoints.length) {
      return '';
    }
    
    final stepPoints = widget.pathPoints.sublist(startIdx, endIdx + 1);
    final modes = [widget.steps[index].mode];
    final boundaries = [stepPoints.length - 1];
    
    final minutes = RouteMetricsService.calculateEta(stepPoints, modes, boundaries);
    return RouteMetricsService.formatEta(minutes);
  }
  
  @override
  Widget build(BuildContext context) {
    return Stepper(
      currentStep: _activeStep,
      onStepTapped: (step) => setState(() => _activeStep = step),
      controlsBuilder: (context, details) {
        return Row(
          children: [
            if (details.currentStep < widget.steps.length - 1)
              ElevatedButton(
                onPressed: details.onStepContinue,
                child: const Text('Next'),
              ),
            if (details.currentStep > 0) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: details.onStepCancel,
                child: const Text('Back'),
              ),
            ],
          ],
        );
      },
      onStepContinue: () {
        if (_activeStep < widget.steps.length - 1) {
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
      steps: List.generate(
        widget.steps.length,
        (index) {
          final step = widget.steps[index];
          final distance = _getStepDistance(index);
          final eta = _getStepEta(index);
          
          return Step(
            title: Row(
              children: [
                Icon(_getModeIcon(step.mode), color: _getModeColor(step.mode)),
                const SizedBox(width: 8),
                Text(step.mode),
                if (distance.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(distance, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
                if (eta.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(eta, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ],
            ),
            subtitle: Text(step.instruction),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step instruction field
                TextFormField(
                  initialValue: step.instruction,
                  decoration: const InputDecoration(
                    labelText: 'Instruction',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Ride a jeep with Cubao terminal',
                  ),
                  maxLines: 2,
                  onChanged: (value) => _updateStep(index, value, step.details),
                ),
                const SizedBox(height: 16),
                
                // Step details field
                TextFormField(
                  initialValue: step.details,
                  decoration: const InputDecoration(
                    labelText: 'Details',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Drop off at Gateway Mall',
                  ),
                  maxLines: 2,
                  onChanged: (value) => _updateStep(index, step.instruction, value),
                ),
                const SizedBox(height: 16),
                
                // Photo attachment
                Row(
                  children: [
                    const Text('Add Landmark Photo:'),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.photo_library),
                      onPressed: () => _pickImage(index),
                      tooltip: 'Choose from gallery',
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: () => _takePhoto(index),
                      tooltip: 'Take photo',
                    ),
                  ],
                ),
                
                // Show image if available
                if (_stepImages[index] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ImagePreviewWidget(
                      imageFile: _stepImages[index]!,
                      onReplace: () => _pickImage(index),
                      onDelete: () => setState(() => _stepImages[index] = null),
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // Delete step button
                TextButton.icon(
                  onPressed: () => widget.onStepDeleted(index),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Delete Step', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            isActive: _activeStep == index,
          );
        },
      ),
    );
  }
  
  IconData _getModeIcon(String mode) {
    switch (mode) {
      case 'Walk':
        return Icons.directions_walk;
      case 'Jeepney':
        return Icons.directions_bus;
      case 'Bus':
        return Icons.directions_bus_filled;
      case 'Train':
        return Icons.train;
      case 'Tricycle':
        return Icons.pedal_bike;
      case 'FX/Van':
        return Icons.directions_car;
      case 'Ferry':
        return Icons.directions_boat;
      default:
        return Icons.directions_walk;
    }
  }
  
  Color _getModeColor(String mode) {
    switch (mode) {
      case 'Walk':
        return Colors.green;
      case 'Jeepney':
        return Colors.blue;
      case 'Bus':
        return Colors.red;
      case 'Train':
        return Colors.purple;
      case 'Tricycle':
        return Colors.orange;
      case 'FX/Van':
        return Colors.amber;
      case 'Ferry':
        return Colors.lightBlue;
      default:
        return Colors.green;
    }
  }
}
