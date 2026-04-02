import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _RouteGenerationNoticeAction { cancel, confirm, dontAskSevenDays }

class RouteGenerationNoticeDialog {
  static const _skipUntilKey = 'route_accuracy_prompt_skip_until_ms';

  static const _surface = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  static Future<bool> shouldProceed(BuildContext context) async {
    final shouldShowPrompt = await _shouldShowPrompt();
    if (!shouldShowPrompt) return true;
    if (!context.mounted) return false;

    final action = await _show(context);
    if (action == _RouteGenerationNoticeAction.cancel) {
      return false;
    }
    if (action == _RouteGenerationNoticeAction.dontAskSevenDays) {
      await _skipForSevenDays();
    }
    return true;
  }

  static Future<bool> _shouldShowPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final skipUntilMs = prefs.getInt(_skipUntilKey);
    if (skipUntilMs == null) return true;
    return DateTime.now().millisecondsSinceEpoch >= skipUntilMs;
  }

  static Future<void> _skipForSevenDays() async {
    final prefs = await SharedPreferences.getInstance();
    final skipUntil = DateTime.now().add(const Duration(days: 7));
    await prefs.setInt(_skipUntilKey, skipUntil.millisecondsSinceEpoch);
  }

  static Future<_RouteGenerationNoticeAction> _show(BuildContext context) async {
    final action = await showDialog<_RouteGenerationNoticeAction>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.info_outline,
                          color: _accent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Generated Route Notice',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This generated route may be inaccurate because dataset availability can be limited. It is currently limited to Jeep, Bus, Train, and Walk routes only.\n\nDo you want to continue?',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(_RouteGenerationNoticeAction.cancel),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _border),
                            foregroundColor: _textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(_RouteGenerationNoticeAction.confirm),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text(
                            'Confirm',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(_RouteGenerationNoticeAction.dontAskSevenDays),
                      style: TextButton.styleFrom(
                        foregroundColor: _accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      child: const Text(
                        "Don't ask again (7 days)",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return action ?? _RouteGenerationNoticeAction.cancel;
  }
}
