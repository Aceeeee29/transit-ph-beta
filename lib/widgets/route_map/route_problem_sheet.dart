import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/route_issue_service.dart';
import '../../theme/app_colors.dart';
import '../translated_text.dart';

const _accent = Color(0xFF0B8FD6);
const _danger = Color(0xFFE05C6A);

/// The two kinds of report. They go to different places, so the rider picks
/// first.
enum ReportKind {
  /// Traffic, floods, accidents: shown to riders on this road for a day.
  road,

  /// Fare, path, stops, schedule or "stopped running": counts toward fixing
  /// or flagging the route.
  route,
}

/// Asks which kind of problem the rider wants to report.
Future<ReportKind?> showReportKindChooser(BuildContext context) {
  return showModalBottomSheet<ReportKind>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TranslatedText(
                  'What do you want to report?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _KindOption(
                  icon: Icons.traffic_outlined,
                  title: 'The road right now',
                  subtitle:
                      'Traffic, flooding, an accident. Riders on this road '
                      'see it for a day.',
                  onTap: () => Navigator.pop(sheetContext, ReportKind.road),
                ),
                const SizedBox(height: 8),
                _KindOption(
                  icon: Icons.edit_road_outlined,
                  title: "This route's details are wrong",
                  subtitle:
                      'The fare, the path, a stop, the schedule, or it '
                      'stopped running.',
                  onTap: () => Navigator.pop(sheetContext, ReportKind.route),
                ),
              ],
            ),
          ),
        ),
  );
}

class _KindOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _KindOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: _accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    TranslatedText(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One ride a report can be about.
class ProblemTarget {
  /// The route's id, or `gtfs:<route_id>` for the DOTC 2013 feed.
  final String routeKey;

  /// "Step 2: Jeepney", shown when there's more than one ride to pick from.
  final String label;

  /// Which step of a rider route this ride is. A fare report needs it. Null
  /// for GTFS lines.
  final int? stepIndex;

  const ProblemTarget({
    required this.routeKey,
    required this.label,
    this.stepIndex,
  });
}

/// What the rider filled in.
class RouteProblemChoice {
  final ProblemTarget target;
  final RouteIssueType type;
  final double? farePaid;
  final String note;

  /// The rider wants to draw the right way, which sends a correction.
  final bool drawFix;

  const RouteProblemChoice({
    required this.target,
    required this.type,
    this.farePaid,
    this.note = '',
    this.drawFix = false,
  });
}

/// Asks what's wrong with a route's details. [targets] are the rides it can
/// be about, at least one. [canDrawFix] offers drawing the right way for a
/// wrong path, which only saved routes can do.
Future<RouteProblemChoice?> showRouteProblemSheet(
  BuildContext context, {
  required String title,
  required List<ProblemTarget> targets,
  bool canDrawFix = false,
}) {
  assert(targets.isNotEmpty);
  return showModalBottomSheet<RouteProblemChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => _RouteProblemSheet(
          title: title,
          targets: targets,
          canDrawFix: canDrawFix,
        ),
  );
}

class _RouteProblemSheet extends StatefulWidget {
  final String title;
  final List<ProblemTarget> targets;
  final bool canDrawFix;

  const _RouteProblemSheet({
    required this.title,
    required this.targets,
    required this.canDrawFix,
  });

  @override
  State<_RouteProblemSheet> createState() => _RouteProblemSheetState();
}

class _RouteProblemSheetState extends State<_RouteProblemSheet> {
  RouteIssueType? _type;
  late ProblemTarget _target = widget.targets.first;
  final _fare = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _fare.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _differentRoutes =>
      widget.targets.map((t) => t.routeKey).toSet().length > 1;

  // Which ride matters when the rides are on different routes, or for a fare,
  // which is per ride.
  bool get _asksWhichRide =>
      widget.targets.length > 1 &&
      (_differentRoutes || _type == RouteIssueType.wrongFare);

  double? get _farePaid {
    final value = double.tryParse(_fare.text.trim());
    return value != null && value > 0 && value <= 1000 ? value : null;
  }

  bool get _canSend {
    final type = _type;
    if (type == null) return false;
    if (type == RouteIssueType.wrongFare) return _farePaid != null;
    if (type == RouteIssueType.other) return _note.text.trim().isNotEmpty;
    return true;
  }

  void _send({bool drawFix = false}) {
    Navigator.pop(
      context,
      RouteProblemChoice(
        target: _target,
        type: _type!,
        farePaid: _type == RouteIssueType.wrongFare ? _farePaid : null,
        note: _note.text.trim(),
        drawFix: drawFix,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder:
            (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TranslatedText(
                    "What's wrong with this route?",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TranslatedText(
                    'When 5 riders report the same thing, the route is marked '
                    'Possibly outdated. When 3 riders paid the same fare, it '
                    'is updated.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final type in RouteIssueType.values) _typeOption(type),
                  if (_asksWhichRide) ...[
                    const SizedBox(height: 8),
                    _sectionLabel('Which ride?'),
                    for (final target in widget.targets) _rideOption(target),
                  ],
                  if (_type == RouteIssueType.wrongFare) ...[
                    const SizedBox(height: 8),
                    _sectionLabel('Fare you paid (PHP)'),
                    _field(
                      controller: _fare,
                      hint: 'e.g. 15',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      formatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                    ),
                  ],
                  if (_type != null) ...[
                    const SizedBox(height: 8),
                    _sectionLabel(
                      _type == RouteIssueType.other
                          ? 'What is wrong?'
                          : 'Anything to add? (optional)',
                    ),
                    _field(
                      controller: _note,
                      hint: _type!.hint,
                      maxLines: 3,
                      maxLength: 500,
                    ),
                  ],
                  const SizedBox(height: 12),
                  ..._actions(),
                ],
              ),
            ),
      ),
    );
  }

  List<Widget> _actions() {
    final drawsFix = widget.canDrawFix && _type == RouteIssueType.wrongPath;
    if (drawsFix) {
      return [
        FilledButton.icon(
          onPressed: () => _send(drawFix: true),
          icon: const Icon(Icons.draw_outlined, size: 18),
          label: const TranslatedText('Draw the right way'),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: _send,
          child: const TranslatedText('Just report it'),
        ),
      ];
    }
    return [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _danger),
        onPressed: _canSend ? _send : null,
        icon: const Icon(Icons.flag_outlined, size: 18),
        label: const TranslatedText('Send report'),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const TranslatedText('Cancel'),
      ),
    ];
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: TranslatedText(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    ),
  );

  Widget _typeOption(RouteIssueType type) {
    final selected = _type == type;
    return _option(
      selected: selected,
      onTap: () => setState(() => _type = type),
      title: type.label,
      subtitle: type.hint,
    );
  }

  Widget _rideOption(ProblemTarget target) {
    return _option(
      selected: identical(_target, target),
      onTap: () => setState(() => _target = target),
      title: target.label,
    );
  }

  Widget _option({
    required bool selected,
    required VoidCallback onTap,
    required String title,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.accentSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    selected
                        ? _accent.withValues(alpha: 0.4)
                        : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? _accent : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TranslatedText(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        TranslatedText(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}
