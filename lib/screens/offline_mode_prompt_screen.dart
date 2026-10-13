import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class OfflineModePromptScreen extends StatelessWidget {
  const OfflineModePromptScreen({super.key});

  static const continueOfflineResult = 'continue_offline';

  static Color get _bg => AppColors.bg;
  static Color get _surface => AppColors.surface;
  static Color get _surfaceAlt => AppColors.surfaceAlt;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;
  static const _warn = Color(0xFFE89A3C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 15,
              color: _textSecondary,
            ),
          ),
        ),
        title: Text(
          'Offline Mode',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _warn.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _warn.withOpacity(0.25)),
                    ),
                    child: const Icon(
                      Icons.wifi_off_rounded,
                      size: 36,
                      color: _warn,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Internet Connection',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You are currently offline. Continue to Offline Mode to view downloaded routes.',
                    style: TextStyle(color: _textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(continueOfflineResult);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.download_for_offline_rounded),
                      label: const Text('Continue to Offline Mode'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textSecondary,
                        side: BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
