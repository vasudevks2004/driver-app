import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'core/pending_operations.dart';

import 'core/session_store.dart';

import 'api.dart';
import 'auth_config.dart';
import 'identity_auth.dart';

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
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        rawProfile is! Map ||
        rawProfile['role'] != 'driver') {
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
    final token = json['token'],
        refreshToken = json['refreshToken'],
        rawProfile = json['profile'];
    if (token is! String ||
        token.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        rawProfile is! Map ||
        rawProfile['role'] != 'driver') {
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
  DriverAuth(
    this.baseUrl, {
    SupabaseIdentityAuth? identity,
    PendingOperations? pending,
    SessionStore? sessionStore,
  }) : _sessions = sessionStore ?? const SecureSessionStore(),
       pending = pending ?? PendingOperations(),
       identity =
           identity ??
           SupabaseIdentityAuth(const DriverAuthConfig.fromEnvironment());
  final String baseUrl;
  final SupabaseIdentityAuth identity;
  final PendingOperations pending;
  Future<DriverSession>? _refreshing;
  int _generation = 0;
  final SessionStore _sessions;
  Future<void> _sessionTail = Future.value();
  Future<T> _sessionAction<T>(Future<T> Function() action) {
    final future = _sessionTail.then((_) => action());
    _sessionTail = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return future;
  }

  DriverSession? current;

  void dispose() => identity.dispose();

  void _requireServer() {
    if (baseUrl.isEmpty) {
      throw const DriverAuthException(
        'Sign-in is being set up. Please contact HireD support.',
      );
    }
  }

  Future<DriverAuthMethods> methods() => identity.methods();

  Future<void> sendPhoneOtp(
    String phone, {
    bool register = false,
    String? fullName,
    String? city,
  }) {
    _requireServer();
    return identity.sendPhoneOtp(
      phone,
      register: register,
      fullName: fullName,
      city: city,
    );
  }

  /// A verified applicant may submit documents, but has no driver permissions.
  Future<IdentitySession> verifyRegistrationOtp(String phone, String code) {
    _requireServer();
    return identity.verifyPhoneOtp(phone, code);
  }

  Future<DriverSession> verifyPhoneOtp(String phone, String code) async {
    _requireServer();
    final generation = _generation;
    return _acceptIdentity(
      await identity.verifyPhoneOtp(phone, code),
      expectedGeneration: generation,
    );
  }

  Future<DriverSession?> loginWithGoogle() async {
    _requireServer();
    final generation = _generation;
    final result = await identity.signInWithGoogle();
    return result == null
        ? null
        : _acceptIdentity(result, expectedGeneration: generation);
  }

  Future<DriverSession> _acceptIdentity(
    IdentitySession identitySession, {
    required int expectedGeneration,
  }) async {
    try {
      // Only the trusted driver service can establish a driver's membership.
      final profile = await DriverApi(
        baseUrl,
        identitySession.accessToken,
      ).request('/drivers/me');
      final session = DriverSession.fromResponse({
        'token': identitySession.accessToken,
        'refreshToken': identitySession.refreshToken,
        'expiresIn': identitySession.expiresIn,
        'profile': profile,
      });
      await _save(session, expectedGeneration: expectedGeneration);
      return session;
    } catch (error) {
      // Never retain an identity-only session as a driver session.
      try {
        await identity.signOut(identitySession.accessToken);
      } catch (_) {}
      if (error is ApiException &&
          error.statusCode == 403 &&
          error.isApplicationError) {
        throw const DriverActivationRequired();
      }
      rethrow;
    }
  }

  DriverApi get _api => DriverApi(baseUrl, current?.token ?? '');

  Future<void> _save(
    DriverSession session, {
    int? expectedGeneration,
    DriverSession? prior,
  }) {
    final generation = expectedGeneration ?? _generation;
    return _sessionAction(() async {
      if (generation != _generation || prior != null && current != prior)
        throw const DriverAuthException('This session has ended.');
      await _sessions.write(jsonEncode(session.toJson()));
      // A sign-out may happen while secure storage is writing. Its queued clear
      // runs after this write; a late refresh must never restore current access.
      if (generation != _generation || prior != null && current != prior)
        throw const DriverAuthException('This session has ended.');
      current = session;
    });
  }

  Future<void> _clear() async {
    _generation++;
    current = null;
    await _sessionAction(_sessions.clear);
  }

  Future<DriverSession?> restore() async {
    final generation = _generation;
    final saved = await _sessionAction(_sessions.read);
    if (generation != _generation) return null;
    if (saved == null) {
      return null;
    }
    try {
      current = DriverSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(saved) as Map),
      );
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
    final generation = _generation;
    final result = await DriverApi(baseUrl, '').request(
      '/auth/driver/login',
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    final session = DriverSession.fromResponse(result);
    await _save(session, expectedGeneration: generation);
    return session;
  }

  Future<DriverSession> refresh() {
    if (_refreshing != null) return _refreshing!;
    final future = _refreshOnce();
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<DriverSession> _refreshOnce() async {
    final saved = current;
    final generation = _generation;
    if (saved == null) throw const DriverAuthException('Please sign in again.');
    try {
      final result = await DriverApi(baseUrl, '').request(
        '/auth/driver/refresh',
        method: 'POST',
        body: {'refreshToken': saved.refreshToken},
      );
      final next = DriverSession.fromResponse(result);
      if (generation != _generation || current != saved)
        throw const DriverAuthException(
          'This session has ended. Please sign in again.',
        );
      await _save(next, expectedGeneration: generation, prior: saved);
      return next;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) await _clear();
      rethrow;
    }
  }

  Future<DriverSession> ensureFresh() async {
    final saved = current;
    if (saved == null) throw StateError('Please sign in again.');
    if (DateTime.now().toUtc().isAfter(
      saved.expiresAt.subtract(const Duration(seconds: 60)),
    )) {
      return refresh();
    }
    return saved;
  }

  String get _subject {
    final id = current?.profile['id'];
    if (id is! String || id.isEmpty)
      throw const DriverAuthException(
        'Your driver profile must be verified again.',
      );
    return id;
  }

  Future<String> _beginOperation(
    String method,
    String path,
    String fingerprint,
  ) async {
    final subject = _subject, group = operationFingerprint(method, path, null);
    final unresolved = await pending.unresolved(
      baseUrl,
      subject,
      group: group,
      except: fingerprint,
    );
    var previousCommitted = false;
    for (final entry in unresolved.entries) {
      final receipt = await request('/drivers/me/operations/${entry.value}');
      if (_subject != subject)
        throw const DriverAuthException('The driver session changed.');
      if (receipt is! Map)
        throw const ApiException(
          'The earlier action could not be confirmed.',
          503,
          uncertain: true,
        );
      previousCommitted = previousCommitted || receipt['committed'] == true;
      if (receipt['committed'] != true && receipt['cancelled'] != true) {
        Future<dynamic> cancel() => _api.request(
          '/drivers/me/operations/${entry.value}/cancel',
          method: 'POST',
          body: {},
          headers: {'Idempotency-Key': entry.value},
        );
        dynamic cancelled;
        try {
          cancelled = await cancel();
        } on ApiException catch (error) {
          if (error.statusCode != 401) rethrow;
          await refresh();
          if (_subject != subject)
            throw const DriverAuthException('The driver session changed.');
          cancelled = await cancel();
        }
        if (cancelled is! Map ||
            cancelled['cancelled'] != true && cancelled['committed'] != true)
          throw const ApiException(
            'The earlier action could not be reconciled.',
            503,
            uncertain: true,
          );
        previousCommitted =
            previousCommitted || (cancelled as Map)['committed'] == true;
      }
      await pending.acknowledge(baseUrl, subject, entry.key);
    }
    if (unresolved.isNotEmpty) {
      throw ReconciledOperation(previousCommitted: previousCommitted);
    }
    return pending.begin(baseUrl, subject, fingerprint, group: group);
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    await ensureFresh();
    final subject = _subject;
    final fingerprint = operationFingerprint(method, path, body);
    final key = method == 'GET'
        ? null
        : await _beginOperation(method, path, fingerprint);
    Future<dynamic> send() => _api.request(
      path,
      method: method,
      body: body,
      headers: key == null ? null : {'Idempotency-Key': key},
    );
    try {
      dynamic result;
      try {
        result = await send();
      } on ApiException catch (error) {
        if (error.statusCode != 401) rethrow;
        await refresh();
        if (_subject != subject)
          throw const DriverAuthException(
            'The driver session changed. Please refresh.',
          );
        result = await send();
      }
      if (key != null) await pending.acknowledge(baseUrl, subject, fingerprint);
      return result;
    } on ApiException catch (error) {
      if (key != null && !error.uncertain)
        await pending.acknowledge(baseUrl, subject, fingerprint);
      rethrow;
    }
  }

  Future<void> upload(String path, String filePath, {String? expiresOn}) async {
    await ensureFresh();
    final subject = _subject;
    final file = File(filePath);
    if (await file.length() > driverUploadLimit)
      throw const ApiException('Choose a file up to 5 MB.', 400);
    final digest = sha256.convert(await file.readAsBytes()).toString();
    final fingerprint = operationFingerprint('UPLOAD', path, {
      'sha256': digest,
      'filename': filePath.replaceAll('\\', '/').split('/').last,
      'expiresOn': expiresOn ?? '',
    });
    final key = await _beginOperation('UPLOAD', path, fingerprint);
    Future<void> send() =>
        _api.upload(path, filePath, requestKey: key, expiresOn: expiresOn);
    try {
      try {
        await send();
      } on ApiException catch (error) {
        if (error.statusCode != 401) rethrow;
        await refresh();
        if (_subject != subject)
          throw const DriverAuthException('The driver session changed.');
        await send();
      }
      await pending.acknowledge(baseUrl, subject, fingerprint);
    } on ApiException catch (error) {
      if (!error.uncertain)
        await pending.acknowledge(baseUrl, subject, fingerprint);
      rethrow;
    }
  }

  Future<DriverSession> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final generation = _generation;
    await ensureFresh();
    final result = await _api.request(
      '/auth/driver/password',
      method: 'POST',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    final next = DriverSession.fromResponse(result);
    await _save(next, expectedGeneration: generation);
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
}
