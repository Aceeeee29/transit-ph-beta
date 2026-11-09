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
  static const _baseApprovalPoints = 20;

  // Votes a question needs before it counts at full weight.
  static const _fullWeightVotes = 5;

  static RouteTrustScore computeConfidence({
    required route_model.Route route,
    required Map<String, int> feedbackSummary,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    // Approval keeps a route at the base score: trust has to come from
    // riders' confirmations, not from a moderator's or admin's approval.
    final approvalPoints = switch (route.approvalStatus) {
      route_model.RouteApprovalStatus.approved => _baseApprovalPoints,
      route_model.RouteApprovalStatus.pending => _baseApprovalPoints,
      route_model.RouteApprovalStatus.rejected => 0,
      route_model.RouteApprovalStatus.withdrawn => 0,
    };

    final fareYes = feedbackSummary['fareAccurateYes'] ?? 0;
    final fareNo = feedbackSummary['fareAccurateNo'] ?? 0;
    final schedYes = feedbackSummary['scheduleAccurateYes'] ?? 0;
    final schedNo = feedbackSummary['scheduleAccurateNo'] ?? 0;
    final opYes = feedbackSummary['stillOperatingYes'] ?? 0;
    final opNo = feedbackSummary['stillOperatingNo'] ?? 0;

    // Each question gives up to its max points when riders agree. A
    // question only counts fully once it has _fullWeightVotes votes, so one
    // rider can't push a route to the top (or the bottom) alone.
    int signedRatioPoints(int yes, int no, int maxPoints) {
      final total = yes + no;
      if (total <= 0) return 0;
      final signedRatio = (yes - no) / total;
      final weight = (total / _fullWeightVotes).clamp(0.0, 1.0);
      return (signedRatio * weight * maxPoints).round().clamp(
        -maxPoints,
        maxPoints,
      );
    }

    // 22 + 22 + 21 = 65, so base 20 + 65 + freshness 15 can reach 100.
    final confirmationPoints =
        signedRatioPoints(fareYes, fareNo, 22) +
        signedRatioPoints(schedYes, schedNo, 22) +
        signedRatioPoints(opYes, opNo, 21);

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

    final total = (approvalPoints + confirmationPoints + freshnessPoints).clamp(
      0,
      100,
    );

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
