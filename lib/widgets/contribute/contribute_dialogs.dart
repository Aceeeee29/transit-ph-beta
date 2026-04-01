import 'package:flutter/material.dart';
import '../../models/route.dart' as route_model;

// ─── Shared colors ────────────────────────────────────────────────────────────

class ContributeColors {
  static const bg = Color(0xFFF4F8FF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFEAF2FF);
  static const accent = Color(0xFF2E7CF6);
  static const accentSoft = Color(0x1A2E7CF6);
  static const textPrimary = Color(0xFF0F1D35);
  static const textSecondary = Color(0xFF7A92B2);
  static const border = Color(0xFFD4E4F7);
}

// ─── Shared dialog header ─────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  final Widget icon;
  final String title;
  final String? subtitle;

  const _DialogHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      decoration: const BoxDecoration(
        color: ContributeColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          bottom: BorderSide(color: ContributeColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ContributeColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: ContributeColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

Widget _iconBox({required Color color, required IconData icon}) {
  return Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, color: color, size: 16),
  );
}

Widget _dialogContainer(Widget child) {
  return Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      decoration: BoxDecoration(
        color: ContributeColors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ContributeColors.border),
        boxShadow: [
          BoxShadow(
            color: ContributeColors.accent.withOpacity(0.08),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    ),
  );
}

