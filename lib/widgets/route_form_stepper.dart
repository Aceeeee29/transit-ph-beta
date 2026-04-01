import 'package:flutter/material.dart';

class RouteFormStepper extends StatefulWidget {
  final TextEditingController startLocationController;
  final TextEditingController endLocationController;
  final TextEditingController shortDescriptionController;
  final List<String> selectedRouteTags;
  final List<String> userTagOptions;
  final List<String> otherTagOptions;
  final ValueChanged<List<String>> onRouteTagsChanged;
  final VoidCallback onSubmit;
  final VoidCallback onReset;
  final String selectionMode;

  const RouteFormStepper({
    super.key,
    required this.startLocationController,
    required this.endLocationController,
    required this.shortDescriptionController,
    required this.selectedRouteTags,
    required this.userTagOptions,
    required this.otherTagOptions,
    required this.onRouteTagsChanged,
    required this.onSubmit,
    required this.onReset,
    required this.selectionMode,
  });

  @override
  State<RouteFormStepper> createState() => _RouteFormStepperState();
}

class _RouteFormStepperState extends State<RouteFormStepper> {
  int _activeStep = 0;

  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _border = Color(0xFFD4E4F7);
  static const _warning = Color(0xFFFFB547);
  static const _danger = Color(0xFFE05C6A);

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
                  if (_activeStep > 0)
                    ElevatedButton(
                      onPressed: details.onStepCancel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7A92B2),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Back'),
                    ),
                  if (_activeStep > 0) const SizedBox(width: 8),
                  if (_activeStep < 2)
                    ElevatedButton(
                      onPressed: details.onStepContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Next'),
                    ),
                  if (_activeStep < 2) const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _clearBasicInfo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _danger,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),

              if (widget.selectionMode == 'done' && _activeStep == 2) ...[
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
        if (_activeStep < 2) {
          setState(() => _activeStep += 1);
        }
      },
      onStepCancel: () {
        if (_activeStep > 0) {
          setState(() => _activeStep -= 1);
        }
      },
      steps: [
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
            ],
          ),
          isActive: _activeStep >= 0,
        ),
        Step(
          title: const Text('Select Route Tags'),
          subtitle: const Text('Choose audience and route style'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'User Tags (Onboarding)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF67758D),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.userTagOptions.map((tag) {
                  final isSelected = widget.selectedRouteTags.contains(tag);
                  return FilterChip(
                    label: Text(tag),
                    selected: isSelected,
                    selectedColor: _accentSoft,
                    showCheckmark: false,
                    checkmarkColor: _accent,
                    labelStyle: TextStyle(
                      color: isSelected ? _accent : const Color(0xFF0F1D35),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    backgroundColor: const Color(0xFFEAF2FF),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: isSelected ? _accent.withOpacity(0.35) : _border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (selected) {
                      final next = List<String>.from(widget.selectedRouteTags);
                      if (selected) {
                        if (!next.contains(tag)) next.add(tag);
                      } else {
                        next.remove(tag);
                      }
                      widget.onRouteTagsChanged(next);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Other Tags',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                         color: const Color(0xFF67758D),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.otherTagOptions.map((tag) {
                  final isSelected = widget.selectedRouteTags.contains(tag);
                  return FilterChip(
                    label: Text(tag),
                    selected: isSelected,
                    selectedColor: _accentSoft,
                    showCheckmark: false,
                    checkmarkColor: _accent,
                    labelStyle: TextStyle(
                      color: isSelected ? _accent : const Color(0xFF0F1D35),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    backgroundColor: const Color(0xFFEAF2FF),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: isSelected ? _accent.withOpacity(0.35) : _border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (selected) {
                      final next = List<String>.from(widget.selectedRouteTags);
                      if (selected) {
                        if (!next.contains(tag)) next.add(tag);
                      } else {
                        next.remove(tag);
                      }
                      widget.onRouteTagsChanged(next);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          isActive: _activeStep >= 1,
        ),
        Step(
          title: const Text('Short Description'),
          subtitle: const Text('Add a quick route summary'),
          content: Column(
            children: [
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
          isActive: _activeStep >= 2,
        ),
      ],
    );
  }

  void _clearBasicInfo() {
    widget.startLocationController.clear();
    widget.endLocationController.clear();
    widget.shortDescriptionController.clear();
    widget.onRouteTagsChanged(const []);
  }
}