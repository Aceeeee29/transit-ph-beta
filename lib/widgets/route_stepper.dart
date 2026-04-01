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

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

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
      is24_7: widget.steps[index].is24_7,
      startTime: widget.steps[index].startTime,
      endTime: widget.steps[index].endTime,
      actualFare: widget.steps[index].actualFare,
      alternateRouteSuggestion: widget.steps[index].alternateRouteSuggestion,
    );
    widget.onStepsChanged(updatedSteps);
  }

  String _getStepDistance(int index) {
    if (widget.pathPoints.isEmpty || widget.stepBoundaries.isEmpty) {
      return '';
    }

    final startIdx = (index == 0) ? 0 : widget.stepBoundaries[index - 1];
    final endIdx =
        (index < widget.stepBoundaries.length)
            ? widget.stepBoundaries[index]
            : widget.pathPoints.length - 1;

    if (endIdx <= startIdx ||
        startIdx >= widget.pathPoints.length ||
        endIdx >= widget.pathPoints.length) {
      return '';
    }

    final stepPoints = widget.pathPoints.sublist(startIdx, endIdx + 1);
    final distance = RouteMetricsService.calculateRouteDistance(stepPoints);
    return RouteMetricsService.formatDistance(distance);
  }

  String _getStepEta(int index) {
    if (widget.pathPoints.isEmpty ||
        widget.stepBoundaries.isEmpty ||
        index >= widget.steps.length) {
      return '';
    }

    final startIdx = (index == 0) ? 0 : widget.stepBoundaries[index - 1];
    final endIdx =
        (index < widget.stepBoundaries.length)
            ? widget.stepBoundaries[index]
            : widget.pathPoints.length - 1;

    if (endIdx <= startIdx ||
        startIdx >= widget.pathPoints.length ||
        endIdx >= widget.pathPoints.length) {
      return '';
    }

    final stepPoints = widget.pathPoints.sublist(startIdx, endIdx + 1);
    final modes = [widget.steps[index].mode];
    final boundaries = [stepPoints.length - 1];

    final minutes = RouteMetricsService.calculateEta(
      stepPoints,
      modes,
      boundaries,
    );
    return RouteMetricsService.formatEta(minutes);
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

  // ─── Styled text field ─────────────────────────────────────────────────────
  Widget _styledField({
    required String label,
    required String hint,
    required IconData icon,
    required String initialValue,
    required ValueChanged<String> onChanged,
    int maxLines = 2,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _surfaceAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: _border),
          ),
          child: TextFormField(
            initialValue: initialValue,
            maxLines: maxLines,
            style: const TextStyle(color: _textPrimary, fontSize: 13),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _textSecondary, fontSize: 13),
              prefixIcon: Icon(icon, color: _accent, size: 16),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 11,
                horizontal: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.alt_route,
                size: 28,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No steps yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.steps.length,
      itemBuilder: (context, index) {
        final step = widget.steps[index];
        final distance = _getStepDistance(index);
        final eta = _getStepEta(index);
        final modeColor = _getModeColor(step.mode);
        final isActive = _activeStep == index;

        return GestureDetector(
          onTap: () => setState(() => _activeStep = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? _accent.withOpacity(0.4) : _border,
                width: isActive ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      isActive
                          ? _accent.withOpacity(0.08)
                          : Colors.black.withOpacity(0.03),
                  blurRadius: isActive ? 14 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── Step header (always visible) ──────────────────────
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Step number + mode icon
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: modeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: modeColor.withOpacity(0.3),
                              ),
                            ),
                            child: Icon(
                              _getModeIcon(step.mode),
                              color: modeColor,
                              size: 19,
                            ),
                          ),
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: isActive ? _accent : _surfaceAlt,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isActive ? _accent : _border,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        isActive
                                            ? Colors.white
                                            : _textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  step.mode,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: modeColor,
                                  ),
                                ),
                                if (distance.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _surfaceAlt,
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: _border),
                                    ),
                                    child: Text(
                                      distance,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                                if (eta.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _accentSoft,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      eta,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (step.instruction.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                step.instruction,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        isActive
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: _textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                ),

                // ── Expanded content (when active) ────────────────────
                if (isActive) ...[
                  Divider(color: _border, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Instruction field
                        _styledField(
                          label: 'Instruction',
                          hint: 'e.g., Ride a jeep with Cubao terminal',
                          icon: Icons.info_outline_rounded,
                          initialValue: step.instruction,
                          onChanged:
                              (value) =>
                                  _updateStep(index, value, step.details),
                        ),
                        const SizedBox(height: 12),

                        // Details field
                        _styledField(
                          label: 'Details',
                          hint: 'e.g., Drop off at Gateway Mall',
                          icon: Icons.location_on_outlined,
                          initialValue: step.details,
                          onChanged:
                              (value) =>
                                  _updateStep(index, step.instruction, value),
                        ),
                        const SizedBox(height: 14),

                        // Photo attachment
                        const Text(
                          'Landmark Photo',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _photoButton(
                              icon: Icons.photo_library_outlined,
                              label: 'Gallery',
                              onTap: () => _pickImage(index),
                            ),
                            const SizedBox(width: 8),
                            _photoButton(
                              icon: Icons.camera_alt_outlined,
                              label: 'Camera',
                              onTap: () => _takePhoto(index),
                            ),
                          ],
                        ),

                        // Show image if available
                        if (_stepImages[index] != null) ...[
                          const SizedBox(height: 10),
                          ImagePreviewWidget(
                            imageFile: _stepImages[index]!,
                            onReplace: () => _pickImage(index),
                            onDelete:
                                () => setState(() => _stepImages[index] = null),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // Navigation + delete row
                        Row(
                          children: [
                            if (index > 0)
                              _navButton(
                                icon: Icons.arrow_back_ios_new_rounded,
                                label: 'Back',
                                onTap:
                                    () =>
                                        setState(() => _activeStep = index - 1),
                              ),
                            const Spacer(),
                            // Delete step button
                            GestureDetector(
                              onTap: () => widget.onStepDeleted(index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _danger.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: _danger.withOpacity(0.3),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      color: _danger,
                                      size: 14,
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Delete',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _danger,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (index < widget.steps.length - 1) ...[
                              const SizedBox(width: 8),
                              _navButton(
                                icon: Icons.arrow_forward_ios_rounded,
                                label: 'Next',
                                onTap:
                                    () =>
                                        setState(() => _activeStep = index + 1),
                                isPrimary: true,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _photoButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _accent, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? _accentSoft : _surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isPrimary ? _accent.withOpacity(0.3) : _border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isPrimary) Icon(icon, color: _textSecondary, size: 12),
            if (!isPrimary) const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isPrimary ? _accent : _textSecondary,
              ),
            ),
            if (isPrimary) const SizedBox(width: 5),
            if (isPrimary) Icon(icon, color: _accent, size: 12),
          ],
        ),
      ),
    );
  }
}
