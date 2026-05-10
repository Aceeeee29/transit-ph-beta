import 'package:flutter/material.dart';

class FareDiscountToggle extends StatelessWidget {
  static const String defaultLabel = 'Student / PWD / Senior';

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry padding;
  final BoxDecoration? decoration;
  final TextStyle? labelStyle;
  final Color iconColor;
  final double iconSize;
  final Color? activeColor;

  const FareDiscountToggle({
    super.key,
    this.label = defaultLabel,
    required this.value,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
    this.decoration,
    this.labelStyle,
    this.iconColor = Colors.grey,
    this.iconSize = 16,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(Icons.badge_outlined, size: iconSize, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: labelStyle,
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: activeColor,
        ),
      ],
    );

    if (decoration != null) {
      return Container(
        padding: padding,
        decoration: decoration,
        child: row,
      );
    }

    return Padding(
      padding: padding,
      child: row,
    );
  }
}
