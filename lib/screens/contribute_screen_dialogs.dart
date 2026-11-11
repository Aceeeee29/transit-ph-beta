part of 'contribute_screen.dart';

class _QuickLinkDialog extends StatelessWidget {
  final String url;

  const _QuickLinkDialog({required this.url});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const TranslatedText('24h Quick Link Created'),
      content: SelectableText(
        '$url\n\nThis link can be used for 24 hours only.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const TranslatedText('Copy Again'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const TranslatedText('Done'),
        ),
      ],
    );
  }
}

/// The automatic checks rejected this route. It's already saved as rejected,
/// so the rider fixes it now (true, the drawing stays) or later from Profile
/// (false, the editor closes).
class _RouteRejectedDialog extends StatelessWidget {
  final List<route_model.RouteCheck> checks;

  const _RouteRejectedDialog({required this.checks});

  static const _danger = Color(0xFFE05C6A);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: TranslatedText(
        'This route was rejected',
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
            for (final check in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: _danger,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TranslatedText(
                        check.message,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TranslatedText(
              "It's saved in your Profile as rejected. Fix it here and send it "
              'again, or fix it later from your Profile.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const TranslatedText('Fix later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const TranslatedText('Fix it now'),
        ),
      ],
    );
  }
}

class _SubmitSuccessDialog extends StatelessWidget {
  final bool isEdit;
  final bool quickCreateMode;

  /// What the automatic checks decided. Null for quick routes, which skip them.
  final RouteSubmitResult? result;

  static Color get _bg => AppColors.bg;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;
  static const _warning = Color(0xFFFFB547);
  static const _green = Color(0xFF3EC97A);

  const _SubmitSuccessDialog({
    required this.isEdit,
    this.quickCreateMode = false,
    this.result,
  });

  bool get _done => (result?.isLive ?? false) || (result?.isApplied ?? false);

  String get _title {
    if (result?.isLive ?? false) return 'Your Route Is Live';
    if (result?.isApplied ?? false) return 'Fare Updated';
    if (isEdit) return 'Edit Sent for Review';
    return quickCreateMode ? 'Quick Route Created' : 'Pending Review';
  }

  String get _body {
    if (result?.isLive ?? false) {
      return 'It passed the automatic checks, so riders can see it now. It shows as Unverified until riders or a moderator confirm it.';
    }
    if (result?.isApplied ?? false) {
      return 'The new fare is in the usual range, so it was added to the route right away.';
    }
    if (isEdit) {
      return 'A moderator will review your changes. Until they approve them, the route is hidden from other riders.';
    }
    return quickCreateMode
        ? 'This temporary route is now available via quick link and expires automatically in 24 hours.'
        : 'A moderator needs to look at this before it goes live.';
  }

  @override
  Widget build(BuildContext context) {
    final flagged = result?.flagged ?? const <route_model.RouteCheck>[];
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.08),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 28),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color:
                    isEdit || _done
                        ? _green.withOpacity(0.12)
                        : _warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      isEdit || _done
                          ? _green.withOpacity(0.3)
                          : _warning.withOpacity(0.3),
                ),
              ),
              child: Icon(
                isEdit || _done
                    ? Icons.check_circle_outline_rounded
                    : (quickCreateMode
                        ? Icons.bolt_rounded
                        : Icons.pending_actions_rounded),
                color: isEdit || _done ? _green : _warning,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            TranslatedText(
              _title,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TranslatedText(
                _body,
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (flagged.isNotEmpty) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final check in flagged)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.flag_outlined,
                                size: 14,
                                color: _warning,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TranslatedText(
                                check.message,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (!isEdit && !quickCreateMode && !_done) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _warning.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      _step(
                        icon: Icons.check_circle_rounded,
                        color: _green,
                        label: 'Route submitted',
                        done: true,
                      ),
                      const SizedBox(height: 10),
                      _step(
                        icon: Icons.shield_outlined,
                        color: _warning,
                        label: 'Awaiting moderator review',
                        done: false,
                      ),
                      const SizedBox(height: 10),
                      _step(
                        icon: Icons.public_rounded,
                        color: _textSecondary,
                        label: 'Goes live after approval',
                        done: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B8FD6), Color(0xFF2BB5F0)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Got it',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step({
    required IconData icon,
    required Color color,
    required String label,
    required bool done,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: TranslatedText(
            label,
            style: TextStyle(
              fontSize: 13,
              color: done ? _textPrimary : _textSecondary,
              fontWeight: done ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
