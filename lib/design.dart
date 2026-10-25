import 'package:flutter/material.dart';

/// Shared visual language for sign-in, onboarding and the driver's workspace.
abstract final class HireDStyle {
  static const primary = Color(0xFF5055E8);
  static const ink = Color(0xFF1E2433);
  static const muted = Color(0xFF667085);
  static const canvas = Color(0xFFF6F7FB);
  static const line = Color(0xFFE7EAF1);
  static const tint = Color(0xFFEEEEFF);
  static const success = Color(0xFF087A56);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primary,
        surface: Colors.white,
        onSurface: ink,
        outline: line,
        error: Color(0xFFB42318),
      ),
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        hintStyle: const TextStyle(color: muted, fontSize: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: ink,
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: tint,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? primary : muted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}

class HireDCard extends StatelessWidget {
  const HireDCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: color == Colors.white ? HireDStyle.line : Colors.transparent,
      ),
    ),
    child: child,
  );
}

class HireDBadge extends StatelessWidget {
  const HireDBadge(
    this.label, {
    super.key,
    this.color = HireDStyle.primary,
    this.dot = false,
  });
  final String label;
  final Color color;
  final bool dot;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}

class HireDEmptyState extends StatelessWidget {
  const HireDEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => HireDCard(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: const BoxDecoration(
            color: HireDStyle.tint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: HireDStyle.primary, size: 26),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: HireDStyle.muted,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}

class HireDSteps extends StatelessWidget {
  const HireDSteps({super.key, required this.labels, required this.current});
  final List<String> labels;
  final int current;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: List.generate(
      labels.length,
      (index) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8),
          child: Semantics(
            label:
                'Step ${index + 1} of ${labels.length}, ${labels[index]}${index == current
                    ? ', current'
                    : index < current
                    ? ', complete'
                    : ''}',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: index <= current
                          ? HireDStyle.primary
                          : HireDStyle.line,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (index < current) ...[
                        const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: HireDStyle.primary,
                        ),
                        const SizedBox(width: 5),
                      ] else
                        Text(
                          '${index + 1}  ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: index <= current
                                ? HireDStyle.primary
                                : HireDStyle.muted,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          labels[index],
                          style: TextStyle(
                            fontSize: 12,
                            color: index <= current
                                ? HireDStyle.primary
                                : HireDStyle.muted,
                            fontWeight: index == current
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class HireDNotice extends StatelessWidget {
  const HireDNotice(
    this.text, {
    super.key,
    this.error = false,
    this.icon = Icons.lock_outline,
  });
  final String text;
  final bool error;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: error,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFF1EE) : HireDStyle.tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : icon,
            size: 18,
            color: error ? const Color(0xFFB42318) : HireDStyle.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: error ? const Color(0xFFB42318) : HireDStyle.ink,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
