import '../models/route.dart' as route_model;

class RouteTrustScore {
  final int total;
  final int approvalPoints;
  final int confirmationPoints;
  final int freshnessPoints;

  const RouteTrustScore({
    required this.total,
    required this.approvalPoints,
    required this.confirmationPoints,
    required this.freshnessPoints,
  });
}

class RouteTrustService {
  static RouteTrustScore computeConfidence({
    required route_model.Route route,
    required Map<String, int> feedbackSummary,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    final approvalPoints = switch (route.approvalStatus) {
      route_model.RouteApprovalStatus.approved => 50,
      route_model.RouteApprovalStatus.pending => 20,
      route_model.RouteApprovalStatus.rejected => 0,
    };

    final fareYes = feedbackSummary['fareAccurateYes'] ?? 0;
    final fareNo = feedbackSummary['fareAccurateNo'] ?? 0;
    final schedYes = feedbackSummary['scheduleAccurateYes'] ?? 0;
    final schedNo = feedbackSummary['scheduleAccurateNo'] ?? 0;
    final opYes = feedbackSummary['stillOperatingYes'] ?? 0;
    final opNo = feedbackSummary['stillOperatingNo'] ?? 0;

    int signedRatioPoints(int yes, int no, int maxPoints) {
      final total = yes + no;
      if (total <= 0) return 0;
      final signedRatio = (yes - no) / total;
      return (signedRatio * maxPoints).round().clamp(-maxPoints, maxPoints);
    }

    final confirmationPoints =
        signedRatioPoints(fareYes, fareNo, 12) +
        signedRatioPoints(schedYes, schedNo, 12) +
        signedRatioPoints(opYes, opNo, 11);

    final refTime = route.updatedAt ?? route.createdAt;
    int freshnessPoints;
    if (refTime == null) {
      freshnessPoints = 0;
    } else {
      final ageDays = current.difference(refTime).inDays;
      if (ageDays <= 7) {
        freshnessPoints = 15;
      } else if (ageDays <= 30) {
        freshnessPoints = 10;
      } else if (ageDays <= 90) {
        freshnessPoints = 5;
      } else {
        freshnessPoints = 0;
      }
    }

    final total = (approvalPoints + confirmationPoints + freshnessPoints)
      .clamp(0, 100);

    return RouteTrustScore(
      total: total,
      approvalPoints: approvalPoints,
      confirmationPoints: confirmationPoints,
      freshnessPoints: freshnessPoints,
    );
  }

  static String confidenceLabel(int score) {
    if (score >= 85) return 'High trust';
    if (score >= 65) return 'Moderate trust';
    return 'Needs verification';
  }
}
