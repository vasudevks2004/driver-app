import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

const bool allowDemo = bool.fromEnvironment('ALLOW_DEMO', defaultValue: false);

class DriverSession {
  const DriverSession({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
    required this.profile,
  });

  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final Map<String, dynamic> profile;

  bool get mustChangePassword => profile['mustChangePassword'] == true;

  static DriverSession fromResponse(dynamic result) {
    if (result is! Map) {
      throw const FormatException('Invalid driver session response.');
    }
    final access = result['token'];
    final refresh = result['refreshToken'];
    final rawProfile = result['profile'];
    if (access is! String || access.isEmpty ||
        refresh is! String || refresh.isEmpty ||
        rawProfile is! Map || rawProfile['role'] != 'driver') {
      throw const FormatException('A verified driver session is required.');
    }
    final seconds = (result['expiresIn'] as num?)?.toInt() ?? 3600;
    if (seconds <= 0) {
      throw const FormatException('The driver session has expired.');
    }
    return DriverSession(
      token: access,
      refreshToken: refresh,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
      profile: Map<String, dynamic>.from(rawProfile),
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'profile': profile,
  };

  static DriverSession fromJson(Map<String, dynamic> json) {
    final token = json['token'], refreshToken = json['refreshToken'],
      rawProfile = json['profile'];
    if (token is! String || token.isEmpty ||
        refreshToken is! String || refreshToken.isEmpty ||
        rawProfile is! Map || rawProfile['role'] != 'driver') {
      throw const FormatException('Saved driver session is invalid.');
    }
    return DriverSession(
      token: token,
      refreshToken: refreshToken,
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      profile: Map<String, dynamic>.from(rawProfile),
    );
  }
}

class DriverAuth {
  DriverAuth(this.baseUrl);
  final String baseUrl;
  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'hired.driver.session.v1';

  DriverSession? current;

  DriverApi get _api => DriverApi(baseUrl, current?.token ?? '');

  Future<void> _save(DriverSession session) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));
    current = session;
  }

  Future<void> _clear() async {
    current = null;
    await _storage.delete(key: _sessionKey);
    // Pre-login builds stored a non-renewable access token here.
    await _storage.delete(key: 'driver_token');
  }

  Future<DriverSession?> restore() async {
    final saved = await _storage.read(key: _sessionKey);
    if (saved == null) {
      await _storage.delete(key: 'driver_token');
      return null;
    }
    try {
      current = DriverSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(saved) as Map));
    } catch (_) {
      await _clear();
      return null;
    }
    // Never unlock the dashboard using unverified cached credentials.
    try {
      return await refresh();
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _clear();
        return null;
      }
      rethrow;
    }
  }

  Future<DriverSession> login(String email, String password) async {
    if (baseUrl.isEmpty) {
      throw StateError('Driver server is not configured for this build.');
    }
    final result = await DriverApi(baseUrl, '').request(
      '/auth/driver/login',
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    final session = DriverSession.fromResponse(result);
    await _save(session);
    return session;
  }

  Future<DriverSession> refresh() async {
    final saved = current;
    if (saved == null) throw StateError('Please sign in again.');
    try {
      final result = await DriverApi(baseUrl, '').request(
        '/auth/driver/refresh', method: 'POST',
        body: {'refreshToken': saved.refreshToken},
      );
      final next = DriverSession.fromResponse(result);
      await _save(next);
      return next;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _clear();
      }
      rethrow;
    }
  }

  Future<DriverSession> ensureFresh() async {
    final saved = current;
    if (saved == null) throw StateError('Please sign in again.');
    if (DateTime.now().toUtc().isAfter(
        saved.expiresAt.subtract(const Duration(seconds: 60)))) {
      return refresh();
    }
    return saved;
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    await ensureFresh();
    final key = method == 'GET' ? null : _idempotencyKey();
    try {
      return await _api.request(
        path, method: method, body: body,
        headers: key == null ? null : {'Idempotency-Key': key},
      );
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      // A GET is safe to repeat. Never silently replay a financial mutation.
      if (method != 'GET') {
        await refresh();
        rethrow;
      }
      await refresh();
      return _api.request(path, method: method, body: body);
    }
  }

  Future<void> upload(String path, String filePath) async {
    await ensureFresh();
    await _api.upload(path, filePath);
  }

  Future<DriverSession> changePassword(
      String currentPassword, String newPassword) async {
    await ensureFresh();
    final result = await _api.request(
      '/auth/driver/password', method: 'POST',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
    final next = DriverSession.fromResponse(result);
    await _save(next);
    return next;
  }

  /// Returns whether server-side token revocation was confirmed.
  /// Local session is always cleared.
  Future<bool> logout() async {
    var revoked = true;
    if (current != null) {
      try {
        await _api.request('/auth/driver/logout', method: 'POST', body: {});
      } catch (_) {
        revoked = false;
      }
    }
    await _clear();
    return revoked;
  }

  String _idempotencyKey() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value = bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return value.substring(0, 8) + '-' + value.substring(8, 12) + '-' +
        value.substring(12, 16) + '-' + value.substring(16, 20) + '-' +
        value.substring(20);
  }
}
