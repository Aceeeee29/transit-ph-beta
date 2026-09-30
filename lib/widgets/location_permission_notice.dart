import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'translated_text.dart';

/// Makes sure TransitPH can read the device location before a feature that
/// needs it, and returns whether it can.
///
/// While the OS can still show its own permission prompt, this shows it again
/// on every call, so a user who tapped "Don't allow" once gets asked the next
/// time they use a location feature. Once the OS stops prompting (permanently
/// denied) or the phone's location is switched off, it shows an in-app dialog
/// that leads to the right Settings page, so the user is never stuck without a
/// way back in. [reason] finishes the sentence "TransitPH needs your location
/// to ...".
Future<bool> ensureLocationAccess(
  BuildContext context, {
  required String reason,
}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) {
        await _showLocationDialog(
          context,
          title: 'Turn on location',
          message:
              'Your phone\'s location is switched off. TransitPH needs your '
              'location to $reason.',
          actionLabel: 'Turn on',
          onAction: Geolocator.openLocationSettings,
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Android never reports a permanent denial from checkPermission; after
      // two "Don't allow"s it still says denied, and requestPermission then
      // returns deniedForever without showing anything. Time the request to
      // tell that silent refusal apart from the user answering the prompt.
      final stopwatch = Stopwatch()..start();
      permission = await Geolocator.requestPermission();
      stopwatch.stop();
      final osShowedPrompt =
          stopwatch.elapsed >= _minPromptAnswerTime && !_osStoppedPrompting;
      if (permission == LocationPermission.deniedForever) {
        _osStoppedPrompting = true;
      }
      // If the user just said no to the OS prompt, respect that for now
      // instead of stacking a second dialog on top; the next location action
      // asks again.
      if (permission != LocationPermission.deniedForever || osShowedPrompt) {
        return _isGranted(permission);
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        await _showLocationDialog(
          context,
          title: 'Location permission is off',
          message:
              'TransitPH needs your location to $reason. Your phone will no '
              'longer ask for it, so turn it on in Settings under '
              'Permissions > Location.',
          actionLabel: 'Open Settings',
          onAction: Geolocator.openAppSettings,
        );
      }
      return false;
    }

    return _isGranted(permission);
  } catch (e) {
    debugPrint('ensureLocationAccess failed: $e');
    return false;
  }
}

/// Nobody reads and answers the OS prompt faster than this, so a quicker
/// deniedForever means the OS refused on its own without showing it.
const _minPromptAnswerTime = Duration(milliseconds: 600);

/// Set once the OS has refused permanently in this app session, so a slow
/// phone that takes longer than [_minPromptAnswerTime] to refuse silently
/// still gets the Settings dialog on the next try.
bool _osStoppedPrompting = false;

bool _isGranted(LocationPermission permission) =>
    permission == LocationPermission.whileInUse ||
    permission == LocationPermission.always;

Future<void> _showLocationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  required Future<bool> Function() onAction,
}) async {
  // Screens call this from initState; wait for the first frame so the
  // dialog isn't pushed while the screen's own route is still being built.
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          icon: const Icon(Icons.location_off_rounded),
          title: TranslatedText(title),
          content: TranslatedText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const TranslatedText('Not now'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onAction();
              },
              child: TranslatedText(actionLabel),
            ),
          ],
        ),
  );
}
