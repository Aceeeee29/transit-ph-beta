import 'package:flutter/material.dart';

import '../../models/route_rejection_reason.dart';
import '../../theme/app_colors.dart';

typedef RejectChoice = ({List<String> codes, String? note});

/// Asks why a route is being rejected. The contributor reads the answer, so
/// it can't be confirmed without a reason. Returns null when cancelled.
Future<RejectChoice?> showRejectReasonsDialog(BuildContext context) {
  return showDialog<RejectChoice>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const _RejectReasonsDialog(),
  );
}

class _RejectReasonsDialog extends StatefulWidget {
  const _RejectReasonsDialog();

  @override
  State<_RejectReasonsDialog> createState() => _RejectReasonsDialogState();
}

class _RejectReasonsDialogState extends State<_RejectReasonsDialog> {
  static const _accent = Color(0xFF0B8FD6);
  static const _danger = Color(0xFFE05C6A);

  final Set<String> _picked = {};
  final TextEditingController _noteController = TextEditingController();

  String get _note => _noteController.text.trim();

  bool get _canConfirm {
    if (_picked.isEmpty) return false;
    final noteRequired = RouteRejectionReason.all.any(
      (reason) => reason.needsNote && _picked.contains(reason.code),
    );
    return !noteRequired || _note.isNotEmpty;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _toggle(String code) {
    setState(() {
      if (!_picked.remove(code)) _picked.add(code);
    });
  }

  void _confirm() {
    // Keep the list's own order, not the order they were tapped in.
    final codes =
        RouteRejectionReason.all
            .map((reason) => reason.code)
            .where(_picked.contains)
            .toList();
    Navigator.of(
      context,
    ).pop<RejectChoice>((codes: codes, note: _note.isEmpty ? null : _note));
  }

  @override
  Widget build(BuildContext context) {
    final noteRequired = _picked.contains('other');
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reject this route?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The contributor sees these reasons and can fix the route and '
              'send it again.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in RouteRejectionReason.all)
                  _ReasonChip(
                    label: reason.label,
                    selected: _picked.contains(reason.code),
                    onTap: () => _toggle(reason.code),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              onChanged: (_) => setState(() {}),
              maxLines: 2,
              maxLength: 300,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText:
                    noteRequired
                        ? 'Say what the problem is (required)'
                        : 'Add a note (optional)',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _accent),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canConfirm ? _confirm : null,
                  style: FilledButton.styleFrom(backgroundColor: _danger),
                  child: const Text(
                    'Reject route',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  static const _danger = Color(0xFFE05C6A);

  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? _danger.withValues(alpha: 0.12) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _danger : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? _danger : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
