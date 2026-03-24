import 'package:flutter/material.dart';

class ContributeLocationSearchBar extends StatefulWidget {
  final Future<bool> Function(String query) onSearch;
  final Color surface;
  final Color border;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  const ContributeLocationSearchBar({
    super.key,
    required this.onSearch,
    required this.surface,
    required this.border,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  State<ContributeLocationSearchBar> createState() =>
      _ContributeLocationSearchBarState();
}

class _ContributeLocationSearchBarState
    extends State<ContributeLocationSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _isSearching) return;

    setState(() => _isSearching = true);
    final success = await widget.onSearch(query);
    if (!mounted) return;

    setState(() => _isSearching = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not found. Try a more specific place.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: widget.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.border),
        boxShadow: [
          BoxShadow(
            color: widget.accent.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(Icons.search_rounded, color: widget.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: 13,
                color: widget.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Search location',
                hintStyle: TextStyle(
                  color: widget.textSecondary,
                  fontSize: 12,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          if (_searchController.text.isNotEmpty && !_isSearching)
            IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: Icon(
                Icons.close_rounded,
                color: widget.textSecondary,
                size: 18,
              ),
              splashRadius: 16,
              tooltip: 'Clear',
            ),
          SizedBox(
            width: 38,
            child: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    onPressed: _search,
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    color: widget.accent,
                    splashRadius: 18,
                    tooltip: 'Search',
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
