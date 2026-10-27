// Opt-in real-service acceptance for the exact driver classes shipped in the APK.
// Run explicitly with HIRED_HOSTED_CONFIG=/private/admin.json flutter test
// tool/hosted_staging_contract_test.dart --reporter expanded.
// OS secure storage, camera and rendered device UI are NOT exercised here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:hired_driver/api.dart';
import 'package:hired_driver/auth.dart';
import 'package:hired_driver/auth_config.dart';
import 'package:hired_driver/core/assignment_feed.dart';
import 'package:hired_driver/core/pending_operations.dart';
import 'package:hired_driver/core/session_store.dart';
import 'package:hired_driver/features/duties/duty.dart';
import 'package:hired_driver/features/workspace/repository.dart';
import 'package:hired_driver/identity_auth.dart';

const _origin = 'https://hired-unit7-staging.pages.dev';
const _project = 'https://wudshomvlnzblpsmntmt.supabase.co';

class _MemorySessions implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

class _Portal {
  final cookies = <String, Cookie>{};
  String csrf = '';
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? data,
    String? requestKey,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.openUrl(
        data == null ? 'GET' : 'POST',
        Uri.parse('$_origin$path'),
      );
      request.followRedirects = false;
      request.headers.set('Origin', _origin);
      request.headers.set('Accept', 'application/json');
      request.cookies.addAll(cookies.values);
      if (csrf.isNotEmpty) request.headers.set('X-CSRF-Token', csrf);
      if (requestKey != null) {
        request.headers.set('Idempotency-Key', requestKey);
      }
      if (data != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(data));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 50),
      );
      for (final cookie in response.cookies) {
        cookies[cookie.name] = cookie;
      }
      final raw = await utf8.decoder.bind(response).join();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw StateError('$path returned HTTP ${response.statusCode}');
      }
      final body = Map<String, dynamic>.from(json['data'] as Map? ?? json);
      if (body['csrfToken'] is String) csrf = body['csrfToken'] as String;
      return body;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> action(
    String type,
    Map<String, dynamic> payload,
  ) async => Map<String, dynamic>.from(
    (await request(
          '/admin/api/v1/admin/actions',
          data: {'type': type, 'payload': payload},
          requestKey: newRequestKey(),
        ))['state']
        as Map,
  );
}

Future<bool> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return condition();
}

