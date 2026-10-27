import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_config.dart';
import 'identity_auth.dart';

const maxDriverImageBytes = 5 * 1024 * 1024;

String? driverImageMime(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  const png = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length >= png.length &&
      List.generate(png.length, (i) => bytes[i] == png[i]).every((x) => x)) {
    return 'image/png';
  }
  return null;
}

bool validLicenceNumber(String text) =>
    RegExp(
      r'^[A-Z0-9][A-Z0-9 /-]{5,29}$',
    ).hasMatch(text.trim().toUpperCase()) &&
    RegExp(r'[0-9]').hasMatch(text);

String normalizeAadhaarNumber(String value) =>
    value.replaceAll(RegExp(r'\s'), '');
// Format validation only. Uploading a document does not verify it with UIDAI.
bool validAadhaarNumber(String value) =>
    RegExp(r'^[2-9][0-9]{11}$').hasMatch(normalizeAadhaarNumber(value));
String maskedAadhaar(String lastFour) => '•••• •••• $lastFour';

class DriverApplication {
  const DriverApplication(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get status => data['status'] as String? ?? 'draft';
  bool get submitted => status == 'submitted';
  bool get editable => ['draft', 'corrections_requested'].contains(status);
  bool get panUploaded => data['pan_uploaded'] == true;
  bool get pccUploaded => data['pcc_uploaded'] == true;
  String? get reviewReason => data['review_reason'] as String?;
  bool get selfieUploaded => data['selfie_uploaded'] == true;
  bool get frontUploaded => data['licence_front_uploaded'] == true;
  bool get backUploaded => data['licence_back_uploaded'] == true;
  bool get aadhaarUploaded => data['aadhaar_uploaded'] == true;
  String? get aadhaarLastFour => data['aadhaar_last4'] as String?;
  String get digiLockerStatus =>
      data['digilocker_status'] as String? ?? 'not_connected';
  bool get hasDigiLockerDocument => digiLockerStatus == 'document_received';
}

/// Applicant-only service. Its bearer is never saved as a driver session.
class DriverOnboarding {
  DriverOnboarding(
    this.config, {
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final DriverAuthConfig config;
  bool get isPreview => false;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Uri _url(String path) {
    final base = Uri.tryParse(config.supabaseUrl);
    final local = base?.host == 'localhost' || base?.host == '127.0.0.1';
    if (!config.isConfigured ||
        base == null ||
        !base.hasAuthority ||
        (base.scheme != 'https' && !(kDebugMode && local))) {
      throw const DriverAuthException(
        'Driver registration is being set up. Please try again later.',
      );
    }
    return Uri.parse(
      '${config.supabaseUrl.replaceFirst(RegExp(r'/$'), '')}/functions/v1/driver-onboarding$path',
    );
  }

  Future<Map<String, dynamic>> _send(
    String path,
    String token, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Uint8List? bytes,
    String? mime,
  }) async {
    final request = http.Request(method, _url(path));
    request.headers.addAll({
      'apikey': config.publishableKey,
      'Authorization': 'Bearer $token',
      'Content-Type': mime ?? 'application/json',
    });
    if (bytes != null) request.bodyBytes = bytes;
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
    } on TimeoutException {
      throw const DriverAuthException(
        'The upload took too long. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const DriverAuthException(
        'The result could not be confirmed. Reopen your application to check its saved status before retrying.',
      );
    }
    if (response.statusCode == 401) {
      throw const DriverAuthException(
        'Your verification session expired. Sign in again to continue your application.',
      );
    }
    if (response.statusCode == 404) {
      throw const DriverAuthException(
        'This service is being set up. Please try again later.',
      );
    }
    if (response.statusCode == 429) {
      throw const DriverAuthException(
        'Too many requests. Please wait a minute and try again.',
      );
    }
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const DriverAuthException(
        'HireD returned an unexpected response. Please retry.',
      );
    }
    if (response.statusCode >= 400) {
      // Only show the service's public message, never upstream response bodies.
      throw DriverAuthException(
        payload['message'] is String
            ? payload['message'] as String
            : 'We could not save your application. Please retry.',
      );
    }
    return payload;
  }

  Future<DriverApplication> open(
    String token, {
    required String name,
    required String city,
  }) async => DriverApplication(
    await _send(
      '/application',
      token,
      method: 'POST',
      body: {'full_name': name.trim(), 'city': city.trim()},
    ),
  );

  Future<DriverApplication> status(String token) async =>
      DriverApplication(await _send('/application', token));

  Future<DriverApplication> upload(
    String token,
    String kind,
    Uint8List bytes,
  ) async {
    if (![
      'selfie',
      'licence_front',
      'licence_back',
      'aadhaar',
      'pan',
      'pcc',
    ].contains(kind)) {
      throw const DriverAuthException('Choose a supported document.');
    }
    final mime = driverImageMime(bytes);
    if (bytes.isEmpty || bytes.length > maxDriverImageBytes || mime == null) {
      throw const DriverAuthException(
        'Choose a JPG or PNG image smaller than 5 MB.',
      );
    }
    return DriverApplication(
      await _send(
        '/documents/$kind',
        token,
        method: 'POST',
        bytes: bytes,
        mime: mime,
      ),
    );
  }

  Future<DriverApplication> saveDraft(
    String token,
    Map<String, dynamic> details,
  ) async => DriverApplication(
    await _send('/draft', token, method: 'POST', body: details),
  );

  Future<void> deleteApplication(String token) async {
    await _send('/delete', token, method: 'POST', body: {});
  }

  Future<Uint8List?> avatar(String token) async {
    final response = await _client
        .get(
          _url('/avatar'),
          headers: {
            'apikey': config.publishableKey,
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(timeout);
    if (response.statusCode != 200 ||
        response.bodyBytes.length > maxDriverImageBytes ||
        driverImageMime(response.bodyBytes) == null) {
      return null;
    }
    return response.bodyBytes;
  }

  Future<Uri> startDigiLocker(String token) async {
    final payload = await _send(
      '/digilocker/start',
      token,
      method: 'POST',
      body: {'consent': true},
    );
    final uri = Uri.tryParse(payload['authorization_url']?.toString() ?? '');
    // Do not open arbitrary URLs or custom schemes returned by a bad gateway.
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !(uri.host == 'digilocker.gov.in' ||
            uri.host.endsWith('.digilocker.gov.in') ||
            uri.host == 'meripehchaan.gov.in' ||
            uri.host.endsWith('.meripehchaan.gov.in'))) {
      throw const DriverAuthException(
        'The DigiLocker connection could not be started safely.',
      );
    }
    return uri;
  }

  Future<DriverApplication> submit(
    String token, {
    required String licenceNumber,
    required String aadhaarNumber,
    required DateTime birthDate,
    required DateTime licenceExpiry,
    required String vehicleClass,
  }) async => DriverApplication(
    await _send(
      '/submit',
      token,
      method: 'POST',
      body: {
        'licence_number': licenceNumber.trim().toUpperCase(),
        'aadhaar_number': normalizeAadhaarNumber(aadhaarNumber),
        'birth_date': _date(birthDate),
        'licence_expiry': _date(licenceExpiry),
        'vehicle_class': vehicleClass,
        'consent': true,
      },
    ),
  );

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
