import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The same tightly framed, transparent wordmark on every HireD screen.
class HireDLogo extends StatelessWidget {
  const HireDLogo({super.key, this.width = 120});
  final double width;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'HireD',
    image: true,
    child: ExcludeSemantics(
      child: SvgPicture.asset(
        'assets/hired-logo.svg',
        width: width,
        height: width / 3.05,
        fit: BoxFit.contain,
      ),
    ),
  );
}
