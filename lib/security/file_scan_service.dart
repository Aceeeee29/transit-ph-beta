import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/file_scan_result.dart';

class FileScanService {
  static const String _badHashListKey = 'file_scan_bad_hashes';
  static const int _defaultMaxFileSizeBytes = 10 * 1024 * 1024; // 10MB
  static const List<String> _dangerousExtensions = [
    '.apk',
    '.exe',
    '.js',
    '.jar',
  ];

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<FileScanResult> scanFile(File file) async {
    await init();

    List<String> reasons = [];
    bool isBlocked = false;

    // Check file size
    int sizeBytes = await file.length();
    if (sizeBytes > _defaultMaxFileSizeBytes) {
      isBlocked = true;
      reasons.add('File size exceeds limit (${_defaultMaxFileSizeBytes} bytes)');
    }

    // Compute SHA-256 hash
    String sha256 = await _computeSha256(file);

    // Check bad hash list
    List<String> badHashes = _prefs?.getStringList(_badHashListKey) ?? [];
    if (badHashes.contains(sha256)) {
      isBlocked = true;
      reasons.add('File hash is in bad hash list');
    }

    // Detect MIME type
    String? mimeType = lookupMimeType(file.path);
    if (mimeType == null) {
      isBlocked = true;
      reasons.add('Unable to detect MIME type');
    }

    // Check dangerous extensions
    String extension = file.path.split('.').last.toLowerCase();
    if (_dangerousExtensions.contains('.$extension')) {
      isBlocked = true;
      reasons.add('Dangerous file extension: .$extension');
    }

    // Validate MIME type vs extension (basic check)
    if (mimeType != null && !_isMimeTypeValidForExtension(mimeType, extension)) {
      isBlocked = true;
      reasons.add('MIME type does not match file extension');
    }

    return FileScanResult(
      isBlocked: isBlocked,
      reasons: reasons,
      sha256: sha256,
      mimeType: mimeType ?? 'unknown',
      sizeBytes: sizeBytes,
    );
  }

  static Future<String> _computeSha256(File file) async {
    var bytes = await file.readAsBytes();
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  static bool _isMimeTypeValidForExtension(String mimeType, String extension) {
    // Basic validation - can be expanded
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return mimeType.startsWith('image/jpeg');
      case 'png':
        return mimeType == 'image/png';
      case 'pdf':
        return mimeType == 'application/pdf';
      case 'txt':
        return mimeType == 'text/plain';
      default:
        return true; // Allow unknown extensions for now
    }
  }

  static Future<void> updateBadHashList(List<String> newHashes) async {
    await init();
    List<String> currentHashes = _prefs?.getStringList(_badHashListKey) ?? [];
    Set<String> allHashes = {...currentHashes, ...newHashes};
    await _prefs?.setStringList(_badHashListKey, allHashes.toList());
    // TODO: Implement remote endpoint update logic here
  }

  static Future<List<String>> getBadHashList() async {
    await init();
    return _prefs?.getStringList(_badHashListKey) ?? [];
  }
}
