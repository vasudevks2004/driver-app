import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/auth_config.dart';
import 'package:hired_driver/design.dart';
import 'package:hired_driver/identity_auth.dart';
import 'package:hired_driver/onboarding.dart';
import 'package:hired_driver/onboarding_screen.dart';

class _Service extends DriverOnboarding {
  _Service()
    : super(const DriverAuthConfig(supabaseUrl: '', publishableKey: ''));
  final data = <String, dynamic>{'id': 'application-test', 'status': 'draft'};
  int submissions = 0;
  String? submittedAadhaar;
  @override
  Future<DriverApplication> open(
    String token, {
    required String name,
    required String city,
  }) async => DriverApplication({...data});
  @override
  Future<DriverApplication> saveDraft(
    String token,
    Map<String, dynamic> details,
  ) async {
    data.addAll(details);
    return DriverApplication({...data});
  }

  @override
  Future<DriverApplication> upload(
    String token,
    String kind,
    Uint8List bytes,
  ) async {
    data['${kind}_uploaded'] = true;
    return DriverApplication({...data});
  }

  @override
  Future<DriverApplication> submit(
    String token, {
    required String licenceNumber,
    required String aadhaarNumber,
    required DateTime birthDate,
    required DateTime licenceExpiry,
    required String vehicleClass,
  }) async {
    submissions++;
    submittedAadhaar = aadhaarNumber;
    data.addAll({
      'status': 'submitted',
      'aadhaar_last4': aadhaarNumber.substring(8),
    });
    return DriverApplication({...data});
  }

  @override
  Future<Uri> startDigiLocker(
    String token,
  ) async => throw const DriverAuthException(
    'DigiLocker is being set up. You can upload your licence photos instead.',
  );
}

void main() {
  late _Service service;
  setUp(() => service = _Service());
  tearDown(() => service.dispose());
  Future<void> open(WidgetTester tester, {bool cameraDenied = false}) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: HireDStyle.theme(),
        home: DriverOnboardingScreen(
          service: service,
          session: const IdentitySession('applicant-only', 'refresh', 3600),
          fullName: 'Test Driver',
          city: 'Kochi',
          onClose: () async {},
          pickImage: (_, _) async {
            if (cameraDenied)
              throw PlatformException(code: 'camera_access_denied');
            return base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aRZkAAAAASUVORK5CYII=',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        240,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> licence(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('licence-number')),
      'KL07 20201234567',
    );
    await tap(tester, find.text('Date of birth'));
    await tap(tester, find.text('OK'));
    await tap(tester, find.text('Licence expiry'));
    await tap(tester, find.text('OK'));
    for (final kind in ['front', 'back']) {
      await tap(tester, find.byKey(Key('onboarding-licence-$kind')));
      await tap(tester, find.text('Choose from photos'));
    }
    await tap(tester, find.byKey(const Key('onboarding-next')));
  }

  Future<void> identityPhotos(WidgetTester tester) async {
    await tap(tester, find.byKey(const Key('onboarding-aadhaar')));
    await tap(tester, find.text('Choose from photos'));
    await tap(tester, find.byKey(const Key('onboarding-selfie')));
    for (final kind in ['pan', 'pcc']) {
      await tap(tester, find.byKey(Key('onboarding-$kind')));
      await tap(tester, find.text('Choose from photos'));
    }
  }

  testWidgets(
    'denied camera access stays unconfirmed and offers a useful recovery message',
    (tester) async {
      await open(tester, cameraDenied: true);
      await tap(tester, find.byKey(const Key('onboarding-licence-front')));
      await tap(tester, find.text('Take a photo'));
      expect(
        find.textContaining('Camera or photo access is unavailable'),
        findsOneWidget,
      );
      expect(service.data['licence_front_uploaded'], isNot(true));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guided licence controls fit a narrow phone', (tester) async {
    await open(tester);
    expect(find.text('Your driving licence.'), findsOneWidget);
    await licence(tester);
    expect(find.byKey(const Key('aadhaar-number')), findsOneWidget);
    await identityPhotos(tester);
    expect(service.data['selfie_uploaded'], isTrue);
    expect(service.data['aadhaar_uploaded'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Aadhaar number and photo are required before review; number is masked by default',
    (tester) async {
      await open(tester);
      await licence(tester);
      final input = tester.widget<TextFormField>(
        find.byKey(const Key('aadhaar-number')),
      );
      expect(input.controller!.text, isEmpty);
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('aadhaar-number')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.obscureText, isTrue);
      await tester.enterText(find.byKey(const Key('aadhaar-number')), '12345');
      await tap(tester, find.byKey(const Key('onboarding-next')));
      expect(
        find.text('Enter a valid 12-digit Aadhaar number'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('aadhaar-number')),
        '234567890123',
      );
      await tap(tester, find.byKey(const Key('onboarding-next')));
      expect(
        find.text('Add your Aadhaar card photo and take a selfie to continue.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('submit-driver-application')), findsNothing);
      expect(service.submissions, 0);
    },
  );

  testWidgets(
    'documents, masked Aadhaar review and consent lead to a receipt',
    (tester) async {
      await open(tester);
      await licence(tester);
      await tester.enterText(
        find.byKey(const Key('aadhaar-number')),
        '234567890123',
      );
      await identityPhotos(tester);
      await tap(tester, find.byKey(const Key('onboarding-next')));
      expect(find.text('Everything look right?'), findsOneWidget);
      expect(find.text('•••• •••• 0123'), findsOneWidget);
      expect(find.text('234567890123'), findsNothing);
      await tap(tester, find.byKey(const Key('submit-driver-application')));
      expect(service.submissions, 0);
      expect(
        find.text('Please agree to the document review and profile photo use.'),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('onboarding-consent')));
      await tap(tester, find.byKey(const Key('submit-driver-application')));
      expect(service.submissions, 1);
      expect(service.submittedAadhaar, '234567890123');
      expect(find.text('You’re on your way.'), findsOneWidget);
      expect(find.textContaining('application-test'), findsOneWidget);
      expect(find.textContaining('234567890123'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back navigation keeps entered details without exposing the Aadhaar number',
    (tester) async {
      await open(tester);
      await licence(tester);
      await tester.enterText(
        find.byKey(const Key('aadhaar-number')),
        '234567890123',
      );
      await identityPhotos(tester);
      await tap(tester, find.byKey(const Key('onboarding-next')));
      await tap(tester, find.text('Go back'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('aadhaar-number')))
            .controller!
            .text,
        '234567890123',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('aadhaar-number')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'DigiLocker requires consent and unavailable service never shows success',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('connect-digilocker')));
      expect(find.text('Share your driving licence?'), findsOneWidget);
      await tap(tester, find.text('Continue to DigiLocker'));
      expect(
        find.textContaining('DigiLocker is being set up.'),
        findsOneWidget,
      );
      expect(find.textContaining('Issued licence received.'), findsNothing);
    },
  );
}
