import 'package:flutter/material.dart';

import '../../models/route.dart' as route_model;
import '../../theme/app_colors.dart';

/// Asks why a moderator is approving a route the checks flagged. The answer goes
/// on the route's record. Returns the note, or null when cancelled.
Future<String?> showApproveNoteDialog(
  BuildContext context, {
  required List<route_model.RouteCheck> flagged,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ApproveNoteDialog(flagged: flagged),
  );
}

class _ApproveNoteDialog extends StatefulWidget {
  final List<route_model.RouteCheck> flagged;

  const _ApproveNoteDialog({required this.flagged});

  @override
  State<_ApproveNoteDialog> createState() => _ApproveNoteDialogState();
}

class _ApproveNoteDialogState extends State<_ApproveNoteDialog> {
  final _controller = TextEditingController();

  String get _note => _controller.text.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Approve over a flag?',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final check in widget.flagged)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  check.message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              maxLines: 2,
              maxLength: 300,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Why is it OK to approve? (required)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _note.isEmpty ? null : () => Navigator.of(context).pop(_note),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}
