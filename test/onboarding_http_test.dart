import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/auth_config.dart';
import 'package:hired_driver/identity_auth.dart';
import 'package:hired_driver/onboarding.dart';

void main() {
  late HttpServer server;
  late DriverOnboarding service;
  final calls = <String>[];
  setUp(() async {
    calls.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    service = DriverOnboarding(DriverAuthConfig(supabaseUrl: 'http://127.0.0.1:${server.port}', publishableKey: 'public-test-key'));
  });
  tearDown(() async { service.dispose(); await server.close(force: true); });

  test('real HTTP sends applicant bearer and raw private images, then submits licence details', () async {
    server.listen((request) async {
      calls.add(request.uri.path);
      expect(request.headers.value('Authorization'), 'Bearer applicant-token');
      expect(request.headers.value('apikey'), 'public-test-key');
      final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      if (request.uri.path.endsWith('/documents/selfie')) {
        expect(request.headers.contentType?.mimeType, 'image/jpeg');
        expect(bytes.take(3), [255, 216, 255]);
      } else {
        final body = jsonDecode(utf8.decode(bytes)) as Map;
        if (request.uri.path.endsWith('/submit')) {
          expect(body['licence_number'], 'KL07 20201234567');
          expect(body['birth_date'], '1995-01-15');
          expect(body['consent'], isTrue);
        } else { expect(body['full_name'], 'Test Driver'); }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'id': 'application-test', 'status': request.uri.path.endsWith('/submit') ? 'submitted' : 'draft'}));
      await request.response.close();
    });
    await service.open('applicant-token', name: 'Test Driver', city: 'Kochi');
    await service.upload('applicant-token', 'selfie', Uint8List.fromList([255,216,255,224]));
    final result = await service.submit('applicant-token', licenceNumber: 'kl07 20201234567', birthDate: DateTime(1995,1,15), licenceExpiry: DateTime(2035,1,15), vehicleClass: 'LMV');
    expect(result.submitted, isTrue);
    expect(calls.length, 3);
  });

  test('unconfigured DigiLocker returns the service message without granting verification', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 503;
      request.response.write(jsonEncode({'message': 'DigiLocker is being set up. You can upload your licence photos instead.'}));
      await request.response.close();
    });
    await expectLater(service.startDigiLocker('applicant'), throwsA(isA<DriverAuthException>().having((e) => e.message, 'message', contains('upload your licence photos'))));
  });

  test('a foreign OAuth URL returned over real HTTP is not opened', () async {
    server.listen((request) async {
      await request.drain<void>();
      request.response.write(jsonEncode({'authorization_url': 'https://digilocker.gov.in.evil.example/steal'}));
      await request.response.close();
    });
    await expectLater(service.startDigiLocker('applicant'), throwsA(isA<DriverAuthException>()));
  });

  test('invalid image bytes and invalid licence numbers are rejected', () async {
    await expectLater(service.upload('applicant', 'selfie', Uint8List.fromList([1,2,3])), throwsA(isA<DriverAuthException>()));
    expect(validLicenceNumber('KL-07-20201234567'), isTrue);
    expect(validLicenceNumber('abc'), isFalse);
  });
}
