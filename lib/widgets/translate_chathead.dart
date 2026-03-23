import 'package:flutter/material.dart';

import '../services/translation_service.dart';

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
      showDragHandle: true,
      backgroundColor: Colors.white,
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
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF2E7CF6), Color(0xFF5AA9FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.translate_rounded, color: Colors.white, size: 28),
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + insetBottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick Translator',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Offline-first ML Kit translation. Language models will download on first use.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Text to translate',
                  hintText: 'Type here...',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _LanguageDropdown(
                      label: 'From',
                      value: _sourceLanguage,
                      options: TranslationService.supportedLanguages,
                      onChanged: (value) {
                        setState(() => _sourceLanguage = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        final oldSource = _sourceLanguage;
                        _sourceLanguage = _targetLanguage;
                        _targetLanguage = oldSource;
                      });
                    },
                    icon: const Icon(Icons.swap_horiz_rounded),
                    tooltip: 'Swap languages',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LanguageDropdown(
                      label: 'To',
                      value: _targetLanguage,
                      options: TranslationService.supportedLanguages,
                      onChanged: (value) {
                        setState(() => _targetLanguage = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleTranslate,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.translate_rounded),
                  label: Text(_isLoading ? 'Translating...' : 'Translate'),
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
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFF9F2A2A)),
                  ),
                ),
              ],
              if (_translatedText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDCE9FF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Translation',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E5AA7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _translatedText,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
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
      value: options.any((option) => option.code == value)
          ? value
          : options.first.code,
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.code,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      decoration: InputDecoration(labelText: label),
    );
  }
}
