import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/auth.dart';
import 'package:hired_driver/auth_screen.dart';
import 'package:hired_driver/identity_auth.dart';

class _ScreenAuth extends DriverAuth {
  _ScreenAuth() : super('https://example.test/api/v1');
  int sends = 0;
  bool registered = false;
  bool rejectCode = false;
  bool googleCanceled = false;
  String? phone;
  String? name;

  @override
  Future<void> sendPhoneOtp(
    String value, {
    bool register = false,
    String? fullName,
    String? city,
  }) async {
    sends++;
    phone = value;
    registered = register;
    name = fullName;
  }

  @override
  Future<DriverSession> verifyPhoneOtp(String phone, String code) async {
    if (rejectCode)
      throw const DriverAuthException('The code is incorrect or expired.');
    throw const DriverActivationRequired();
  }

  @override
  Future<DriverSession?> loginWithGoogle() async {
    if (googleCanceled) return null;
    throw const DriverActivationRequired();
  }
}

void main() {
  late _ScreenAuth auth;
  setUp(() => auth = _ScreenAuth());
  tearDown(() => auth.dispose());

  Future<void> open(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverAuthScreen(auth: auth, onAuthenticated: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
    'login fits a narrow phone and offers Google and mobile sign-in',
    (tester) async {
      await open(tester, width: 320);
      expect(find.text('Welcome back.'), findsOneWidget);
      expect(find.byKey(const Key('google-sign-in')), findsOneWidget);
      expect(find.byKey(const Key('phone-number')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid phone cannot request an OTP', (tester) async {
    await open(tester);
    await tap(tester, find.text('Send OTP'));
    expect(find.text('Enter a valid mobile number'), findsOneWidget);
    expect(auth.sends, 0);
  });

  testWidgets(
    'register requires name and review acknowledgement, then opens OTP',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('open-register')));
      expect(find.text('Drive with HireD.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('register-name')),
        'Test Driver',
      );
      await tester.enterText(
        find.byKey(const Key('phone-number')),
        '9876543210',
      );
      await tester.enterText(find.byKey(const Key('register-city')), 'Kochi');
      await tap(tester, find.text('Verify mobile & continue'));
      expect(auth.sends, 0);
      await tap(tester, find.byKey(const Key('registration-acknowledgement')));
      await tap(tester, find.text('Verify mobile & continue'));
      expect(auth.registered, isTrue);
      expect(auth.phone, '+919876543210');
      expect(auth.name, 'Test Driver');
      expect(find.text('Verify your number.'), findsOneWidget);
      final resend = tester.widget<TextButton>(
        find.byKey(const Key('resend-otp')),
      );
      expect(resend.onPressed, isNull);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('Resend code'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('incorrect OTP stays on verification and can be corrected', (
    tester,
  ) async {
    auth.rejectCode = true;
    await open(tester);
    await tester.enterText(find.byKey(const Key('phone-number')), '9876543210');
    await tap(tester, find.text('Send OTP'));
    await tester.enterText(find.byKey(const Key('phone-otp')), '123456');
    await tap(tester, find.text('Verify & sign in'));
    expect(find.text('The code is incorrect or expired.'), findsOneWidget);
    expect(find.text('Verify your number.'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'verified applicant sees activation information instead of dashboard',
    (tester) async {
      await open(tester);
      await tap(tester, find.byKey(const Key('google-sign-in')));
      expect(find.text('Identity verified.'), findsOneWidget);
      await tap(tester, find.text('Back to sign in'));
      expect(find.text('Welcome back.'), findsOneWidget);
    },
  );

  testWidgets('Google cancellation keeps login available', (tester) async {
    auth.googleCanceled = true;
    await open(tester);
    await tap(tester, find.byKey(const Key('google-sign-in')));
    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.byKey(const Key('auth-error')), findsNothing);
  });

  testWidgets('email mode validates the existing credentials form', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.text('Email'));
    await tap(tester, find.text('Sign in'));
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsWidgets);
  });
}
