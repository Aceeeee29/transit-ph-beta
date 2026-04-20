part of 'contribute_screen.dart';

class _QuickLinkDialog extends StatelessWidget {
  final String url;

  const _QuickLinkDialog({required this.url});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('24h Quick Link Created'),
      content: SelectableText(
        '$url\n\nThis link can be used for 24 hours only.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Copy Again'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _SubmitSuccessDialog extends StatelessWidget {
  final bool isEdit;
  final bool quickCreateMode;

  static const _bg = Color(0xFFF4F8FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _warning = Color(0xFFFFB547);
  static const _green = Color(0xFF3EC97A);

  const _SubmitSuccessDialog({
    required this.isEdit,
    this.quickCreateMode = false,
  });

  @override
  Widget build(BuildContext context) {
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
                color: isEdit
                    ? _green.withOpacity(0.12)
                    : _warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isEdit
                      ? _green.withOpacity(0.3)
                      : _warning.withOpacity(0.3),
                ),
              ),
              child: Icon(
                isEdit
                    ? Icons.check_circle_outline_rounded
                    : (quickCreateMode
                        ? Icons.bolt_rounded
                        : Icons.pending_actions_rounded),
                color: isEdit ? _green : _warning,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEdit
                  ? 'Route Updated'
                  : (quickCreateMode ? 'Quick Route Created' : 'Pending Review'),
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                isEdit
                    ? 'Your route has been updated successfully.'
                    : (quickCreateMode
                        ? 'This temporary route is now available via quick link and expires automatically in 24 hours.'
                        : 'Your route has been submitted and is awaiting moderator approval. It will appear publicly once approved.'),
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (!isEdit && !quickCreateMode) ...[
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
                      colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
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
          child: Text(
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
