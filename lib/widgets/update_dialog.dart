import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_checker.dart';

/// Shows an update dialog when a new version of TransitPH is available.
///
/// On Android the APK is downloaded directly inside the app with a progress
/// indicator, then handed to the system package installer via [OpenFile].
/// On iOS the App Store link is opened in [url_launcher] instead, since
/// sideloading is not supported on that platform.
class UpdateDialog {
  UpdateDialog._();

  /// Runs an update check and, if an update is available, presents the dialog.
  static Future<void> checkAndShow(BuildContext context) async {
    final info = await UpdateChecker.checkForUpdate();
    if (!info.updateAvailable) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => _UpdateAlertDialog(info: info),
    );
  }
}

// ── Download state machine ────────────────────────────────────────────────────

enum _DownloadState { idle, downloading, error }

// ── Widget ───────────────────────────────────────────────────────────────────

class _UpdateAlertDialog extends StatefulWidget {
  const _UpdateAlertDialog({required this.info});
  final UpdateInfo info;

  @override
  State<_UpdateAlertDialog> createState() => _UpdateAlertDialogState();
}

class _UpdateAlertDialogState extends State<_UpdateAlertDialog> {
  _DownloadState _state = _DownloadState.idle;
  double _progress = 0.0; // 0.0 – 1.0
  String? _errorMessage;
  CancelToken? _cancelToken;

  // ── Download & install ────────────────────────────────────────────────────

  Future<void> _startDownload() async {
    // iOS cannot sideload APKs — open the App Store URL instead.
    if (Platform.isIOS) {
      await _openUrl();
      return;
    }

    // Android 8.0+ (API 26) requires the user to grant "Install unknown apps"
    // before the system installer will accept our APK.
    final installPerm = await Permission.requestInstallPackages.request();
    if (!installPerm.isGranted) {
      if (mounted) {
        setState(() {
          _state = _DownloadState.error;
          _errorMessage =
              'Install permission was denied.\n\n'
              'Please enable "Install unknown apps" for TransitPH in your '
              'device Settings, then try again.';
        });
      }
      return;
    }

    setState(() {
      _state = _DownloadState.downloading;
      _progress = 0.0;
      _errorMessage = null;
    });

    try {
      // Prefer external app-private storage (Android/data/<pkg>/files/).
      // No WRITE_EXTERNAL_STORAGE permission is needed here on API 29+.
      final dir =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final savePath = '${dir.path}/transitph_update.apk';

      _cancelToken = CancelToken();

      await Dio().download(
        widget.info.updateUrl,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );

      if (!mounted) return;

      // Hand the downloaded APK to the system package installer.
      final result = await OpenFile.open(savePath);
      if (result.type != ResultType.done && mounted) {
        setState(() {
          _state = _DownloadState.error;
          _errorMessage = 'Could not open the installer: ${result.message}';
        });
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // User deliberately cancelled — return to idle so they can retry.
        if (mounted) setState(() => _state = _DownloadState.idle);
      } else if (mounted) {
        setState(() {
          _state = _DownloadState.error;
          _errorMessage = 'Download failed: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _DownloadState.error;
          _errorMessage = 'Unexpected error: $e';
        });
      }
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('User cancelled download');
  }

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(widget.info.updateUrl);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link.')));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block the Back button while force-updating or actively downloading.
      canPop:
          !widget.info.forceUpdate && _state != _DownloadState.downloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.system_update_rounded, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'TransitPH Update Available',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: _buildContent(),
        actions: _buildActions(),
      ),
    );
  }

  // ── Content per state ─────────────────────────────────────────────────────

  Widget _buildContent() {
    switch (_state) {
      case _DownloadState.idle:
        return Text(
          widget.info.updateMessage.isNotEmpty
              ? widget.info.updateMessage
              : 'A new version of TransitPH is available. Update now to enjoy '
                  'the latest features and improvements.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        );

      case _DownloadState.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Downloading update…',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey.shade200,
                color: Colors.blue.shade700,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

      case _DownloadState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                color: Colors.red.shade600, size: 38),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An unexpected error occurred.',
              style: const TextStyle(fontSize: 13, height: 1.45),
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }

  // ── Actions per state ─────────────────────────────────────────────────────

  List<Widget> _buildActions() {
    switch (_state) {
      case _DownloadState.idle:
        return [
          if (!widget.info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Update'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _startDownload,
          ),
        ];

      case _DownloadState.downloading:
        return [
          TextButton(
            onPressed: _cancelDownload,
            child: const Text('Cancel'),
          ),
        ];

      case _DownloadState.error:
        return [
          if (!widget.info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _startDownload,
          ),
        ];
    }
  }
}

