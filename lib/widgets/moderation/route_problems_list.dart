import 'package:flutter/material.dart';

import '../../services/route_issue_service.dart';
import '../../theme/app_colors.dart';

const _accent = Color(0xFF0B8FD6);
const _warning = Color(0xFFC2410C);

/// Routes riders reported, for moderators. The ones marked Possibly outdated
/// come first. Most reports need nothing: enough of them flag the route or fix
/// its fare by themselves. A moderator steps in to clear a label after
/// checking, or to throw out wrong reports.
class RouteProblemsList extends StatefulWidget {
  const RouteProblemsList({super.key});

  @override
  State<RouteProblemsList> createState() => _RouteProblemsListState();
}

class _RouteProblemsListState extends State<RouteProblemsList> {
  late Future<List<RouteProblem>> _problems = RouteIssueService.issueQueue();

  /// Routes with a decision on its way, so a second tap does nothing.
  final _busy = <String>{};

  Future<void> _reload() async {
    final next = RouteIssueService.issueQueue();
    // A block body: an arrow would hand the Future back to setState, which
    // Flutter refuses with an error.
    setState(() {
      _problems = next;
    });
    await next.catchError((_) => <RouteProblem>[]);
  }

  Future<void> _settle(RouteProblem problem, String resolution) async {
    final note = await _askNote(resolution);
    if (note == null || !mounted) return;
    setState(() => _busy.add(problem.routeKey));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await RouteIssueService.settle(
        problem.routeKey,
        resolution: resolution,
        note: note,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            resolution == 'resolved'
                ? 'Marked as fixed. The label is gone.'
                : 'Reports dismissed. The label is gone.',
          ),
        ),
      );
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(problem.routeKey));
    }
  }

  /// Null when the moderator cancels. An empty note is fine.
  Future<String?> _askNote(String resolution) {
    final controller = TextEditingController();
    final fixed = resolution == 'resolved';
    return showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(fixed ? 'Mark as fixed' : 'Dismiss reports'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fixed
                      ? 'Use this when the route was fixed, or you checked and '
                          'it is right. Its reports close and the Possibly '
                          'outdated label goes.'
                      : 'Use this when the reports are wrong. They close and '
                          'the Possibly outdated label goes.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'What you checked (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(dialogContext, controller.text.trim()),
                child: Text(fixed ? 'Mark as fixed' : 'Dismiss'),
              ),
            ],
          ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RouteProblem>>(
      future: _problems,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _message(
            "Couldn't load route problems. Pull down to try again.",
          );
        }
        final problems = snapshot.data ?? const <RouteProblem>[];
        if (problems.isEmpty) {
          return _message('No route problems right now.');
        }
        return RefreshIndicator(
          color: _accent,
          onRefresh: _reload,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: problems.length,
            itemBuilder: (context, i) => _card(problems[i]),
          ),
        );
      },
    );
  }

  Widget _message(String text) {
    return RefreshIndicator(
      color: _accent,
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  static String _sourceLabel(String? source) => switch (source) {
    'gtfs' => 'DOTC 2013 data',
    'osm' => 'OpenStreetMap',
    _ => 'Rider route',
  };

  Widget _card(RouteProblem problem) {
    final busy = _busy.contains(problem.routeKey);
    final fares = [
      for (final issue in problem.issues)
        if (issue.farePaid case final fare?)
          'PHP ${fare.toStringAsFixed(fare % 1 == 0 ? 0 : 2)}'
              '${issue.stepIndex != null ? ' (step ${issue.stepIndex! + 1})' : ''}',
    ];
    final notes = [
      for (final issue in problem.issues)
        if (issue.note case final note? when note.isNotEmpty)
          '${issue.type.label}: $note',
    ];
    final fixes = problem.issues.where((i) => i.correctionId != null).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              problem.outdated
                  ? _warning.withValues(alpha: 0.5)
                  : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  problem.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (problem.outdated)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Possibly outdated',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _sourceLabel(problem.source),
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in problem.counts.entries)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${entry.key.label}: ${entry.value} '
                    '${entry.value == 1 ? 'rider' : 'riders'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
          if (fares.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Fares paid: ${fares.join(', ')}',
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ],
          if (fixes > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$fixes drawn ${fixes == 1 ? 'fix' : 'fixes'} waiting in the Routes tab',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          for (final note in notes.take(5)) ...[
            const SizedBox(height: 4),
            Text(
              '"$note"',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _settle(problem, 'dismissed'),
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : () => _settle(problem, 'resolved'),
                  child: const Text('Mark as fixed'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
