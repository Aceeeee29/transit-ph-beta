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
  final VoidCallback? onSubmitForReviewInstead;
  final VoidCallback? onCreateQuickLink;
  final VoidCallback onReset;
  final String selectionMode;
  final bool quickCreateMode;

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
    this.onSubmitForReviewInstead,
    this.onCreateQuickLink,
    required this.onReset,
    required this.selectionMode,
    this.quickCreateMode = false,
  });

  @override
  State<RouteFormStepper> createState() => _RouteFormStepperState();
}

class _RouteFormStepperState extends State<RouteFormStepper> {
  int _activeStep = 0;

  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _border = Color(0xFFD4E4F7);
  static const _warning = Color(0xFFFFB547);
  static const _danger = Color(0xFFE05C6A);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);

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
                    onPressed: _clearCurrentStep,
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
                      Expanded(
                        child: Text(
                          widget.quickCreateMode
                              ? 'This route is temporary and expires automatically after 24 hours.'
                              : 'Your route will be reviewed by a moderator before it appears publicly.',
                          style: const TextStyle(
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

                ElevatedButton.icon(
                  onPressed: (widget.quickCreateMode &&
                          widget.onSubmitForReviewInstead != null)
                      ? widget.onSubmitForReviewInstead
                      : widget.onSubmit,
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

                if (widget.quickCreateMode && widget.onSubmitForReviewInstead != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: widget.onSubmit,
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text('Use This Link: Quick Create (24h)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withOpacity(0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],

                if (!widget.quickCreateMode && widget.onCreateQuickLink != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: widget.onCreateQuickLink,
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Generate 24h Quick Link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withOpacity(0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
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
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                ),
                decoration: _buildInputDecoration(
                  label: 'Starting Location (tap map to select or type)',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.endLocationController,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                ),
                decoration: _buildInputDecoration(
                  label: 'End Location (tap map to select or type)',
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
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                ),
                decoration: _buildInputDecoration(
                  label: 'Short Description',
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

  void _clearCurrentStep() {
    switch (_activeStep) {
      case 0:
        widget.startLocationController.clear();
        widget.endLocationController.clear();
        break;
      case 1:
        widget.onRouteTagsChanged(const []);
        break;
      case 2:
        widget.shortDescriptionController.clear();
        break;
    }
  }

  InputDecoration _buildInputDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: _textSecondary,
        fontSize: 12,
      ),
      floatingLabelStyle: const TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: _surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }
}