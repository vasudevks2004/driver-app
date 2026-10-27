import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/auth.dart';
import 'package:hired_driver/auth_config.dart';
import 'package:hired_driver/auth_validation.dart';
import 'package:hired_driver/identity_auth.dart';

// A local HTTP stand-in for the documented Supabase Auth and HireD contracts.
// Requests use the real HTTP transport; no HttpClient/MockClient is substituted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late HttpServer server;
  late DriverAuth auth;
  late SupabaseIdentityAuth identity;
  late List<Map<String, dynamic>> calls;
  var identityStatus = 200;
  var profileStatus = 200;
  var identityError = <String, dynamic>{};
  var htmlResponse = false;
  var googleCanceled = false;
  var profileRole = 'driver';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    calls = [];
    identityStatus = 200;
    profileStatus = 200;
    identityError = {};
    htmlResponse = false;
    googleCanceled = false;
    profileRole = 'driver';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final raw = await utf8.decoder.bind(request).join();
      final data = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map;
      calls.add({
        'path': request.uri.path,
        'query': request.uri.query,
        'method': request.method,
        'body': data,
        'authorization': request.headers.value('authorization'),
        'apikey': request.headers.value('apikey'),
      });
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      if (path == '/auth/v1/logout') {
        request.response.statusCode = 204;
      } else if (path == '/api/v1/drivers/me') {
        request.response.statusCode = profileStatus;
        request.response.write(
          jsonEncode(
            profileStatus == 200
                ? {
                    'data': {
                      'id': 'driver-1',
                      'name': 'Test Driver',
                      'role': profileRole,
                    },
                  }
                : {
                    'error': {'message': 'Driver profile is unavailable.'},
                  },
          ),
        );
      } else if (path == '/api/v1/auth/driver/refresh') {
        request.response.statusCode = profileStatus;
        request.response.write(
          jsonEncode(
            profileStatus == 200
                ? {
                    'data': {
                      'token': 'renewed-access',
                      'refreshToken': 'rotated-refresh',
                      'expiresIn': 3600,
                      'profile': {'id': 'driver-1', 'role': profileRole},
                    },
                  }
                : {
                    'error': {'message': 'Driver access was revoked.'},
                  },
          ),
        );
      } else if (path == '/auth/v1/otp') {
        request.response.statusCode = identityStatus;
        request.response.write(
          htmlResponse
              ? '<h1>Unavailable</h1>'
              : jsonEncode(identityStatus == 200 ? {} : identityError),
        );
      } else if (path == '/auth/v1/verify' || path == '/auth/v1/token') {
        request.response.statusCode = identityStatus;
        request.response.write(
          jsonEncode(
            identityStatus == 200
                ? {
                    'access_token': 'verified-access',
                    'refresh_token': 'verified-refresh',
                    'expires_in': 3600,
                  }
                : identityError,
          ),
        );
      } else {
        request.response.statusCode = 501;
        request.response.write(
          jsonEncode({'error': 'Not modeled by this contract stand-in.'}),
        );
      }
      await request.response.close();
    });
    final origin = 'http://127.0.0.1:${server.port}';
    identity = SupabaseIdentityAuth(
      DriverAuthConfig(
        supabaseUrl: origin,
        publishableKey: 'sb_publishable_test',
      ),
      googleTokenProvider: () async => googleCanceled
          ? null
          : const GoogleIdentityTokens(
              'google-id-proof',
              'google-access-proof',
            ),
    );
    auth = DriverAuth('$origin/api/v1', identity: identity);
  });

  tearDown(() async {
    auth.dispose();
    await server.close(force: true);
  });

  test('phone login sends SMS without creating an account', () async {
    await auth.sendPhoneOtp('+919876543210');
    expect(calls.single['path'], '/auth/v1/otp');
    expect(calls.single['body'], {
      'phone': '+919876543210',
      'channel': 'sms',
      'create_user': false,
    });
    expect(calls.single['apikey'], 'sb_publishable_test');
    expect(auth.current, isNull);
  });

  test(
    'registration sends contact metadata and never grants a driver role',
    () async {
      await auth.sendPhoneOtp(
        '+919876543210',
        register: true,
        fullName: '  Test Driver ',
        city: ' Kochi ',
      );
      final body = calls.single['body'] as Map;
      expect(body['create_user'], isTrue);
      expect(body['data'], {
        'full_name': 'Test Driver',
        'city': 'Kochi',
        'onboarding_intent': 'driver',
      });
      expect((body['data'] as Map).containsKey('role'), isFalse);
      expect(auth.current, isNull);
    },
  );

  test(
    'OTP opens a driver session only after the server verifies membership',
    () async {
      await auth.sendPhoneOtp('+919876543210');
      final session = await auth.verifyPhoneOtp('+919876543210', '123456');
      expect(session.profile['role'], 'driver');
      expect(auth.current?.token, 'verified-access');
      expect(calls[1]['body'], {
        'phone': '+919876543210',
        'token': '123456',
        'type': 'sms',
      });
      expect(calls.last['path'], '/api/v1/drivers/me');
      expect(calls.last['authorization'], 'Bearer verified-access');
      expect(
        await const FlutterSecureStorage().read(key: 'hired.driver.session.v1'),
        isNotNull,
      );
    },
  );

  test(
    'Google exchanges provider proof and verifies the HireD driver profile',
    () async {
      final session = await auth.loginWithGoogle();
      expect(calls.first['query'], 'grant_type=id_token');
      expect(calls.first['body'], {
        'provider': 'google',
        'id_token': 'google-id-proof',
        'access_token': 'google-access-proof',
      });
      expect(session?.profile['role'], 'driver');
      expect(calls.last['path'], '/api/v1/drivers/me');
    },
  );

  for (final provider in ['phone', 'google']) {
    test(
      '$provider sessions send their Supabase refresh token to the gateway and save rotation',
      () async {
        if (provider == 'phone') {
          await auth.verifyPhoneOtp('+919876543210', '123456');
        } else {
          await auth.loginWithGoogle();
        }
        final renewed = await auth.refresh();
        expect(calls.last['path'], '/api/v1/auth/driver/refresh');
        expect(calls.last['body'], {'refreshToken': 'verified-refresh'});
        expect(renewed.token, 'renewed-access');
        expect(auth.current?.refreshToken, 'rotated-refresh');
        profileStatus = 403;
        await expectLater(auth.refresh(), throwsA(isA<Exception>()));
        expect(auth.current, isNull);
      },
    );
  }

  test(
    'canceling Google makes no HTTP requests and creates no session',
    () async {
      googleCanceled = true;
      expect(await auth.loginWithGoogle(), isNull);
      expect(calls, isEmpty);
      expect(auth.current, isNull);
    },
  );

  test(
    'identity without driver access is revoked and does not unlock the app',
    () async {
      profileStatus = 403;
      await expectLater(
        auth.verifyPhoneOtp('+919876543210', '123456'),
        throwsA(isA<DriverActivationRequired>()),
      );
      expect(calls.last['path'], '/auth/v1/logout');
      expect(calls.last['authorization'], 'Bearer verified-access');
      expect(auth.current, isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'hired.driver.session.v1'),
        isNull,
      );
    },
  );

  test('a non-driver profile cannot be stored as a driver session', () async {
    profileRole = 'admin';
    await expectLater(auth.loginWithGoogle(), throwsA(isA<FormatException>()));
    expect(auth.current, isNull);
    expect(calls.last['path'], '/auth/v1/logout');
  });

  test('wrong or expired OTP stays signed out', () async {
    identityStatus = 403;
    identityError = {'error_code': 'otp_expired'};
    await expectLater(
      auth.verifyPhoneOtp('+919876543210', '123456'),
      throwsA(
        isA<DriverAuthException>().having(
          (e) => e.message,
          'message',
          contains('incorrect or expired'),
        ),
      ),
    );
    expect(calls.length, 1);
    expect(auth.current, isNull);
  });

  test('rate limiting produces a retry message', () async {
    identityStatus = 429;
    await expectLater(
      auth.sendPhoneOtp('+919876543210'),
      throwsA(
        isA<DriverAuthException>().having(
          (e) => e.message,
          'message',
          contains('wait a minute'),
        ),
      ),
    );
  });

  test(
    'disabled phone provider is reported without pretending to send an OTP',
    () async {
      identityStatus = 400;
      identityError = {'error_code': 'phone_provider_disabled'};
      await expectLater(
        auth.sendPhoneOtp('+919876543210'),
        throwsA(isA<DriverAuthException>()),
      );
      expect(auth.current, isNull);
    },
  );

  test(
    'otp_disabled produces setup guidance and never activates a driver',
    () async {
      identityStatus = 422;
      identityError = {'error_code': 'otp_disabled'};
      await expectLater(
        auth.sendPhoneOtp('+919876543210'),
        throwsA(
          isA<DriverAuthException>().having(
            (error) => error.message,
            'message',
            contains('SMS sign-in is not configured'),
          ),
        ),
      );
      expect(auth.current, isNull);
    },
  );

  test(
    'HTML server failures are handled without exposing response content',
    () async {
      identityStatus = 503;
      htmlResponse = true;
      await expectLater(
        auth.sendPhoneOtp('+919876543210'),
        throwsA(
          isA<DriverAuthException>().having(
            (e) => e.message,
            'message',
            contains('temporarily unavailable'),
          ),
        ),
      );
    },
  );

  test('invalid numbers and codes make no requests', () async {
    await expectLater(
      auth.sendPhoneOtp('98765'),
      throwsA(isA<DriverAuthException>()),
    );
    await expectLater(
      auth.verifyPhoneOtp('+919876543210', '1234'),
      throwsA(isA<DriverAuthException>()),
    );
    expect(calls, isEmpty);
  });

  test('normalizes Indian and international phone numbers', () {
    expect(normalizePhone('98765 43210'), '+919876543210');
    expect(normalizePhone('09876543210'), '+919876543210');
    expect(normalizePhone('+1 (202) 555-0123'), '+12025550123');
    expect(normalizePhone('0091 9876543210'), '+919876543210');
    expect(normalizePhone('1234567890'), isNull);
    expect(normalizePhone('++919876543210'), isNull);
    expect(normalizePhone('abc9876543210'), isNull);
    expect(isValidEmail('driver@example.com'), isTrue);
    expect(isValidEmail('driver @example.com'), isFalse);
  });
}
