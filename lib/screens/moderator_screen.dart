import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/user.dart';
import '../models/route.dart' as route_model;
import '../models/feedback.dart' as feedback_model;
import '../services/moderation_service.dart';
import '../services/route_service.dart';
import '../services/route_trust_service.dart';
import '../widgets/route_preview.dart';
part 'moderator_screen_route_cards.dart';
part 'moderator_screen_user_management.dart';

class ModeratorScreen extends StatefulWidget {
  final Future<void> Function()? onRoutesModerated;

  const ModeratorScreen({super.key, this.onRoutesModerated});

  @override
  State<ModeratorScreen> createState() => _ModeratorScreenState();
}

class _ModeratorScreenState extends State<ModeratorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final ValueNotifier<List<Post>> _postsNotifier;
  late final ValueNotifier<List<route_model.Route>> _routesNotifier;
  final TextEditingController _userSearchController = TextEditingController();
  String _userSearchQuery = '';

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);
  static const _success = Color(0xFF3EC97A);
  static const _warning = Color(0xFFFFB547);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _postsNotifier = ModerationService.postsNotifier;
    _routesNotifier = ModerationService.pendingRoutesNotifier;
    _postsNotifier.addListener(_onDataChanged);
    _routesNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _postsNotifier.removeListener(_onDataChanged);
    _routesNotifier.removeListener(_onDataChanged);
    _userSearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onDataChanged() => setState(() {});

  void _refreshModeratorState() {
    if (!mounted) return;
    setState(() {});
  }

  void _setUserSearchQuery(String value) {
    setState(() => _userSearchQuery = value);
  }

  void _clearUserSearchQuery() {
    _userSearchController.clear();
    _setUserSearchQuery('');
  }

  Future<void> _refreshModeratorPanel() async {
    await widget.onRoutesModerated?.call();
    // Keep pull-to-refresh responsive even when realtime listeners are already up-to-date.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() {});
  }

  Future<void> _deleteFeedbackWithConfirmation(
    feedback_model.Feedback feedback, {
    required bool fromDismiss,
  }) async {
    await this._deleteFeedbackWithConfirmationSection(
      feedback,
      fromDismiss: fromDismiss,
    );
  }

  String _buildRestrictionLabel(User user) {
    if (!user.hasActiveRestriction) return 'Active';
    final until = user.restrictedUntil;
    if (until == null) return 'Restricted';
    final remaining = until.difference(DateTime.now());
    final daysLeft = (remaining.inHours / 24).ceil().clamp(1, 7);
    return 'Restricted (${daysLeft}d left)';
  }

  Future<int?> _confirmRestrictUser(User user) async {
    return this._confirmRestrictUserSection(user);
  }

  Widget _refreshableEmptyState(Widget child) {
    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshModeratorPanel,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Center(child: child),
          ),
        ],
      ),
    );
  }

  // ─── Pending route count badge ─────────────────────────────────────────────
  Widget _tabWithBadge(String label, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: _danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingRoutesCount = _routesNotifier.value.length;
    final pendingPostsCount = _getReportedPendingPosts().length;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.shield_rounded,
                  color: _accent, size: 16),
            ),
            const SizedBox(width: 10),
            const Text(
              'Moderator Panel',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _accent,
          unselectedLabelColor: _textSecondary,
          indicatorColor: _accent,
          indicatorWeight: 2.5,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500),
          tabs: [
            _tabWithBadge('Routes', pendingRoutesCount),
            const Tab(text: 'Trust'),
            _tabWithBadge('Posts', pendingPostsCount),
            const Tab(text: 'Users'),
            const Tab(text: 'Feedback'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingRoutesTab(),
          _buildRouteTrustTab(),
          _buildPendingPostsTab(),
          _buildUsersTab(),
          _buildFeedbacksTab(),
        ],
      ),
    );
  }

  // ─── Pending Routes Tab ────────────────────────────────────────────────────

  Widget _buildPendingRoutesTab() {
    final pendingRoutes = _routesNotifier.value;

    if (pendingRoutes.isEmpty) {
      return _refreshableEmptyState(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.route_rounded,
                  size: 32, color: _textSecondary),
            ),
            const SizedBox(height: 14),
            const Text(
              'No pending routes',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'All submitted routes have been reviewed.',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshModeratorPanel,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: pendingRoutes.length,
        itemBuilder: (context, index) {
          final route = pendingRoutes[index];
          return _buildRouteReviewCard(route);
        },
      ),
    );
  }

  Widget _buildRouteReviewCard(route_model.Route route) {
    return this._buildRouteReviewCardSection(route);
  }

  void _openRoutePreview(route_model.Route route) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoutePreview(
          route: route,
          readOnly: true,
        ),
      ),
    );
  }

  Widget _buildRouteTrustTab() {
    return StreamBuilder<List<route_model.Route>>(
      stream: RouteService.watchAllRoutes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final routes = snapshot.data ?? const <route_model.Route>[];
        if (routes.isEmpty) {
          return _refreshableEmptyState(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    size: 32,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'No routes with trust data',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Approved routes will appear here with confidence scores.',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: _accent,
          onRefresh: _refreshModeratorPanel,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: routes.length,
            itemBuilder: (context, index) {
              final route = routes[index];
              return _buildRouteTrustCard(route);
            },
          ),
        );
      },
    );
  }

  Widget _buildRouteTrustCard(route_model.Route route) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${route.startLocation} -> ${route.endLocation}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildTrustConfidenceChip(route),
              _metaChip(
                Icons.verified,
                route.approvalStatus.name.toUpperCase(),
                route.isApproved ? _success : _warning,
              ),
              _metaChip(Icons.directions_rounded, '${route.steps.length} steps', _textSecondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustConfidenceChip(route_model.Route route) {
    return StreamBuilder<Map<String, int>>(
      stream: RouteService.watchRouteFeedbackSummary(route.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _metaChip(Icons.verified_user_outlined, 'Trust loading...', _textSecondary);
        }

        final summary = snapshot.data ?? const {
          'fareAccurateYes': 0,
          'fareAccurateNo': 0,
          'scheduleAccurateYes': 0,
          'scheduleAccurateNo': 0,
          'stillOperatingYes': 0,
          'stillOperatingNo': 0,
        };

        final score = RouteTrustService.computeConfidence(
          route: route,
          feedbackSummary: summary,
        );
        final isCritical = score.total < 30;
        final label = RouteTrustService.confidenceLabel(score.total);
        final color = score.total >= 85
            ? _success
            : score.total >= 65
                ? _accent
                : _warning;

        final trustChip = isCritical
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _metaChip(
                    Icons.warning_amber_rounded,
                    'Trust ${score.total}/100 ($label)',
                    _danger,
                  ),
                  const SizedBox(width: 6),
                  _metaChip(
                    Icons.notification_important_rounded,
                    'ALERT',
                    _danger,
                  ),
                ],
              )
            : _metaChip(
                Icons.verified_user_outlined,
                'Trust ${score.total}/100 ($label)',
                color,
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            trustChip,
          ],
        );
      },
    );
  }

  Widget _panelCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required Future<void> Function() onTap,
    bool filled = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: filled ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }

  Color _accentFor(String mode) {
    switch (mode) {
      case 'Walk':
        return Colors.green.shade600;
      case 'Jeepney':
        return Colors.blue.shade600;
      case 'Bus':
        return Colors.red.shade600;
      case 'Train':
        return Colors.purple.shade600;
      case 'Tricycle':
        return Colors.orange.shade600;
      case 'FX/Van':
        return Colors.amber.shade700;
      case 'Ferry':
        return Colors.lightBlue.shade600;
      default:
        return _accent;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  List<Post> _getReportedPendingPosts() {
    final reportedPostIds = ModerationService.getFeedbacks()
        .where((f) =>
            f.type == feedback_model.FeedbackType.report &&
        f.status == feedback_model.FeedbackStatus.pending &&
            f.targetType == feedback_model.FeedbackTargetType.post &&
            f.targetId != null)
        .map((f) => f.targetId!)
        .toSet();

    return ModerationService.postsNotifier.value
      .where((p) =>
        reportedPostIds.contains(p.id) &&
        p.moderationStatus != ModerationStatus.rejected)
        .toList();
  }

  // ─── Reported Posts Tab ────────────────────────────────────────────────────

  Widget _buildPendingPostsTab() {
    return this._buildPendingPostsTabSection();
  }

  // ─── Users Tab ─────────────────────────────────────────────────────────────

  Widget _buildUsersTab() {
    return this._buildUsersTabSection();
  }

  // ─── Feedbacks Tab ─────────────────────────────────────────────────────────

  Widget _buildFeedbacksTab() {
    return this._buildFeedbacksTabSection();
  }
}