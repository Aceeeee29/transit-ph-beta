/// Why a moderator can reject a route. The codes must match the server's list
/// in `routes-api` and the `rejection_reasons` table, which refuse anything else.
class RouteRejectionReason {
  final String code;
  final String label;
  final bool needsNote;

  const RouteRejectionReason({
    required this.code,
    required this.label,
    this.needsNote = false,
  });

  static const all = [
    RouteRejectionReason(code: 'incomplete', label: 'Missing information'),
    RouteRejectionReason(
      code: 'outside_area',
      label: 'Outside the service area',
    ),
    RouteRejectionReason(
      code: 'wrong_path',
      label: "Path doesn't match the real route",
    ),
    RouteRejectionReason(code: 'wrong_fare', label: 'Fare is wrong'),
    RouteRejectionReason(code: 'duplicate', label: 'Already exists'),
    RouteRejectionReason(code: 'not_operating', label: 'Route no longer runs'),
    RouteRejectionReason(
      code: 'unsafe_or_spam',
      label: 'Spam or unsafe content',
    ),
    RouteRejectionReason(code: 'other', label: 'Other', needsNote: true),
  ];

  static RouteRejectionReason? byCode(String code) {
    for (final reason in all) {
      if (reason.code == code) return reason;
    }
    return null;
  }
}
