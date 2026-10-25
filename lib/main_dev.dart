// Explicit debug-only entry point. Production main.dart never imports this file.
import 'package:flutter/material.dart';

import 'development/preview_services.dart';
import 'main.dart' show DriverHome;
import 'design.dart';

void main() {
  requireDevelopmentBuild();
  runApp(const HireDDevelopmentApp());
}

class HireDDevelopmentApp extends StatefulWidget {
  const HireDDevelopmentApp({super.key});
  @override
  State<HireDDevelopmentApp> createState() => _HireDDevelopmentAppState();
}

class _HireDDevelopmentAppState extends State<HireDDevelopmentApp> {
  late final application = PreviewOnboarding();
  late final auth = PreviewDriverAuth(application);

  @override
  void dispose() {
    application.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HireD · Local OTP Preview',
    debugShowCheckedModeBanner: false,
    theme: HireDStyle.theme(),
    builder: (context, child) => Column(
      children: [
        Material(
          color: const Color(0xFFFFE7A5),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Text(
                'LOCAL TEST · No SMS or real account\n+91 9876543210 · Code 123456\nPhotos and applications stay in memory.',
                key: const Key('development-banner'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5C4200),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    ),
    home: DriverHome(authOverride: auth, onboardingOverride: application),
  );
}