Widget _gradientButton({
  required String label,
  required IconData icon,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: ContributeColors.accent.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _ghostButton({required String label, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 44,
      decoration: BoxDecoration(
        color: ContributeColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ContributeColors.border),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: ContributeColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );
}

// ─── Mode Selection Dialog ────────────────────────────────────────────────────

class ModeSelectionDialog extends StatefulWidget {
  final String currentMode;
  final List<String> modes;
  final Map<String, Color> modeColors;
  final IconData Function(String) getModeIcon;
  final void Function(String mode) onModeSelected;

  const ModeSelectionDialog({
    super.key,
    required this.currentMode,
    required this.modes,
    required this.modeColors,
    required this.getModeIcon,
    required this.onModeSelected,
  });

  @override
  State<ModeSelectionDialog> createState() => _ModeSelectionDialogState();
}

class _ModeSelectionDialogState extends State<ModeSelectionDialog> {
  bool _showAdvancedModes = false;

  static const _advancedModes = {'Walk', 'Ferry'};

  @override
  Widget build(BuildContext context) {
    final visibleModes = widget.modes.where((mode) {
      if (_showAdvancedModes) return true;
      return !_advancedModes.contains(mode);
    }).toList();

    return _dialogContainer(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogHeader(
            icon: _iconBox(
                color: ContributeColors.accent, icon: Icons.alt_route),
            title: 'Select Transport Mode',
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: visibleModes
                    .map(
                      (mode) => _ModeTile(
                        mode: mode,
                        color: widget.modeColors[mode] ?? ContributeColors.accent,
                        icon: widget.getModeIcon(mode),
                        isSelected: mode == widget.currentMode,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onModeSelected(mode);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Tap on the map to select the next point for $mode',
                              ),
                            ),
                          );
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _ghostButton(
              label: _showAdvancedModes
                  ? 'Hide Advanced Modes (Walk / Ferry)'
                  : 'Show Advanced Modes (Walk / Ferry)',
              onTap: () {
                setState(() => _showAdvancedModes = !_showAdvancedModes);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String mode;
  final Color color;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeTile({
    required this.mode,
    required this.color,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.08)
              : ContributeColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected
                ? color.withOpacity(0.4)
                : ContributeColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 12),
            Text(
              mode,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? ContributeColors.textPrimary
                    : ContributeColors.textSecondary,
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              Icon(Icons.check_circle_rounded, color: color, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Step Dialog ──────────────────────────────────────────────────────────────

class StepDialog extends StatefulWidget {
  final String mode;
  final Map<String, Color> modeColors;
  final IconData Function(String) getModeIcon;
  final VoidCallback onCancel;
  final void Function(route_model.Step step) onSaved;

  const StepDialog({
    super.key,
    required this.mode,
    required this.modeColors,
    required this.getModeIcon,
    required this.onCancel,
    required this.onSaved,
  });

  @override
  State<StepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends State<StepDialog> {
  final _instructionController = TextEditingController();
  final _detailsController = TextEditingController();
  final _altRouteController = TextEditingController();
  final _actualFareController = TextEditingController();

  late bool _is24_7;
  TimeOfDay _startTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 22, minute: 0);

  static const _warn = Color(0xFFFFF8E1);
  static const _warnBorder = Color(0xFFFFD54F);
  static const _warnText = Color(0xFF7A5800);

  bool get _isMotorizedMode => widget.mode != 'Walk';

  @override
  void initState() {
    super.initState();
    _is24_7 = widget.mode == 'Walk';
  }

  @override
  void dispose() {
    _instructionController.dispose();
    _detailsController.dispose();
    _altRouteController.dispose();
    _actualFareController.dispose();
    super.dispose();
  }

  /// Converts [TimeOfDay] → "HH:mm" for storage.
  String _fmt24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _endBeforeStart =>
      (_endTime.hour * 60 + _endTime.minute) <=
      (_startTime.hour * 60 + _startTime.minute);

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: ContributeColors.accent,
            onPrimary: Colors.white,
            surface: ContributeColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  void _save() {
    final instruction = _instructionController.text.trim();
    final details = _detailsController.text.trim();
    final fareText = _actualFareController.text.trim();

    if (instruction.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Instruction is required.')),
      );
      return;
    }

    if (_isMotorizedMode && details.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Details are required for this transport mode.')),
      );
      return;
    }

    if (_isMotorizedMode && !_is24_7 && _endBeforeStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    double? actualFare;
    if (_isMotorizedMode) {
      if (fareText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Actual fare is required for this transport mode.')),
        );
        return;
      }
      actualFare = double.tryParse(fareText);
      if (actualFare == null || actualFare < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Actual fare must be a valid non-negative number.')),
        );
        return;
      }
    }

    final step = route_model.Step(
      mode: widget.mode,
      instruction: instruction,
      details: details,
      is24_7: _is24_7,
      startTime: _is24_7 ? null : _fmt24(_startTime),
      endTime: _is24_7 ? null : _fmt24(_endTime),
      actualFare: actualFare,
      alternateRouteSuggestion:
          (!_is24_7 && _altRouteController.text.trim().isNotEmpty)
              ? _altRouteController.text.trim()
              : null,
    );

    Navigator.of(context).pop();
    widget.onSaved(step);
  }

  @override
  Widget build(BuildContext context) {
    final modeColor =
        widget.modeColors[widget.mode] ?? ContributeColors.accent;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: ContributeColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ContributeColors.border),
          boxShadow: [
            BoxShadow(
              color: ContributeColors.accent.withOpacity(0.08),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────────
            _DialogHeader(
              icon: _iconBox(
                color: modeColor,
                icon: widget.getModeIcon(widget.mode),
              ),
              title: '${widget.mode} Step',
              subtitle: 'Add step details & schedule',
            ),

            // ── Scrollable body ───────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Instruction
                    const _FieldLabel(label: 'Instruction'),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _instructionController,
                      hint: 'e.g., Ride a jeep with Cubao terminal',
                      maxLines: 2,
                      prefixIcon: Icons.info_outline,
                    ),
                    const SizedBox(height: 12),

                    // Details
                    const _FieldLabel(label: 'Details'),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _detailsController,
                      hint: 'e.g., Drop off at Gateway Mall',
                      maxLines: 2,
                      prefixIcon: Icons.location_on_outlined,
                    ),
                    const SizedBox(height: 18),

                    const _FieldLabel(label: 'Actual Fare (PHP)'),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _actualFareController,
                      hint: _isMotorizedMode
                          ? 'e.g., 20'
                          : 'Optional for walk',
                      maxLines: 1,
                      prefixIcon: Icons.payments_outlined,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 18),

                    // Schedule header row
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Schedule',
                                style: TextStyle(
                                  color: ContributeColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Operating hours for this vehicle',
                                style: TextStyle(
                                  color: ContributeColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 24/7 toggle pill
                        GestureDetector(
                          onTap: () =>
                              setState(() => _is24_7 = !_is24_7),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _is24_7
                                  ? ContributeColors.accent
                                      .withOpacity(0.12)
                                  : ContributeColors.surfaceAlt,
                              borderRadius:
                                  BorderRadius.circular(10),
                              border: Border.all(
                                color: _is24_7
                                    ? ContributeColors.accent
                                        .withOpacity(0.4)
                                    : ContributeColors.border,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _is24_7
                                      ? Icons.all_inclusive_rounded
                                      : Icons.schedule_rounded,
                                  size: 14,
                                  color: _is24_7
                                      ? ContributeColors.accent
                                      : ContributeColors
                                          .textSecondary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _is24_7
                                      ? '24/7'
                                      : 'Limited hours',
                                  style: TextStyle(
                                    color: _is24_7
                                        ? ContributeColors.accent
                                        : ContributeColors
                                            .textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isMotorizedMode) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Set operating hours for this transport leg. 24/7 is allowed when applicable.',
                        style: TextStyle(
                          color: ContributeColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],

                    // Time range + alternate route — animated reveal
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: _is24_7
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),

                                // Opens / Closes row
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TimePicker(
                                        label: 'Opens',
                                        display:
                                            _startTime.format(context),
                                        onTap: () => _pickTime(
                                            isStart: true),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 16,
                                        color: ContributeColors
                                            .textSecondary,
                                      ),
                                    ),
                                    Expanded(
                                      child: _TimePicker(
                                        label: 'Closes',
                                        display:
                                            _endTime.format(context),
                                        onTap: () => _pickTime(
                                            isStart: false),
                                        hasError: _endBeforeStart,
                                      ),
                                    ),
                                  ],
                                ),

                                if (_endBeforeStart) ...[
                                  const SizedBox(height: 6),
                                  const Text(
                                    'End time must be after start time',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 11),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                // Alternate route suggestion card
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _warn,
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                        color: _warnBorder),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline_rounded,
                                            size: 14,
                                            color: _warnText,
                                          ),
                                          SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'This vehicle has limited hours',
                                              style: TextStyle(
                                                color: _warnText,
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Do you know an alternate vehicle or route riders can use outside these hours?',
                                        style: TextStyle(
                                          color: _warnText,
                                          fontSize: 11,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      _Field(
                                        controller:
                                            _altRouteController,
                                        hint:
                                            'e.g., Take the MRT-3 instead, or ride a tricycle to the next terminal',
                                        maxLines: 2,
                                        fillColor: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Footer ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: ContributeColors.surface,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(
                    top: BorderSide(color: ContributeColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ghostButton(
                      label: 'Cancel',
                      onTap: () {
                        widget.onCancel();
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _gradientButton(
                      label: 'Save Step',
                      icon: Icons.check_rounded,
                      onTap: _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Another Step Dialog ──────────────────────────────────────────────────

class AddStepDialog extends StatelessWidget {
  final int stepCount;
  final VoidCallback onAddAnother;
  final VoidCallback onFinished;

  const AddStepDialog({
    super.key,
    required this.stepCount,
    required this.onAddAnother,
    required this.onFinished,
  });

  @override
  Widget build(BuildContext context) {
    return _dialogContainer(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogHeader(
            icon: _iconBox(
              color: const Color(0xFF3EC97A),
              icon: Icons.check_circle_outline,
            ),
            title: 'Step Added',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ContributeColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ContributeColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: ContributeColors.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '$stepCount',
                        style: const TextStyle(
                          color: ContributeColors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'step${stepCount > 1 ? 's' : ''} added to this route',
                    style: const TextStyle(
                      color: ContributeColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                _gradientButton(
                  label: 'Add Another Step',
                  icon: Icons.add_rounded,
                  onTap: () {
                    Navigator.pop(context);
                    onAddAnother();
                  },
                ),
                const SizedBox(height: 8),
                _ghostButton(
                  label: 'Finish Route',
                  onTap: () {
                    Navigator.pop(context);
                    onFinished();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Private helper widgets ───────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          color: ContributeColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final IconData? prefixIcon;
  final Color? fillColor;
  final TextInputType? keyboardType;

  const _Field({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.prefixIcon,
    this.fillColor,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(
            color: ContributeColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              color: ContributeColors.textSecondary, fontSize: 12),
          filled: true,
          fillColor: fillColor ?? ContributeColors.surface,
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon,
                  size: 16, color: ContributeColors.textSecondary)
              : null,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: ContributeColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: ContributeColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: ContributeColors.accent, width: 1.5),
          ),
        ),
      );
}

class _TimePicker extends StatelessWidget {
  final String label;
  final String display;
  final VoidCallback onTap;
  final bool hasError;

  const _TimePicker({
    required this.label,
    required this.display,
    required this.onTap,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: ContributeColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasError ? Colors.red : ContributeColors.border,
              width: hasError ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 14,
                color: hasError
                    ? Colors.red
                    : ContributeColors.accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: ContributeColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      display,
                      style: TextStyle(
                        color: hasError
                            ? Colors.red
                            : ContributeColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}