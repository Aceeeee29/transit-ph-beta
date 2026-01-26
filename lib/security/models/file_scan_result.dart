class FileScanResult {
  final bool isBlocked;
  final List<String> reasons;
  final String sha256;
  final String mimeType;
  final int sizeBytes;

  FileScanResult({
    required this.isBlocked,
    required this.reasons,
    required this.sha256,
    required this.mimeType,
    required this.sizeBytes,
  });
}
