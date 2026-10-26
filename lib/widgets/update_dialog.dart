import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_checker.dart';
import '../theme/app_colors.dart';

/// Shows an update dialog when a new version of TransitPH is available.
///
/// On Android the APK is downloaded directly inside the app with a progress
/// indicator, then handed to the system package installer via [OpenFile].
/// On iOS the App Store link is opened in [url_launcher] instead, since
/// sideloading is not supported on that platform.
class UpdateDialog {
  UpdateDialog._();

  static bool _checkedThisRun = false;

  /// Runs an update check and, if an update is available, presents the
  /// dialog. Once per app run, however often the main screen is rebuilt.
  static Future<void> checkAndShow(BuildContext context) async {
    if (_checkedThisRun) return;
    _checkedThisRun = true;
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

  // Set before the install-permission check, which can return before the
  // button changes: a quick second tap started a second download into the
  // same file.
  bool _isStarting = false;

  Future<void> _startDownload() async {
    if (_isStarting || _state == _DownloadState.downloading) return;
    _isStarting = true;
    try {
      await _download();
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _download() async {
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

      final dio = Dio();
      dio.options.followRedirects = true;
      dio.options.maxRedirects = 5;

      await dio.download(
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

      // Validate that the downloaded file is actually an APK (ZIP archive).
      final file = File(savePath);
      if (!await _isValidApk(file)) {
        if (mounted) {
          setState(() {
            _state = _DownloadState.error;
            _errorMessage =
                'The downloaded file is not a valid APK.\n\n'
                'The download link may be broken or redirecting to a web page '
                'instead of the actual file. Please check the update URL.';
          });
        }
        // Clean up the invalid file.
        try {
          await file.delete();
        } catch (_) {}
        return;
      }

      // Hand the downloaded APK to the system package installer.
      final result = await OpenFilex.open(
        savePath,
        type: 'application/vnd.android.package-archive',
      );
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

  /// Returns `true` if [file] starts with the ZIP/APK magic bytes (`PK\x03\x04`).
  static Future<bool> _isValidApk(File file) async {
    try {
      if (!await file.exists()) return false;
      final raf = await file.open(mode: FileMode.read);
      final header = await raf.read(4);
      await raf.close();
      // APK files are ZIP archives — the magic number is PK\x03\x04.
      return header.length == 4 &&
          header[0] == 0x50 && // P
          header[1] == 0x4B && // K
          header[2] == 0x03 &&
          header[3] == 0x04;
    } catch (_) {
      return false;
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
      canPop: !widget.info.forceUpdate && _state != _DownloadState.downloading,
      child: Dialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Update available',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Long release notes scroll instead of pushing the buttons
              // off the screen.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SingleChildScrollView(child: _buildContent()),
              ),
              const SizedBox(height: 20),
              _buildActions(),
            ],
          ),
        ),
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
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.5,
          ),
        );

      case _DownloadState.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloading update…',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: AppColors.surfaceAlt,
                color: AppColors.accent,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: AppColors.textSecondary,
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
            Icon(
              Icons.error_outline_rounded,
              color: Colors.red.shade600,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An unexpected error occurred.',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }

  // ── Actions per state ─────────────────────────────────────────────────────

  /// Side by side, equal widths, so neither can run off the dialog.
  Widget _buildActions() {
    final (secondary, primary) = switch (_state) {
      _DownloadState.idle => (
        widget.info.forceUpdate
            ? null
            : _secondaryButton('Later', () => Navigator.of(context).pop()),
        _primaryButton('Update', Icons.download_rounded, _startDownload),
      ),
      _DownloadState.downloading => (
        _secondaryButton('Cancel', _cancelDownload),
        null,
      ),
      _DownloadState.error => (
        widget.info.forceUpdate
            ? null
            : _secondaryButton('Cancel', () => Navigator.of(context).pop()),
        _primaryButton('Retry', Icons.refresh_rounded, _startDownload),
      ),
    };
    return Row(
      children: [
        if (secondary != null) Expanded(child: secondary),
        if (secondary != null && primary != null) const SizedBox(width: 12),
        if (primary != null) Expanded(child: primary),
      ],
    );
  }

  Widget _secondaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      height: 46,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          backgroundColor: AppColors.surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }

  /// The app's gradient button.
  Widget _primaryButton(String label, IconData icon, VoidCallback onPressed) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.buttonGradient),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
