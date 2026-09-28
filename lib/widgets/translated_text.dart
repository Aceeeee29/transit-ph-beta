import 'package:flutter/material.dart';
import '../services/app_language_service.dart';

/// Drop-in replacement for [Text] that auto-translates its string into the
/// app's selected language (Settings > Preferences > Language) using the
/// on-device ML Kit engine. Shows the original English text immediately and
/// swaps in the translation once it resolves; falls back silently to
/// English if translation isn't available.
class TranslatedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const TranslatedText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  State<TranslatedText> createState() => _TranslatedTextState();
}

class _TranslatedTextState extends State<TranslatedText> {
  late String _display = widget.text;

  @override
  void initState() {
    super.initState();
    AppLanguageService.languageCode.addListener(_onLanguageChanged);
    _translate();
  }

  @override
  void didUpdateWidget(covariant TranslatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _display = widget.text;
      _translate();
    }
  }

  @override
  void dispose() {
    AppLanguageService.languageCode.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() => _translate();

  Future<void> _translate() async {
    if (AppLanguageService.isEnglish) {
      if (mounted && _display != widget.text) {
        setState(() => _display = widget.text);
      }
      return;
    }
    final result = await AppLanguageService.translate(widget.text);
    if (mounted) setState(() => _display = result);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder:
          (child, animation) =>
              FadeTransition(opacity: animation, child: child),
      layoutBuilder:
          (currentChild, previousChildren) => Stack(
            alignment: Alignment.centerLeft,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
      child: Text(
        _display,
        key: ValueKey(_display),
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      ),
    );
  }
}
