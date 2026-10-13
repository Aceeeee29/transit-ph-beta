import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// The Map tab's bottom drawer. It rests at [peekHeight] showing the handle
/// line and [header] (like the "Local vibe" bar in Google Maps), and drags
/// up to show [children].
class MapDrawer extends StatelessWidget {
  final DraggableScrollableController controller;
  final double peekHeight;
  final Widget header;
  final List<Widget> children;

  /// Highest the drawer goes, as a fraction of the space it sits in.
  final double maxFraction;

  const MapDrawer({
    super.key,
    required this.controller,
    required this.peekHeight,
    required this.header,
    required this.children,
    this.maxFraction = 0.7,
  });

  static const handleHeight = 22.0;
  static Color get _surface => AppColors.surface;
  static Color get _handle => AppColors.border;

  /// Opens the drawer about halfway, or fully with [full].
  static void open(
    DraggableScrollableController controller, {
    bool full = false,
  }) {
    if (!controller.isAttached) return;
    controller.animateTo(
      full ? 0.7 : 0.45,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Back to the resting height.
  static void close(DraggableScrollableController controller, double minSize) {
    if (!controller.isAttached) return;
    controller.animateTo(
      minSize,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final max = maxFraction;
        final min = (peekHeight / height).clamp(0.05, max - 0.05).toDouble();
        const mid = 0.45;
        return DraggableScrollableSheet(
          controller: controller,
          initialChildSize: min,
          minChildSize: min,
          maxChildSize: max,
          snap: true,
          snapSizes: [if (mid > min + 0.05 && mid < max - 0.05) mid],
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 16,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!controller.isAttached) return;
                        if (controller.size > min + 0.02) {
                          close(controller, min);
                        } else {
                          open(controller);
                        }
                      },
                      child: SizedBox(
                        height: handleHeight,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _handle,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: peekHeight - handleHeight, child: header),
                    ...children,
                    SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
