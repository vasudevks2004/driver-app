import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hired_driver/main_dev.dart';
import 'package:hired_driver/development/preview_services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native startup, explicit preview sign-in and four tabs', (
    tester,
  ) async {
    final start = DateTime.now();
    await tester.pumpWidget(const HireDDevelopmentApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('development-banner')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('phone-number')),
      previewPhone.substring(3),
    );
    await tester.ensureVisible(find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone-otp')), previewOtp);
    await tester.ensureVisible(find.text('Verify & sign in'));
    await tester.tap(find.text('Verify & sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in ['Duties', 'Earnings', 'Profile', 'Home']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    // This is an explicit local preview, not evidence of provider delivery or backend access.
    debugPrint(
      'Native preview startup and navigation: ${DateTime.now().difference(start).inMilliseconds} ms',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
