import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/auth_config.dart';
import 'package:hired_driver/identity_auth.dart';
import 'package:hired_driver/onboarding.dart';
import 'package:hired_driver/onboarding_screen.dart';

class _Service extends DriverOnboarding {
  _Service() : super(const DriverAuthConfig(supabaseUrl: '', publishableKey: ''));
  final data = <String, dynamic>{'id': 'application-test', 'status': 'draft'};
  int submissions = 0;
  @override
  Future<DriverApplication> open(String token, {required String name, required String city}) async => DriverApplication({...data});
  @override
  Future<DriverApplication> upload(String token, String kind, Uint8List bytes) async {
    data['${kind}_uploaded'] = true;
    return DriverApplication({...data});
  }
  @override
  Future<DriverApplication> submit(String token, {required String licenceNumber, required DateTime birthDate, required DateTime licenceExpiry, required String vehicleClass}) async {
    submissions++;
    data['status'] = 'submitted';
    return DriverApplication({...data});
  }
  @override
  Future<Uri> startDigiLocker(String token) async =>
    throw const DriverAuthException('DigiLocker is being set up. You can upload your licence photos instead.');
}

void main() {
  late _Service service;
  setUp(() => service = _Service());
  tearDown(() => service.dispose());
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: DriverOnboardingScreen(service: service,
      session: const IdentitySession('applicant-only', 'refresh', 3600), fullName: 'Test Driver', city: 'Kochi',
      onClose: () async {},
      pickImage: (_, _) async => base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aRZkAAAAASUVORK5CYII='))));
    await tester.pumpAndSettle();
  }
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder); await tester.tap(finder); await tester.pumpAndSettle();
  }

  testWidgets('registration documents and selfie fit a narrow phone', (tester) async {
    await open(tester);
    expect(find.text('Complete your driver profile.'), findsOneWidget);
    await tap(tester, find.byKey(const Key('onboarding-selfie')));
    expect(service.data['selfie_uploaded'], isTrue);
    await tester.ensureVisible(find.byKey(const Key('connect-digilocker')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('licence, photos, selfie and consent lead to an application receipt', (tester) async {
    await open(tester);
    await tap(tester, find.byKey(const Key('onboarding-selfie')));
    await tester.enterText(find.byKey(const Key('licence-number')), 'KL07 20201234567');
    await tap(tester, find.text('Date of birth')); await tap(tester, find.text('OK'));
    await tap(tester, find.text('Licence expiry')); await tap(tester, find.text('OK'));
    for (final kind in ['front', 'back']) {
      await tap(tester, find.byKey(Key('onboarding-licence-$kind')));
      await tap(tester, find.text('Choose from photos'));
    }
    await tap(tester, find.byKey(const Key('submit-driver-application')));
    expect(service.submissions, 0);
    expect(find.text('Please agree to the document review and profile photo use.'), findsOneWidget);
    await tap(tester, find.byKey(const Key('onboarding-consent')));
    await tap(tester, find.byKey(const Key('submit-driver-application')));
    expect(service.submissions, 1);
    expect(find.text('Application submitted.'), findsOneWidget);
    expect(find.textContaining('application-test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DigiLocker requires consent and unavailable service never shows success', (tester) async {
    await open(tester);
    await tap(tester, find.byKey(const Key('connect-digilocker')));
    expect(find.text('Share your driving licence?'), findsOneWidget);
    await tap(tester, find.text('Continue to DigiLocker'));
    expect(find.textContaining('DigiLocker is being set up.'), findsOneWidget);
    expect(find.textContaining('Issued licence received.'), findsNothing);
  });
}
