part of 'moderator_screen.dart';

/// Riders' appeals against a ban or restriction, shown at the top of the
/// Feedback tab. Moderators decide restriction appeals; ban appeals are
/// for a superadmin (the Firestore rules say the same).
extension _ModeratorScreenAppeals on _ModeratorScreenState {
  static Color get _surfaceAlt => _ModeratorScreenState._surfaceAlt;
  static const _accent = _ModeratorScreenState._accent;
  static Color get _textPrimary => _ModeratorScreenState._textPrimary;
  static Color get _textSecondary => _ModeratorScreenState._textSecondary;
  static Color get _border => _ModeratorScreenState._border;
  static const _danger = _ModeratorScreenState._danger;
  static const _success = _ModeratorScreenState._success;
  static const _warning = _ModeratorScreenState._warning;

  // Decided appeals stay listed for a while so staff can see what was done,
  // but only the latest few, or the list grows forever.
  static const _decidedShown = 10;

  /// The appeals section's rows: a heading, then one card per appeal.
  /// Empty when no appeal matches [filter]. Pending shows waiting appeals,
  /// Resolved shows decided ones (lifted or upheld), Dismissed shows none.
  List<Widget> _appealRows(feedback_model.FeedbackStatus? filter) {
    final showWaiting =
        filter == null || filter == feedback_model.FeedbackStatus.pending;
    final showDecided =
        filter == null || filter == feedback_model.FeedbackStatus.resolved;
    final waiting =
        showWaiting
            ? _appeals.where((a) => a.status == AppealStatus.pending).toList()
            : const <Appeal>[];
    final decided =
        showDecided
            ? _appeals
                .where((a) => a.status != AppealStatus.pending)
                .take(_decidedShown)
                .toList()
            : const <Appeal>[];
    if (waiting.isEmpty && decided.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        child: Text(
          waiting.isEmpty ? 'Appeals' : 'Appeals (${waiting.length} waiting)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
        ),
      ),
      for (final appeal in [...waiting, ...decided]) _appealCard(appeal),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        child: Text(
          'Feedback',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
        ),
      ),
    ];
  }

  Widget _appealCard(Appeal appeal) {
    final waiting = appeal.status == AppealStatus.pending;
    final statusColor =
        waiting
            ? _warning
            : appeal.status == AppealStatus.lifted
            ? _success
            : _textSecondary;
    final statusLabel =
        waiting
            ? 'waiting'
            : appeal.status == AppealStatus.lifted
            ? 'lifted'
            : 'upheld';
    // Moderators can't lift a ban, so they don't decide ban appeals.
    final canDecide =
        waiting &&
        (!appeal.isBan || ModerationService.isSuperAdminNotifier.value);
    // Never the email: moderators shouldn't see riders' emails here.
    final who = appeal.userName.isNotEmpty ? appeal.userName : 'Rider';

    return _panelCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    appeal.isBan ? Icons.block_rounded : Icons.gpp_bad_rounded,
                    size: 16,
                    color: _danger,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    appeal.isBan ? 'Ban appeal' : 'Restriction appeal',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _metaChip(Icons.person_outline, who, _accent),
                if (appeal.createdAt != null)
                  _metaChip(
                    Icons.schedule_outlined,
                    _formatDate(appeal.createdAt!),
                    _textSecondary,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              appeal.reasonLabel.isEmpty
                  ? 'No reason was recorded for this lockout.'
                  : 'Reason given: ${appeal.reasonLabel}'
                      '${appeal.note.isEmpty ? '' : ' — ${appeal.note}'}',
              style: TextStyle(
                fontSize: 12,
                color: _textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Text(
                appeal.message,
                style: TextStyle(
                  fontSize: 13,
                  color: _textPrimary,
                  height: 1.35,
                ),
              ),
            ),
            if (appeal.reply.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Reply: ${appeal.reply}',
                style: TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            if (waiting && !canDecide) ...[
              const SizedBox(height: 10),
              Text(
                'Only a superadmin can decide ban appeals.',
                style: TextStyle(fontSize: 12, color: _textSecondary),
              ),
            ],
            if (canDecide) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _actionButton(
                    label: appeal.isBan ? 'Lift ban' : 'Lift restriction',
                    color: _success,
                    filled: true,
                    lockItem: 'appeal:${appeal.id}',
                    onTap: () => _decideAppeal(appeal, lift: true),
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    label: 'Uphold',
                    color: _danger,
                    lockItem: 'appeal:${appeal.id}',
                    onTap: () => _decideAppeal(appeal, lift: false),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 1. Asks staff to confirm, with an optional reply (shown to the rider
  /// when the decision is kept). 2. Saves the decision. 3. Says whether it
  /// worked.
  Future<void> _decideAppeal(Appeal appeal, {required bool lift}) async {
    final reply = await _askAppealReply(lift: lift);
    if (reply == null) return;
    final saved = await LockoutService.decide(appeal, lift: lift, reply: reply);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !saved
              ? 'Couldn\'t save that. Check your connection and try again.'
              : lift
              ? 'Lifted. The rider can sign in again.'
              : 'Upheld. The rider will see it next time they open the app.',
        ),
      ),
    );
  }

  /// The reply to send with the decision, '' for none, or null when
  /// staff cancelled.
  Future<String?> _askAppealReply({required bool lift}) {
    var reply = '';
    return showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: _ModeratorScreenState._surface,
            title: Text(
              lift ? 'Lift and let them back in?' : 'Keep the decision?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lift
                      ? 'The rider can sign in again right away.'
                      : 'The rider stays locked out and sees that their appeal was reviewed.',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
                if (!lift) ...[
                  const SizedBox(height: 12),
                  TextField(
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    onChanged: (value) => reply = value,
                    style: TextStyle(fontSize: 13, color: _textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Reply to the rider (optional)',
                      hintStyle: TextStyle(color: _textSecondary),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('Cancel', style: TextStyle(color: _textSecondary)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: lift ? _success : _danger,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(reply.trim()),
                child: Text(
                  lift ? 'Lift' : 'Uphold',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }
}