void main() {
  final configPath = Platform.environment['HIRED_HOSTED_CONFIG'];
  final outputPath = Platform.environment['HIRED_HOSTED_REPORT'];
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'shipped Dart client completes a real isolated hosted duty',
    () async {
      final cfg = jsonDecode(await File(configPath!).readAsString()) as Map;
      expect(cfg['gatewayUrl'], _origin);
      final public =
          jsonDecode(await File('config/staging.json').readAsString()) as Map;
      expect(public['API_URL'], '$_origin/admin/api/v1');
      expect(public['SUPABASE_URL'], _project);
      // Flutter's test runner otherwise installs a network stand-in. This
      // explicit opt-in uses real HTTPS/WebSocket services, never a mock server.
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      final admin = _Portal(), partner = _Portal();
      final auths = <DriverAuth>[];
      final feeds = <SupabaseAssignmentFeed>[];
      final report = <String, dynamic>{
        'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'gateway': _origin,
        'project': 'wudshomvlnzblpsmntmt',
        'clientSource': 'a251abbcfa004b7ad3e2a2e9a1b5abdbfa6b2b86',
        'platformStandIns': [
          'OS secure session storage',
          'pending-key storage',
        ],
        'notExercised': ['physical device', 'camera', 'rendered app/portal UI'],
        'checks': <String>[],
        'syntheticAccountIds': <String>[],
      };
      final fixture = await Directory.systemTemp.createTemp('hired-contract-');
      void check(bool condition, String name) {
        if (!condition) throw TestFailure(name);
        (report['checks'] as List).add(name);
        // No credentials, bearer tokens or partner code enter the test log.
        // ignore: avoid_print
        print('HOSTED PASS: $name');
      }

      final random = Random.secure();
      String secret() =>
          'Test!${List.generate(28, (_) => random.nextInt(16).toRadixString(16)).join()}';
      final id = List.generate(
        6,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      final identityConfig = DriverAuthConfig(
        supabaseUrl: _project,
        publishableKey: public['SUPABASE_PUBLISHABLE_KEY'] as String,
      );
      Future<Map<String, dynamic>> provision(
        String label,
        String role,
        String company,
      ) async {
        final result = await admin.request(
          '/admin/api/v1/admin/accounts',
          data: {
            'role': role,
            'email': 'dart-$label-$id@hired.example',
            'name': 'Synthetic Dart $label',
            'phone': '2025550140',
            if (role == 'partner') 'companyId': company,
          },
          requestKey: newRequestKey(),
        );
        return Map<String, dynamic>.from(result['credentials'] as Map);
      }

      try {
        await admin.request(
          '/admin/api/v1/auth/login',
          data: {
            'username': cfg['adminUsername'],
            'password': cfg['adminPassword'],
          },
        );
        var state = await admin.action('SAVE_COMPANY', {
          'name': 'Synthetic Dart client $id',
          'contact': 'Synthetic Contact',
          'email': 'dart-company-$id@hired.example',
          'phone': '2025550140',
          'address': 'Synthetic staging address',
          'driverPercent': '25',
          'notes': 'SYNTHETIC TEST RATE ONLY, not a production business policy',
        });
        final company =
            (state['companies'] as List).cast<Map>().firstWhere(
                  (c) => c['name'] == 'Synthetic Dart client $id',
                )['id']
                as String;
        report['companyId'] = company;
        final partnerCredentials = await provision(
          'partner',
          'partner',
          company,
        );
        await partner.request(
          '/api/login',
          data: {
            'email': partnerCredentials['email'],
            'password': partnerCredentials['temporaryPassword'],
          },
        );
        final readyPartner = await partner.request(
          '/api/password',
          data: {
            'currentPassword': partnerCredentials['temporaryPassword'],
            'newPassword': secret(),
          },
        );
        check(
          (readyPartner['company'] as Map)['id'] == company,
          'Real partner first-password setup completes for the isolated company',
        );
        for (final label in ['a', 'b']) {
          final credentials = await provision(
            'driver-$label',
            'driver',
            company,
          );
          final auth = DriverAuth(
            '$_origin/admin/api/v1',
            identity: SupabaseIdentityAuth(identityConfig),
            sessionStore: _MemorySessions(),
            pending: PendingOperations(storage: MemoryOperationStorage()),
          );
          auths.add(auth);
          final initial = await auth.login(
            credentials['email'] as String,
            credentials['temporaryPassword'] as String,
          );
          check(
            initial.mustChangePassword,
            'Dart driver $label requires its initial password change',
          );
          final session = await auth.changePassword(
            credentials['temporaryPassword'] as String,
            secret(),
          );
          (report['syntheticAccountIds'] as List).add(session.profile['id']);
          for (final kind in ['license', 'aadhaar', 'pan', 'pcc']) {
            final file = File('${fixture.path}/synthetic-$kind.pdf');
            await file.writeAsString(
              '%PDF-1.7\nSYNTHETIC TEST, NOT AN IDENTITY DOCUMENT\n%%EOF',
            );
            await auth.upload(
              '/drivers/me/documents/$kind',
              file.path,
              expiresOn: '2099-01-01',
            );
          }
          await admin.action('ACTIVATE_DRIVER', {'id': session.profile['id']});
          check(
            !auth.current!.mustChangePassword,
            'Dart driver $label uploads all four document types through the real private service',
          );
        }
        final a = auths[0], b = auths[1];
        final repoA = DriverRepository(a), repoB = DriverRepository(b);
        final pickupDate = DateTime.now()
            .toUtc()
            .add(const Duration(days: 12))
            .toIso8601String()
            .substring(0, 10);
        final order = await partner.request(
          '/api/orders',
          data: {
            'requestKey': newRequestKey(),
            'data': {
              'service': 'Business driver',
              'pickup': 'Synthetic Dart depot',
              'drop': 'Synthetic Dart destination',
              'date': pickupDate,
              'time': '10:00',
              'contact': 'Synthetic Contact',
              'phone': '2025550140',
              'notes': 'Synthetic test; business supplies its vehicle',
              'pickupLat': 10.05,
              'pickupLng': 76.31,
              'dropLat': 10.1,
              'dropLng': 76.35,
            },
          },
        );
        state = await admin.action('ACCEPT_ORDER', {
          'id': order['id'],
          'amount': '123.45',
        });
        final trip =
            (state['trips'] as List).cast<Map>().firstWhere(
                  (t) => t['orderId'] == order['id'],
                )['id']
                as String;
        report['tripId'] = trip;
        var changesA = 0, changesB = 0;
        final readyA = Completer<void>(), readyB = Completer<void>();
        for (var i = 0; i < 2; i++) {
          final feed = SupabaseAssignmentFeed(identityConfig);
          feeds.add(feed);
          final ready = i == 0 ? readyA : readyB;
          await feed.connect(
            auths[i].current!.token,
            () {
              if (i == 0) {
                changesA++;
              } else {
                changesB++;
              }
            },
            (connected) {
              if (connected && !ready.isCompleted) ready.complete();
            },
          );
        }
        await Future.wait([
          readyA.future,
          readyB.future,
        ]).timeout(const Duration(seconds: 30));
        var beforeA = changesA, beforeB = changesB;
        await admin.action('ASSIGN_DRIVER', {
          'id': trip,
          'driverId': a.current!.profile['id'],
          'reason': 'Synthetic Dart initial assignment',
        });
        check(
          await _until(() => changesA > beforeA),
          'The shipped Dart assignment feed receives the real initial assignment',
        );
        check(
          (await repoA.duties()).items.any((d) => d.id == trip),
          'The shipped typed duty list parses its assigned trip',
        );
        beforeA = changesA;
        beforeB = changesB;
        await admin.action('ASSIGN_DRIVER', {
          'id': trip,
          'driverId': b.current!.profile['id'],
          'reason': 'Synthetic Dart reassignment',
        });
        check(
          await _until(() => changesA > beforeA && changesB > beforeB),
          'The shipped Dart feeds receive both sides of reassignment',
        );
        await expectLater(
          repoA.duty(trip),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 403),
          ),
        );
        check(
          (await repoB.duty(trip)).status == DutyStatus.assigned,
          'The old driver is denied while the new Dart duty model is Assigned',
        );
        await expectLater(
          repoB.start(trip),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 400),
          ),
        );
        final image = File('${fixture.path}/synthetic-selfie.png');
        await image.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8b8AAAAASUVORK5CYII=',
          ),
        );
        await b.upload('/trips/$trip/selfie', image.path);
        check(
          (await repoB.duty(trip)).selfie,
          'The actual Dart raw upload contract stores and reads its synthetic selfie',
        );
        await repoB.start(trip);
        check(
          (await repoB.duty(trip)).status == DutyStatus.ongoing,
          'The actual Dart start call reads back Ongoing',
        );
        await repoB.expense(trip, 'Synthetic parking', '12.25');
        final expenseDuty = await repoB.duty(trip);
        check(
          expenseDuty.expensesSubmitted &&
              expenseDuty.expenses.single.amount == 12.25,
          'The typed duty model reads the recorded expense and submission flag',
        );
        await admin.action('ISSUE_CLOSE_CODE', {
          'id': trip,
          'reason': 'Synthetic Dart completion',
        });
        final code =
            (await partner.request('/api/trips/$trip/code'))['code'] as String;
        await expectLater(
          repoB.close(trip, code == '000000' ? '111111' : '000000'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 400),
          ),
        );
        check(
          (await repoB.duty(trip)).status == DutyStatus.ongoing,
          'The shipped Dart client rejects a wrong code without closing',
        );
        await repoB.close(trip, code);
        check(
          (await repoB.duty(trip)).complete,
          'The shipped Dart client closes the duty with the correct partner code',
        );
        final wallet = await repoB.wallet();
        final credits = wallet.transactions
            .where((t) => t.tripId == trip)
            .toList();
        check(
          wallet.balance == 30.86 &&
              credits.length == 1 &&
              credits.single.amount == 30.86,
          'The shipped Dart wallet model reads one 25% credit, separate from expenses',
        );
        check(
          (await repoB.duties(completed: true)).items.any((d) => d.id == trip),
          'The shipped Dart completed-history model includes the closed duty',
        );
        final portal = await partner.request('/api/session');
        check(
          (portal['orders'] as List).cast<Map>().any(
            (o) => o['tripId'] == trip && o['status'] == 'Closed',
          ),
          'The business portal API reflects the Dart-completed trip report',
        );
        final oldToken = b.current!.token;
        check(
          await b.logout(),
          'The shipped Dart logout confirms deployed server revocation',
        );
        await expectLater(
          DriverApi('$_origin/admin/api/v1', oldToken).request('/drivers/me'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.statusCode,
              'revoked bearer denied',
              isIn([401, 403]),
            ),
          ),
        );
        check(
          b.current == null,
          'The Dart session clears and its revoked bearer is denied',
        );
        report['result'] = 'PASS_WITH_LIMITS';
      } catch (error) {
        report['result'] = 'FAIL';
        report['failureType'] = error.runtimeType.toString();
        rethrow;
      } finally {
        for (final feed in feeds) {
          await feed.stop();
        }
        for (final auth in auths) {
          if (auth.current != null) await auth.logout();
          auth.dispose();
        }
        try {
          await partner.request('/api/logout', data: {});
        } catch (_) {}
        try {
          await admin.request('/admin/api/v1/auth/logout', data: {});
        } catch (_) {}
        await fixture.delete(recursive: true);
        HttpOverrides.global = previousHttp;
        report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
        if (outputPath != null)
          await File(
            outputPath,
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      }
    },
    skip: configPath == null
        ? 'Opt-in: requires private test Admin credentials and isolated staging'
        : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
