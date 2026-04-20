import 'package:flutter/material.dart';

class ContributeLocationSearchScreen extends StatefulWidget {
  final String initialQuery;

  const ContributeLocationSearchScreen({
    super.key,
    this.initialQuery = '',
  });

  @override
  State<ContributeLocationSearchScreen> createState() =>
      _ContributeLocationSearchScreenState();
}

class _ContributeLocationSearchScreenState
    extends State<ContributeLocationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
  }

  void _submitQuery() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    Navigator.of(context).pop(query);
  }

  @override
  void dispose() {
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
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 15,
              color: _textSecondary,
            ),
          ),
        ),
        title: const Text(
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
                  style: const TextStyle(color: _textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search location...',
                    hintStyle: const TextStyle(
                      color: _textSecondary,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _accent,
                      size: 20,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            child: Container(
                              margin: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _border,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
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
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitQuery(),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _submitQuery,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.my_location_rounded, size: 18, color: _surface),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: _textSecondary, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Use specific place names or landmarks for better results.',
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
