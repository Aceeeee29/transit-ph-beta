import 'package:flutter/material.dart';
import '../models/post.dart';
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

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
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
    _tabController.dispose();
    super.dispose();
  }

  void _onDataChanged() => setState(() {});

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
    final pendingPostsCount = ModerationService.getPendingPosts().length;

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
      return Center(
        child: Column(
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

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pendingRoutes.length,
      itemBuilder: (context, index) {
        final route = pendingRoutes[index];
        return _buildRouteReviewCard(route);
      },
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

  // ─── Reported Posts Tab ────────────────────────────────────────────────────

  Widget _buildPendingPostsTab() {
    final pendingPosts = ModerationService.getPendingPosts();
    if (pendingPosts.isEmpty) {
      return Center(
        child: Column(
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

    return ListView.builder(
      itemCount: pendingPosts.length,
      itemBuilder: (context, index) {
        final post = pendingPosts[index];
        final reportReasons = ModerationService.getFeedbacks()
            .where((f) =>
                f.type == feedback_model.FeedbackType.report &&
                f.targetId == post.id)
            .map((f) => f.content)
            .toList();
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.content,
                    style: const TextStyle(fontSize: 16)),
                if (post.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: post.imageUrls.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Image.network(
                          post.imageUrls[index],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.error),
                        ),
                      ),
                    ),
                  ),
                ],
                if (post.taggedLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Location: ${post.taggedLocation!.name}',
                      style: const TextStyle(
                          fontSize: 14, color: Colors.blue),
                    ),
                  ),
                const SizedBox(height: 8),
                Text('By: ${post.userName ?? post.userEmail ?? 'Anonymous'}'),
                if (reportReasons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Reported for: ${reportReasons.join(', ')}',
                      style: const TextStyle(
                          color: Colors.red,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        ModerationService.rejectPost(post.id);
                        setState(() {});
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red),
                      child: const Text('Remove'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        ModerationService.approvePost(post.id);
                        setState(() {});
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Users Tab ─────────────────────────────────────────────────────────────

  Widget _buildUsersTab() {
    final users = ModerationService.getUsers();
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name,
                    style: const TextStyle(fontSize: 16)),
                Text(user.email),
                Text('Role: ${user.role.name}'),
                Text('Banned: ${user.isBanned}'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!user.isBanned)
                      ElevatedButton(
                        onPressed: () async {
                          if (user.uid != null) {
                            await ModerationService.banUser(user.uid!);
                            setState(() {});
                          }
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        child: const Text('Ban'),
                      )
                    else
                      ElevatedButton(
                        onPressed: () async {
                          if (user.uid != null) {
                            await ModerationService.unbanUser(user.uid!);
                            setState(() {});
                          }
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        child: const Text('Unban'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Feedbacks Tab ─────────────────────────────────────────────────────────

  Widget _buildFeedbacksTab() {
    final feedbacks = ModerationService.getFeedbacks();
    return ListView.builder(
      itemCount: feedbacks.length,
      itemBuilder: (context, index) {
        final feedback = feedbacks[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Type: ${feedback.type.name}',
                      style:
                          const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: feedback.status ==
                                feedback_model.FeedbackStatus.pending
                            ? Colors.orange
                            : feedback.status ==
                                feedback_model.FeedbackStatus.resolved
                            ? Colors.green
                            : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        feedback.status.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(feedback.content),
                if (feedback.targetId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Target: ${feedback.targetType?.name ?? 'unknown'} (${feedback.targetId})',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.blue),
                  ),
                ],
                const SizedBox(height: 4),
                Text('From: ${feedback.userId}'),
                Text('Time: ${feedback.timestamp}'),
                if (feedback.status ==
                    feedback_model.FeedbackStatus.pending) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          await ModerationService.updateFeedbackStatus(
                            feedback.id,
                            feedback_model.FeedbackStatus.resolved,
                          );
                          setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        child: const Text('Resolve'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await ModerationService.updateFeedbackStatus(
                            feedback.id,
                            feedback_model.FeedbackStatus.dismissed,
                          );
                          setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}