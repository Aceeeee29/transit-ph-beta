import 'dart:async';
import 'package:flutter/material.dart';
import '../models/location_search_result.dart';
import '../services/place_search_service.dart';
import '../theme/app_colors.dart';

class ContributeLocationSearchScreen extends StatefulWidget {
  final String initialQuery;

  const ContributeLocationSearchScreen({super.key, this.initialQuery = ''});

  @override
  State<ContributeLocationSearchScreen> createState() =>
      _ContributeLocationSearchScreenState();
}

class _ContributeLocationSearchScreenState
    extends State<ContributeLocationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  List<LocationSearchResult> _suggestions = [];
  bool _isLoadingSuggestions = false;

  static Color get _bg => AppColors.bg;
  static Color get _surface => AppColors.surface;
  static Color get _surfaceAlt => AppColors.surfaceAlt;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    if (widget.initialQuery.trim().isNotEmpty) {
      _scheduleSuggest(widget.initialQuery);
    }
  }

  void _submitQuery() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    // Manual submit — caller geocodes the raw query.
    Navigator.of(context).pop(query);
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _scheduleSuggest(value);
  }

  void _scheduleSuggest(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _isLoadingSuggestions = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _isLoadingSuggestions = true);
    final suggestions = await PlaceSearchService.suggest(query);
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _isLoadingSuggestions = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 15,
              color: _textSecondary,
            ),
          ),
        ),
        title: Text(
          'Search Location',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border, width: 1.5),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: _textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search location...',
                    hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _accent,
                      size: 20,
                    ),
                    suffixIcon:
                        _searchController.text.isNotEmpty
                            ? GestureDetector(
                              onTap: () {
                                _debounce?.cancel();
                                _searchController.clear();
                                setState(() {
                                  _suggestions = [];
                                  _isLoadingSuggestions = false;
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _border,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: _textSecondary,
                                ),
                              ),
                            )
                            : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 4,
                    ),
                  ),
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) => _submitQuery(),
                ),
              ),
              const SizedBox(height: 8),
              if (_isLoadingSuggestions)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accent,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Finding suggestions…',
                        style: TextStyle(color: _textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              if (!_isLoadingSuggestions && _suggestions.isNotEmpty)
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _suggestions.length,
                      separatorBuilder:
                          (_, __) =>
                              Divider(height: 1, indent: 48, color: _border),
                      itemBuilder: (_, index) {
                        final suggestion = _suggestions[index];
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(suggestion),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: _surfaceAlt,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.location_on_outlined,
                                    color: _accent,
                                    size: 17,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    suggestion.name,
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(
                                  Icons.north_west_rounded,
                                  size: 15,
                                  color: _textSecondary,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _submitQuery,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.my_location_rounded,
                        size: 18,
                        color: _surface,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Search on Map',
                        style: TextStyle(
                          color: _surface,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: _textSecondary,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap a suggestion to jump straight there, or use Search on Map for an exact match.',
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
