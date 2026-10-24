import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/development/preview_services.dart';
import 'package:hired_driver/identity_auth.dart';
import 'package:hired_driver/main_dev.dart';

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Development preview attempted to access the network.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PreviewOnboarding onboarding;
  late PreviewIdentityAuth identity;
  late PreviewDriverAuth auth;
  late _NoNetwork network;
  var now = DateTime(2026, 10, 24);
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    network = _NoNetwork(); HttpOverrides.global = network;
    now = DateTime(2026, 10, 24);
    onboarding = PreviewOnboarding();
    identity = PreviewIdentityAuth(clock: () => now);
    auth = PreviewDriverAuth(onboarding, identity: identity);
  });
  tearDown(() { auth.dispose(); onboarding.dispose(); HttpOverrides.global = null; });

  test('test OTP checks request, number, code, expiry and single use without real storage or HTTP', () async {
    await expectLater(auth.verifyPhoneOtp(previewPhone, previewOtp), throwsA(isA<DriverAuthException>()));
    await expectLater(auth.sendPhoneOtp('+919123456789'), throwsA(isA<DriverAuthException>()));
    await auth.sendPhoneOtp(previewPhone);
    await expectLater(auth.verifyPhoneOtp(previewPhone, '000000'), throwsA(isA<DriverAuthException>()));
    final session = await auth.verifyPhoneOtp(previewPhone, previewOtp);
    expect(session.token, startsWith('development-only-'));
    await expectLater(auth.verifyPhoneOtp(previewPhone, previewOtp), throwsA(isA<DriverAuthException>()));
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    expect(auth.baseUrl, isEmpty);
    expect(auth.identity.config.isConfigured, isFalse);
    expect(network.attempts, 0);
    await auth.logout(); expect(await auth.restore(), isNull);
  });

  test('test OTP resend cooldown and expiry match the displayed preview behavior', () async {
    await auth.sendPhoneOtp(previewPhone);
    await expectLater(auth.sendPhoneOtp(previewPhone), throwsA(isA<DriverAuthException>()));
    now = now.add(const Duration(minutes: 5));
    await expectLater(auth.verifyPhoneOtp(previewPhone, previewOtp), throwsA(isA<DriverAuthException>()));
    await auth.sendPhoneOtp(previewPhone);
    await auth.verifyPhoneOtp(previewPhone, previewOtp);
    expect(network.attempts, 0);
  });

  test('registration, licence images and selfie stay in memory and never grant a real account', () async {
    await auth.sendPhoneOtp(previewPhone, register: true, fullName: 'Test Driver', city: 'Kochi');
    final applicant = await auth.verifyRegistrationOtp(previewPhone, previewOtp);
    expect(auth.current, isNull);
    await onboarding.open(applicant.accessToken, name: 'Test Driver', city: 'Kochi');
    final image = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aRZkAAAAASUVORK5CYII=');
    for (final kind in ['selfie', 'licence_front', 'licence_back']) { await onboarding.upload(applicant.accessToken, kind, image); }
    final receipt = await onboarding.submit(applicant.accessToken, licenceNumber: 'KL0720201234567',
      birthDate: DateTime(1995), licenceExpiry: DateTime(2035), vehicleClass: 'LMV');
    expect(receipt.submitted, isTrue); expect(receipt.id, 'LOCAL-PREVIEW-001');
    await expectLater(onboarding.startDigiLocker(applicant.accessToken), throwsA(isA<DriverAuthException>()));
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    expect(network.attempts, 0);
  });

  testWidgets('debug app uses the actual login and dashboard with a visible local test banner', (tester) async {
    await tester.pumpWidget(const HireDDevelopmentApp()); await tester.pumpAndSettle();
    expect(find.byKey(const Key('development-banner')), findsOneWidget);
    expect(find.text('Welcome back.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone-number')), '9876543210');
    await tester.ensureVisible(find.text('Send OTP')); await tester.pumpAndSettle();
    await tester.tap(find.text('Send OTP')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone-otp')), '123456');
    await tester.ensureVisible(find.text('Verify & sign in')); await tester.pumpAndSettle();
    await tester.tap(find.text('Verify & sign in')); await tester.pumpAndSettle();
    expect(find.textContaining('Hello, Preview'), findsOneWidget);
    expect(find.byKey(const Key('development-banner')), findsOneWidget);
    expect(network.attempts, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
