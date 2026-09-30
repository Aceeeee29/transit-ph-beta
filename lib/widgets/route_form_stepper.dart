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

  /// Finishes drawing the route on the map. Submitting and quick links only
  /// unlock once the route is finished, so the Description step offers this
  /// directly instead of relying on the map's Finish pill, which the open
  /// form covers. Null when there is no step to finish yet.
  final VoidCallback? onFinishRoute;

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
    this.onFinishRoute,
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

  static const _stepTitles = ['Basic Info', 'Route Tags', 'Description'];

  void _setStep(int step) {
    if (step < 0 || step > 2 || _activeStep == step) return;
    setState(() => _activeStep = step);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepHeader(),
        const SizedBox(height: 14),
        _buildStepContent(),
        const SizedBox(height: 16),
        _buildControls(),
        if (_activeStep == 2) ...[
          const SizedBox(height: 12),
          widget.selectionMode == 'done'
              ? _buildSubmitSection()
              : _buildFinishRouteNotice(),
        ],
      ],
    );
  }

  Widget _buildFinishRouteNotice() {
    final canFinish = widget.onFinishRoute != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _accentSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _accent.withOpacity(0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 15, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  canFinish
                      ? 'Finish your route to submit it or share it as a quick link.'
                      : 'Add at least one step on the map, then finish your route to submit it or share it as a quick link.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (canFinish) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: widget.onFinishRoute,
            icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
            label: const Text(
              'Finish Route',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3EC97A),
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
    );
  }

  // ─── Step navigation header (jump straight to any of the 3 parts) ───────

  Widget _buildStepHeader() {
    return Row(
      children: [
        for (int i = 0; i < 3; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => _setStep(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: i == _activeStep ? _accentSoft : _surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: i == _activeStep
                        ? _accent.withOpacity(0.45)
                        : _border,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i <= _activeStep ? _accent : _border,
                        shape: BoxShape.circle,
                      ),
                      child: i < _activeStep
                          ? const Icon(Icons.check_rounded,
                              size: 12, color: Colors.white)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: i == _activeStep
                                    ? Colors.white
                                    : _textSecondary,
                              ),
                            ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _stepTitles[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: i == _activeStep
                              ? _accent
                              : _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 6),
        ],
      ],
    );
  }

  // ─── Active step content ────────────────────────────────────────────────

  Widget _buildStepContent() {
    switch (_activeStep) {
      case 0:
        return _buildBasicInfoStep();
      case 1:
        return _buildTagsStep();
      default:
        return _buildDescriptionStep();
    }
  }

  Widget _buildBasicInfoStep() {
    return Column(
      children: [
        TextFormField(
          controller: widget.startLocationController,
          style: const TextStyle(color: _textPrimary, fontSize: 13),
          decoration: _buildInputDecoration(
            label: 'Starting Location (tap map to select or type)',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.endLocationController,
          style: const TextStyle(color: _textPrimary, fontSize: 13),
          decoration: _buildInputDecoration(
            label: 'End Location (tap map to select or type)',
          ),
        ),
      ],
    );
  }

  Widget _buildTagsStep() {
    return Column(
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
            'Other Tags (pick one)',
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
                // Single-select within Other Tags; User Tags are untouched.
                final next =
                    widget.selectedRouteTags
                        .where((t) => !widget.otherTagOptions.contains(t))
                        .toList();
                if (selected) next.add(tag);
                widget.onRouteTagsChanged(next);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDescriptionStep() {
    return Column(
      children: [
        TextFormField(
          controller: widget.shortDescriptionController,
          style: const TextStyle(color: _textPrimary, fontSize: 13),
          decoration: _buildInputDecoration(label: 'Short Description'),
          maxLines: 2,
        ),
      ],
    );
  }

  // ─── Controls ───────────────────────────────────────────────────────────

  Widget _buildControls() {
    return Row(
      children: [
        if (_activeStep > 0)
          Expanded(
            child: ElevatedButton(
              onPressed: () => _setStep(_activeStep - 1),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7A92B2),
                foregroundColor: Colors.white,
              ),
              child: const Text('Back'),
            ),
          ),
        if (_activeStep > 0) const SizedBox(width: 8),
        if (_activeStep < 2)
          Expanded(
            child: ElevatedButton(
              onPressed: () => _setStep(_activeStep + 1),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Next'),
            ),
          ),
        if (_activeStep < 2) const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: _clearCurrentStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _warning.withOpacity(0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
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
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Prefer to keep this as a temporary route instead?',
              style: TextStyle(fontSize: 11, color: Color(0xFF7A92B2)),
            ),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider(height: 1, color: Color(0xFFD4E4F7))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'OPTIONAL · SHARE AS DRAFT',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: Color(0xFF7A92B2),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(child: Divider(height: 1, color: Color(0xFFD4E4F7))),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Create a 24-hour link without moderator review. '
              'Recipients open it as a temporary quick route.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: Color(0xFF7A92B2)),
            ),
          ),
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
      labelStyle: const TextStyle(color: _textSecondary, fontSize: 12),
      floatingLabelStyle: const TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: _surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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