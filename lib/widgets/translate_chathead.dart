import 'package:flutter/material.dart';

import '../services/translation_service.dart';

const _bg = Color(0xFFF4F8FF);
const _surface = Color(0xFFFFFFFF);
const _surfaceAlt = Color(0xFFEAF2FF);
const _accent = Color(0xFF2E7CF6);
const _accentSoft = Color(0x1A2E7CF6);
const _textPrimary = Color(0xFF0F1D35);
const _textSecondary = Color(0xFF7A92B2);
const _border = Color(0xFFD4E4F7);
const _danger = Color(0xFFE05C6A);

class TranslateChatHead extends StatefulWidget {
  const TranslateChatHead({super.key});

  @override
  State<TranslateChatHead> createState() => _TranslateChatHeadState();
}

class _TranslateChatHeadState extends State<TranslateChatHead> {
  static const double _bubbleSize = 58;
  static const double _edgePadding = 12;
  Offset? _offset;

  Offset _bottomRightStart(BoxConstraints constraints) {
    return Offset(
      constraints.maxWidth - _bubbleSize - _edgePadding,
      constraints.maxHeight - _bubbleSize - _edgePadding,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _offset ??= _bottomRightStart(constraints);

        final clampedX = _offset!.dx.clamp(
          _edgePadding,
          constraints.maxWidth - _bubbleSize - _edgePadding,
        );
        final clampedY = _offset!.dy.clamp(
          _edgePadding,
          constraints.maxHeight - _bubbleSize - _edgePadding,
        );
        _offset = Offset(clampedX.toDouble(), clampedY.toDouble());

        return Stack(
          children: [
            Positioned(
              left: _offset!.dx,
              top: _offset!.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  setState(() {
                    final next = _offset! + details.delta;
                    _offset = Offset(
                      next.dx.clamp(
                        _edgePadding,
                        constraints.maxWidth - _bubbleSize - _edgePadding,
                      ),
                      next.dy.clamp(
                        _edgePadding,
                        constraints.maxHeight - _bubbleSize - _edgePadding,
                      ),
                    );
                  });
                },
                onTap: () => _openTranslator(context),
                child: _TranslateBubble(size: _bubbleSize),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openTranslator(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TranslatorSheet(),
    );
  }
}

class _TranslateBubble extends StatelessWidget {
  final double size;

  const _TranslateBubble({required this.size});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7CF6), Color(0xFF5AA9FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.26),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.translate_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}

class _TranslatorSheet extends StatefulWidget {
  const _TranslatorSheet();

  @override
  State<_TranslatorSheet> createState() => _TranslatorSheetState();
}

class _TranslatorSheetState extends State<_TranslatorSheet> {
  final TextEditingController _controller = TextEditingController();

  String _sourceLanguage = 'en';
  String _targetLanguage = 'en';
  bool _isLoading = false;
  String _translatedText = '';
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTranslate() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await TranslationService.translate(
        text: _controller.text,
        sourceLanguage: _sourceLanguage,
        targetLanguage: _targetLanguage,
      );

      if (!mounted) return;
      setState(() {
        _translatedText = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final insetBottom = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder:
          (context, scrollController) => Container(
            decoration: const BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.translate_rounded,
                          color: _accent,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Quick Translator',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: _border, height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + insetBottom),
                    children: [
                      Text(
                        'Offline-first ML Kit translation. Language models download on first use.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _textSecondary.withValues(alpha: 0.95),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border),
                        ),
                        child: TextField(
                          controller: _controller,
                          minLines: 3,
                          maxLines: 5,
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(
                            color: _textPrimary,
                            height: 1.35,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Text to translate',
                            hintText: 'Type your sentence here...',
                            filled: true,
                            fillColor: _surfaceAlt,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _accent,
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final useStackedLayout = constraints.maxWidth < 430;

                            final swapButton = InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () {
                                setState(() {
                                  final oldSource = _sourceLanguage;
                                  _sourceLanguage = _targetLanguage;
                                  _targetLanguage = oldSource;
                                });
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: _accentSoft,
                                  borderRadius: BorderRadius.circular(19),
                                  border: Border.all(
                                    color: _accent.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 20,
                                  color: _accent,
                                ),
                              ),
                            );

                            final fromDropdown = _LanguageDropdown(
                              label: 'From',
                              value: _sourceLanguage,
                              options: TranslationService.supportedLanguages,
                              onChanged: (value) {
                                setState(() => _sourceLanguage = value);
                              },
                            );

                            final toDropdown = _LanguageDropdown(
                              label: 'To',
                              value: _targetLanguage,
                              options: TranslationService.supportedLanguages,
                              onChanged: (value) {
                                setState(() => _targetLanguage = value);
                              },
                            );

                            if (useStackedLayout) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  fromDropdown,
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.center,
                                    child: swapButton,
                                  ),
                                  const SizedBox(height: 10),
                                  toDropdown,
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: fromDropdown),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: swapButton,
                                ),
                                Expanded(child: toDropdown),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _handleTranslate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _accent.withValues(
                              alpha: 0.4,
                            ),
                            disabledForegroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon:
                              _isLoading
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                  : const Icon(Icons.translate_rounded),
                          label: Text(
                            _isLoading ? 'Translating...' : 'Translate',
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFD5D5)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: _danger,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFF9F2A2A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_translatedText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(
                                    Icons.notes_rounded,
                                    size: 16,
                                    color: _accent,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Translation',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _translatedText,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: _textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<TranslationLanguage> options;
  final ValueChanged<String> onChanged;

  const _LanguageDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value:
          options.any((option) => option.code == value)
              ? value
              : options.first.code,
      isExpanded: true,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: _textSecondary,
      ),
      dropdownColor: _surface,
      items:
          options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option.code,
                  child: Text(
                    option.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _textPrimary, fontSize: 13),
                  ),
                ),
              )
              .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      style: const TextStyle(color: _textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: _surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.4),
        ),
      ),
    );
  }
}
