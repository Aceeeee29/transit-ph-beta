class LinkSafetyResult {
  final bool isBlocked;
  final int riskScore;
  final List<String> reasons;
  final String normalizedUrl;
  final String host;

  LinkSafetyResult({
    required this.isBlocked,
    required this.riskScore,
    required this.reasons,
    required this.normalizedUrl,
    required this.host,
  });
}
