import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../services/post_actions_service.dart';
import 'feed_colors.dart';
import 'feed_dialog_widgets.dart';

/// Dialog that lets users report a post with a predefined reason.
class ReportPostDialog extends StatefulWidget {
  final Post post;

  const ReportPostDialog({super.key, required this.post});

  @override
  State<ReportPostDialog> createState() => _ReportPostDialogState();
}

class _ReportPostDialogState extends State<ReportPostDialog> {
  static const _reasons = [
    'Spam',
    'Inappropriate Content',
    'Harassment',
    'Misinformation',
    'Other',
  ];

  static const _other = 'Other';

  String? _selectedReason;
  // What the rider types when they pick Other. Staff need it to know what
  // the problem is.
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  bool get _canReport {
    final reason = _selectedReason;
    if (reason == null) return false;
    return reason != _other || _otherController.text.trim().isNotEmpty;
  }

  /// The saved reason. Other becomes "Other: (what they typed)".
  String get _reportReason {
    final reason = _selectedReason!;
    if (reason != _other) return reason;
    return '$_other: ${_otherController.text.trim()}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: FeedColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: FeedColors.border),
          boxShadow: [
            BoxShadow(
              color: FeedColors.accent.withOpacity(0.08),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FeedDialogHeader(
              icon: Icons.flag_outlined,
              title: 'Report Post',
              iconBg: FeedColors.danger.withOpacity(0.1),
              iconColor: FeedColors.danger,
            ),
            // Scrolls so the text box stays reachable above the keyboard.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why are you reporting this post?',
                      style: TextStyle(
                        color: FeedColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._reasons.map(
                      (reason) => _ReasonOption(
                        reason: reason,
                        isSelected: _selectedReason == reason,
                        onTap: () => setState(() => _selectedReason = reason),
                      ),
                    ),
                    if (_selectedReason == _other)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextField(
                          controller: _otherController,
                          autofocus: true,
                          maxLines: 3,
                          minLines: 2,
                          maxLength: 200,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(
                            color: FeedColors.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: "Tell us what's wrong with this post",
                            hintStyle: TextStyle(
                              color: FeedColors.textSecondary,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: FeedColors.surface,
                            contentPadding: const EdgeInsets.all(12),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: FeedColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: FeedColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: FeedDialogCancelButton(
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FeedDialogDangerButton(
                      label: 'Report',
                      onTap:
                          !_canReport
                              ? null
                              : () {
                                PostActionsService.reportPost(
                                  widget.post,
                                  _reportReason,
                                  // The real rider, so "can't report your
                                  // own post" and account deletion work.
                                  FirebaseAuth.instance.currentUser?.uid ?? '',
                                );
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Post reported for moderation',
                                    ),
                                  ),
                                );
                              },
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

class _ReasonOption extends StatelessWidget {
  final String reason;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReasonOption({
    required this.reason,
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
          color: isSelected ? FeedColors.accentSoft : FeedColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? FeedColors.accent : FeedColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      isSelected ? FeedColors.accent : FeedColors.textSecondary,
                  width: 2,
                ),
                color: isSelected ? FeedColors.accent : Colors.transparent,
              ),
              child:
                  isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 10)
                      : null,
            ),
            const SizedBox(width: 10),
            Text(
              reason,
              style: TextStyle(
                color:
                    isSelected
                        ? FeedColors.textPrimary
                        : FeedColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
