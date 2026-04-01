import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/user.dart';
import '../models/route.dart' as route_model;
import '../models/feedback.dart' as feedback_model;
import '../services/moderation_service.dart';
import '../widgets/route_preview.dart';

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
    _tabController = TabController(length: 4, vsync: this);
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
    final title = fromDismiss ? 'Dismiss Feedback' : 'Delete Feedback';
    final message = fromDismiss
        ? 'This will dismiss and permanently delete this feedback. Continue?'
        : 'This will permanently delete this resolved feedback. Continue?';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _danger.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: _danger,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(false),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: _surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _border),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(true),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: _danger,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: _danger.withOpacity(0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    await ModerationService.deleteFeedback(feedback.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fromDismiss
              ? 'Feedback dismissed and deleted'
              : 'Feedback deleted',
        ),
      ),
    );
    setState(() {});
  }

  Future<bool> _confirmBanUser(User user) async {
    var typedBan = '';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canBan = typedBan.trim() == 'BAN';

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.gpp_bad_rounded,
                              color: _danger,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Confirm User Ban',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You are about to ban ${user.name}. Type BAN to confirm this action.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: _surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _border),
                        ),
                        child: TextField(
                          onChanged: (value) {
                            typedBan = value;
                            setDialogState(() {});
                          },
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Type BAN',
                            hintStyle: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(false),
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _surfaceAlt,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _border),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: canBan
                                  ? () => Navigator.of(context).pop(true)
                                  : null,
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: canBan
                                      ? _danger
                                      : _danger.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: canBan
                                      ? [
                                          BoxShadow(
                                            color: _danger.withOpacity(0.28),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Ban User',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return confirmed == true;
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
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
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
          labelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500),
          tabs: [
            _tabWithBadge('Routes', pendingRoutesCount),
            _tabWithBadge('Posts', pendingPostsCount),
            const Tab(text: 'Users'),
            const Tab(text: 'Feedbacks'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingRoutesTab(),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _warning.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                  bottom: BorderSide(color: _warning.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: _warning.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pending_rounded,
                          size: 12, color: _warning),
                      const SizedBox(width: 4),
                      Text(
                        'PENDING REVIEW',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _warning,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (route.createdAt != null)
                  Text(
                    _formatDate(route.createdAt!),
                    style: const TextStyle(
                        fontSize: 11, color: _textSecondary),
                  ),
              ],
            ),
          ),

          // ── Route info ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // From → To
                Row(
                  children: [
                    const Icon(Icons.trip_origin,
                        size: 14, color: _success),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        route.startLocation,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    width: 2,
                    height: 14,
                    color: _border,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 14, color: _danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        route.endLocation,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                Text(
                  route.shortDescription,
                  style: const TextStyle(
                      fontSize: 13, color: _textSecondary, height: 1.4),
                ),

                const SizedBox(height: 12),

                // ── Meta chips ───────────────────────────────────────────
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (route.eta != null)
                      _metaChip(Icons.timer_outlined, route.eta!, _accent),
                    if (route.price != null)
                      _metaChip(Icons.payments_outlined, route.price!,
                          _success),
                    if (route.distance != null)
                      _metaChip(Icons.straighten_rounded, route.distance!,
                          _textSecondary),
                    _metaChip(Icons.directions_rounded,
                        '${route.steps.length} steps', _textSecondary),
                  ],
                ),

                if (route.audienceTags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'SUBMITTED TAGS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: route.audienceTags
                        .map((tag) => _metaChip(Icons.sell_outlined, tag, _accent))
                        .toList(),
                  ),
                ],

                const SizedBox(height: 12),

                // ── Steps preview ────────────────────────────────────────
                if (route.steps.isNotEmpty) ...[
                  const Text(
                    'STEPS PREVIEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...route.steps.take(3).map(
                        (step) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _accentFor(step.mode),
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                                child: Text(
                                  step.mode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  step.instruction,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: _textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (route.steps.length > 3)
                    Text(
                      '+ ${route.steps.length - 3} more steps',
                      style: const TextStyle(
                          fontSize: 11, color: _textSecondary),
                    ),
                ],
              ],
            ),
          ),

          // ── Action buttons ───────────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _openRoutePreview(route),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _accent.withOpacity(0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, size: 16, color: _accent),
                        SizedBox(width: 6),
                        Text(
                          'Preview Route',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await ModerationService.rejectRoute(route.id);
                          await widget.onRoutesModerated?.call();
                        },
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: _danger.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _danger.withOpacity(0.3)),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.close_rounded,
                                  size: 16, color: _danger),
                              SizedBox(width: 6),
                              Text(
                                'Reject',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await ModerationService.approveRoute(route.id);
                          await widget.onRoutesModerated?.call();
                        },
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _success.withOpacity(0.9),
                                _success,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: _success.withOpacity(0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.verified_rounded,
                                  size: 16, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Approve',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final pendingPosts = _getReportedPendingPosts();
    if (pendingPosts.isEmpty) {
      return _refreshableEmptyState(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.check_circle_outline_rounded,
                  size: 32, color: _textSecondary),
            ),
            const SizedBox(height: 14),
            const Text('No reported posts',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary)),
            const SizedBox(height: 6),
            const Text('All clear!',
                style: TextStyle(fontSize: 13, color: _textSecondary)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshModeratorPanel,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: pendingPosts.length,
        itemBuilder: (context, index) {
          final post = pendingPosts[index];
          final reportReasons = ModerationService.getFeedbacks()
              .where((f) =>
                  f.type == feedback_model.FeedbackType.report &&
                f.status == feedback_model.FeedbackStatus.pending &&
                  f.targetId == post.id)
              .map((f) => f.content)
              .toList();
            final authorName = post.userName?.trim();
            final authorEmail = post.userEmail?.trim();
            final displayAuthor = (authorName != null && authorName.isNotEmpty)
              ? authorName
              : ((authorEmail != null && authorEmail.isNotEmpty)
                ? authorEmail
                : 'Anonymous');
          return _panelCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.report_problem_outlined,
                            size: 16, color: _danger),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Reported Post',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    post.content,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _textPrimary,
                      height: 1.4,
                    ),
                  ),
                  if (post.imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: post.imageUrls.length,
                        itemBuilder: (context, index) => Container(
                          width: 90,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.network(
                            post.imageUrls[index],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image,
                                    color: _textSecondary),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metaChip(
                        Icons.person_outline,
                        displayAuthor,
                        _accent,
                      ),
                      if (post.taggedLocation != null)
                        _metaChip(
                          Icons.location_on_outlined,
                          post.taggedLocation!.name,
                          _success,
                        ),
                    ],
                  ),
                  if (reportReasons.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _danger.withOpacity(0.2)),
                      ),
                      child: Text(
                        'Reported for: ${reportReasons.join(', ')}',
                        style: const TextStyle(
                          color: _danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _actionButton(
                        label: 'Remove',
                        color: _danger,
                        onTap: () async {
                          await ModerationService.removePostPermanently(post.id);
                          setState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      _actionButton(
                        label: 'Dismiss',
                        color: _success,
                        onTap: () async {
                          await ModerationService.dismissReportedPost(post.id);
                          setState(() {});
                        },
                        filled: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Users Tab ─────────────────────────────────────────────────────────────

  Widget _buildUsersTab() {
    final users = ModerationService.getUsers()
      .where((u) => u.role == UserRole.user)
      .toList()
      ..sort((a, b) {
        final aName = (a.name.trim().isNotEmpty ? a.name : a.email)
            .toLowerCase();
        final bName = (b.name.trim().isNotEmpty ? b.name : b.email)
            .toLowerCase();
        return aName.compareTo(bName);
      });

    final query = _userSearchQuery.trim().toLowerCase();
    final filteredUsers = users.where((u) {
      if (query.isEmpty) return true;
      return u.name.toLowerCase().contains(query) ||
          u.email.toLowerCase().contains(query);
    }).toList();

    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshModeratorPanel,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: (filteredUsers.isEmpty ? 2 : filteredUsers.length + 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _userSearchController,
                  onChanged: (value) =>
                      setState(() => _userSearchQuery = value),
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search users by name or email',
                    hintStyle: const TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    icon: const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: _textSecondary,
                    ),
                    suffixIcon: _userSearchQuery.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _userSearchController.clear();
                              setState(() => _userSearchQuery = '');
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: _textSecondary,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            );
          }

          if (filteredUsers.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No users found',
                  style: TextStyle(
                    color: _textSecondary.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          final user = filteredUsers[index - 1];
          return _panelCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: _accentSoft,
                        child: Text(
                          (user.name.isNotEmpty ? user.name[0] : '?')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.email,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metaChip(Icons.badge_outlined, user.role.name, _accent),
                      _metaChip(
                        user.isBanned
                            ? Icons.block_outlined
                            : Icons.verified_user_outlined,
                        user.isBanned ? 'Banned' : 'Active',
                        user.isBanned ? _danger : _success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _actionButton(
                        label: user.isBanned ? 'Unban' : 'Ban',
                        color: user.isBanned ? _success : _danger,
                        filled: user.isBanned,
                        onTap: () async {
                          if (user.uid == null) return;
                          if (user.role != UserRole.user) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Moderator accounts cannot be banned.'),
                              ),
                            );
                            return;
                          }
                          if (user.isBanned) {
                            await ModerationService.unbanUser(user.uid!);
                          } else {
                            final confirmed = await _confirmBanUser(user);
                            if (!confirmed) return;
                            await ModerationService.banUser(user.uid!);
                          }
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Feedbacks Tab ─────────────────────────────────────────────────────────

  Widget _buildFeedbacksTab() {
    final feedbacks = ModerationService.getFeedbacks()
        .where((f) => f.type == feedback_model.FeedbackType.feedback)
        .toList();
    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshModeratorPanel,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: feedbacks.length,
        itemBuilder: (context, index) {
          final feedback = feedbacks[index];
          final statusColor = feedback.status ==
                  feedback_model.FeedbackStatus.pending
              ? _warning
              : feedback.status == feedback_model.FeedbackStatus.resolved
                  ? _success
                  : _textSecondary;

          return _panelCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _accentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.feedback_outlined,
                                size: 16, color: _accent),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            feedback.type.name.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          feedback.status.name,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Text(
                      feedback.content,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metaChip(Icons.person_outline, feedback.userId, _accent),
                      _metaChip(
                        Icons.schedule_outlined,
                        _formatDate(feedback.timestamp),
                        _textSecondary,
                      ),
                      if (feedback.targetId != null)
                        _metaChip(
                          Icons.gps_fixed_outlined,
                          '${feedback.targetType?.name ?? 'unknown'} • ${feedback.targetId}',
                          _success,
                        ),
                    ],
                  ),
                  if (feedback.status ==
                      feedback_model.FeedbackStatus.pending) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _actionButton(
                          label: 'Resolve',
                          color: _success,
                          filled: true,
                          onTap: () async {
                            await ModerationService.updateFeedbackStatus(
                              feedback.id,
                              feedback_model.FeedbackStatus.resolved,
                            );
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        _actionButton(
                          label: 'Dismiss',
                          color: _textSecondary,
                          onTap: () async {
                            await _deleteFeedbackWithConfirmation(
                              feedback,
                              fromDismiss: true,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                  if (feedback.status ==
                      feedback_model.FeedbackStatus.resolved) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _actionButton(
                          label: 'Delete',
                          color: _danger,
                          onTap: () async {
                            await _deleteFeedbackWithConfirmation(
                              feedback,
                              fromDismiss: false,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}