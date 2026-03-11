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

// ─── Shared dialog header ────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  final Widget icon;
  final String title;

  const _DialogHeader({required this.icon, required this.title});

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
          Text(
            title,
            style: const TextStyle(
              color: ContributeColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

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

Widget _styledTextField({
  required String label,
  required String hint,
  required IconData icon,
  required ValueChanged<String> onChanged,
  int maxLines = 1,
}) {
  return Container(
    decoration: BoxDecoration(
      color: ContributeColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ContributeColors.border),
    ),
    child: TextField(
      maxLines: maxLines,
      style: const TextStyle(color: ContributeColors.textPrimary, fontSize: 14),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: ContributeColors.textSecondary, fontSize: 13),
        hintStyle: const TextStyle(color: ContributeColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: ContributeColors.accent, size: 18),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
      ),
    ),
  );
}

// ─── Mode Selection Dialog ────────────────────────────────────────────────────

class ModeSelectionDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return _dialogContainer(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogHeader(
            icon: _iconBox(color: ContributeColors.accent, icon: Icons.alt_route),
            title: 'Select Transport Mode',
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: modes.map((mode) => _ModeTile(
                  mode: mode,
                  color: modeColors[mode] ?? ContributeColors.accent,
                  icon: getModeIcon(mode),
                  isSelected: mode == currentMode,
                  onTap: () {
                    Navigator.pop(context);
                    onModeSelected(mode);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Tap on the map to select the next point for $mode',
                        ),
                      ),
                    );
                  },
                )).toList(),
              ),
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
          color: isSelected ? color.withOpacity(0.08) : ContributeColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.4) : ContributeColors.border,
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

// ─── Step Dialog ─────────────────────────────────────────────────────────────

class StepDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    String instruction = '';
    String details = '';
    final modeColor = modeColors[mode] ?? ContributeColors.accent;

    return _dialogContainer(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogHeader(
            icon: _iconBox(color: modeColor, icon: getModeIcon(mode)),
            title: 'Step: $mode',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _styledTextField(
                  hint: 'e.g., Ride a jeep with Cubao terminal',
                  label: 'Instruction',
                  icon: Icons.info_outline,
                  maxLines: 2,
                  onChanged: (v) => instruction = v,
                ),
                const SizedBox(height: 10),
                _styledTextField(
                  hint: 'e.g., Drop off at Gateway Mall',
                  label: 'Details',
                  icon: Icons.location_on_outlined,
                  maxLines: 2,
                  onChanged: (v) => details = v,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: _ghostButton(
                    label: 'Cancel',
                    onTap: () {
                      Navigator.pop(context);
                      onCancel();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _gradientButton(
                    label: 'Save Step',
                    icon: Icons.check_rounded,
                    onTap: () {
                      Navigator.pop(context);
                      onSaved(route_model.Step(
                        mode: mode,
                        instruction: instruction,
                        details: details,
                      ));
                    },
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

// ─── Add Another Step Dialog ─────────────────────────────────────────────────

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
