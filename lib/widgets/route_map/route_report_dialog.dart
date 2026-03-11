import 'package:flutter/material.dart';

// ─── Color tokens ─────────────────────────────────────────────────────────────
const _bg = Color(0xFFF4F8FF);
const _surface = Color(0xFFFFFFFF);
const _surfaceAlt = Color(0xFFEAF2FF);
const _accent = Color(0xFF2E7CF6);
const _accentSoft = Color(0x1A2E7CF6);
const _textPrimary = Color(0xFF0F1D35);
const _textSecondary = Color(0xFF7A92B2);
const _border = Color(0xFFD4E4F7);
const _danger = Color(0xFFE05C6A);

const Map<String, List<String>> reportCategories = {
  'Traffic-Related': [
    'Heavy traffic / congestion',
    'Road closure / construction',
    'Detour / alternative route',
    'Slow-moving vehicles',
  ],
  'Safety-Related': [
    'Accident / crash',
    'Hazard on road',
    'Crime / suspicious activity',
  ],
  'Transit-Specific': [
    'Bus/train delay',
    'Cancelled service',
    'Crowding / full capacity',
  ],
  'Weather-Related': [
    'Flooding / water logging',
    'Landslide / mudslide',
    'Storm / lightning hazard',
  ],
};

/// Shows the report issue bottom sheet.
/// [onSubmit] receives (type, description) and handles actual submission.
void showRouteReportDialog(
  BuildContext context, {
  required void Function(String type, String description) onSubmit,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RouteReportSheet(onSubmit: onSubmit),
  );
}

class _RouteReportSheet extends StatefulWidget {
  final void Function(String type, String description) onSubmit;

  const _RouteReportSheet({required this.onSubmit});

  @override
  State<_RouteReportSheet> createState() => _RouteReportSheetState();
}

class _RouteReportSheetState extends State<_RouteReportSheet> {
  String? _selectedType;
  String _description = '';

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(),
            const Divider(color: _border, height: 1),
            Expanded(
              child: _buildContent(scrollController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: _border,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.report_problem_outlined,
              color: _danger,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Report an Issue',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        ...reportCategories.entries.map(_buildCategoryTile),
        const SizedBox(height: 4),
        _buildDescriptionField(),
        const SizedBox(height: 16),
        _buildActions(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCategoryTile(MapEntry<String, List<String>> entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Text(
            entry.key,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          iconColor: _accent,
          collapsedIconColor: _textSecondary,
          children: entry.value.map(_buildReportOption).toList(),
        ),
      ),
    );
  }

  Widget _buildReportOption(String type) {
    final selected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _accentSoft : _surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? _accent.withOpacity(0.35) : _border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _RadioCircle(selected: selected),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                type,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? _textPrimary : _textSecondary,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: TextField(
        onChanged: (val) => _description = val,
        maxLines: 3,
        style: const TextStyle(color: _textPrimary, fontSize: 14),
        decoration: const InputDecoration(
          hintText: 'Additional description (optional)',
          hintStyle: TextStyle(color: _textSecondary, fontSize: 13),
          prefixIcon: Icon(
            Icons.edit_note_outlined,
            color: _accent,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        ),
      ),
    );
  }

  Widget _buildActions() {
    final canSubmit = _selectedType != null;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: canSubmit
                ? () {
                    widget.onSubmit(_selectedType!, _description);
                    Navigator.pop(context);
                  }
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 46,
              decoration: BoxDecoration(
                gradient: canSubmit
                    ? const LinearGradient(
                        colors: [Color(0xFFE05C6A), Color(0xFFEA8A94)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: canSubmit ? null : _border,
                borderRadius: BorderRadius.circular(12),
                boxShadow: canSubmit
                    ? [
                        BoxShadow(
                          color: _danger.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.flag_outlined,
                    color: canSubmit ? Colors.white : _textSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Submit Report',
                    style: TextStyle(
                      color: canSubmit ? Colors.white : _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RadioCircle extends StatelessWidget {
  final bool selected;
  const _RadioCircle({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? _accent : _border,
          width: 2,
        ),
        color: selected ? _accent : Colors.transparent,
      ),
      child: selected
          ? const Icon(Icons.check, size: 10, color: Colors.white)
          : null,
    );
  }
}
