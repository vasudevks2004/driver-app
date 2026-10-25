import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:hired_driver/api.dart';
import 'package:hired_driver/auth.dart';
import 'package:hired_driver/core/pending_operations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Process server;
  late String base;
  late Directory temp;
  Future<Map<String, dynamic>> control(
    String route, [
    Map<String, dynamic>? body,
  ]) async {
    final response = body == null
        ? await http.get(Uri.parse('$base$route'))
        : await http.post(
            Uri.parse('$base$route'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          );
    expect(response.statusCode, 200, reason: 'Contract fixture control failed');
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  DriverAuth authFor(
    Map<String, dynamic> data,
    MemoryOperationStorage storage,
  ) {
    final auth = DriverAuth(
      '$base/admin/api/v1',
      pending: PendingOperations(storage: storage),
    );
    auth.current = DriverSession(
      token: data['token'] as String,
      refreshToken: data['refreshToken'] as String,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      profile: Map<String, dynamic>.from(data['profile'] as Map),
    );
    return auth;
  }

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    server = await Process.start('node', [
      'test/support/driver-contract-fixture.mjs',
    ]);
    // Fixture stdout contains only the loopback address, never codes or identity data.
    final line = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 40));
    base = (jsonDecode(line) as Map)['base'] as String;
    temp = await Directory.systemTemp.createTemp('hired-contract-');
  });
  tearDownAll(() async {
    server.kill();
    await server.exitCode;
    await temp.delete(recursive: true);
  });
  test(
    'client raw upload encoding and restart recovery use real HTTP',
    () async {
      final data = await control('/__case', {}),
          storage = MemoryOperationStorage();
      var auth = authFor(data, storage);
      final trip = data['tripId'] as String;
      final photo = File('${temp.path}/driver photo.jpg');
      await photo.writeAsBytes([255, 216, 255, 1, 2, 3]);
      await auth.request('/trips/$trip/start', method: 'POST', body: {});
      await control('/__fault', {'suffix': '/expenses'});
      await expectLater(
        auth.request(
          '/trips/$trip/expenses',
          method: 'POST',
          body: {'amount': '10.25', 'description': 'Parking'},
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.uncertain,
            'uncertain result',
            true,
          ),
        ),
      );
      auth.dispose();
      auth = authFor(
        data,
        storage,
      ); // Same durable operation store after restart.
      await auth.request(
        '/trips/$trip/expenses',
        method: 'POST',
        body: {'amount': '10.25', 'description': 'Parking'},
      );
      expect((await control('/__state?tripId=$trip'))['expenses'], 1);
      await expectLater(
        auth.request(
          '/trips/$trip/close',
          method: 'POST',
          body: {'otp': '123456'},
        ),
        throwsA(isA<ApiException>()),
      );
      await control('/__fault', {'suffix': '/selfie'});
      await expectLater(
        auth.upload('/trips/$trip/selfie', photo.path),
        throwsA(
          isA<ApiException>().having(
            (e) => e.uncertain,
            'uncertain upload',
            true,
          ),
        ),
      );
      final before = await control('/__state?tripId=$trip');
      auth.dispose();
      auth = authFor(data, storage);
      await auth.upload('/trips/$trip/selfie', photo.path);
      final after = await control('/__state?tripId=$trip');
      expect(after['objects'], before['objects']);
      expect(after['files'], before['files']);
      final duty = await auth.request('/drivers/me/trips/$trip') as Map;
      expect(duty['expensesSubmitted'], true);
      expect(duty['selfie'], true);
      final code = (await control('/__code', {'tripId': trip}))['code'];
      await expectLater(
        auth.request(
          '/trips/$trip/close',
          method: 'POST',
          body: {'otp': '1234'},
        ),
        throwsA(isA<ApiException>()),
      );
      await control('/__fault', {'suffix': '/close'});
      await expectLater(
        auth.request('/trips/$trip/close', method: 'POST', body: {'otp': code}),
        throwsA(isA<ApiException>()),
      );
      await auth.request(
        '/trips/$trip/close',
        method: 'POST',
        body: {'otp': code},
      );
      expect((await control('/__state?tripId=$trip'))['journals'], 1);
      final wallet =
          await auth.request('/drivers/me/wallet?v=2&limit=25') as Map;
      expect(num.parse('${wallet['balance']}'), 70.09);
      final requests = (after['requests'] as List)
          .cast<Map>()
          .where((r) => r['path'].toString().endsWith('/selfie'))
          .toList();
      expect(requests.length, 2);
      expect(requests[0]['key'], requests[1]['key']);
      expect(requests.first['mime'], 'image/jpeg');
      expect(requests.first['filename'], 'driver%20photo.jpg');
      auth.dispose();
    },
    timeout: const Timeout(Duration(seconds: 80)),
  );
  test(
    'no-expenses survives refresh, other-driver access and expired sessions are denied',
    () async {
      final one = await control('/__case', {}),
          two = await control('/__case', {});
      final auth = authFor(one, MemoryOperationStorage()), trip = one['tripId'];
      await auth.request('/trips/$trip/start', method: 'POST', body: {});
      await auth.request(
        '/trips/$trip/expenses',
        method: 'POST',
        body: {'amount': '0', 'description': 'No expenses'},
      );
      final duty = await auth.request('/drivers/me/trips/$trip') as Map;
      expect(duty['noExpenses'], true);
      expect(duty['expensesSubmitted'], true);
      await expectLater(
        DriverApi(
          '$base/admin/api/v1',
          two['token'] as String,
        ).request('/drivers/me/trips/$trip'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'scope', 403)),
      );
      await expectLater(
        DriverApi('$base/admin/api/v1', 'expired').request('/drivers/me'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.statusCode,
            'expired session',
            401,
          ),
        ),
      );
      final pdf = File('${temp.path}/selfie.pdf');
      await pdf.writeAsString('%PDF-1.7');
      await expectLater(
        auth.upload('/trips/$trip/selfie', pdf.path),
        throwsA(isA<ApiException>()),
      );
      final large = File('${temp.path}/too-large.jpg');
      await large.writeAsBytes(List.filled(driverUploadLimit + 1, 0));
      await expectLater(
        auth.upload('/drivers/me/documents/license', large.path),
        throwsA(isA<ApiException>()),
      );
      auth.dispose();
    },
  );
}
