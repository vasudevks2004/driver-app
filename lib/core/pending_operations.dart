import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String operationFingerprint(String method, String path, Object? body) => sha256
    .convert(utf8.encode('$method|$path|${jsonEncode(_canonical(body))}'))
    .toString();
String newRequestKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

abstract interface class PendingOperationStorage {
  Future<String?> read(String scope);
  Future<void> write(String scope, String value);
}

class SecureOperationStorage implements PendingOperationStorage {
  const SecureOperationStorage();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String scope) =>
      _storage.read(key: 'hired.pending.$scope');
  @override
  Future<void> write(String scope, String value) =>
      _storage.write(key: 'hired.pending.$scope', value: value);
}

class MemoryOperationStorage implements PendingOperationStorage {
  final _values = <String, String>{};
  @override
  Future<String?> read(String scope) async => _values[scope];
  @override
  Future<void> write(String scope, String value) async {
    _values[scope] = value;
  }
}

/// Only payload hashes and random keys are stored, never OTPs or request bodies.
/// The scope binds pending actions to the verified driver and backend.
class PendingOperations {
  PendingOperations({PendingOperationStorage? storage})
    : _storage = storage ?? const SecureOperationStorage();
  final PendingOperationStorage _storage;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  String _scope(String server, String subject) =>
      sha256.convert(utf8.encode('$server|$subject')).toString();
  Future<Map<String, dynamic>> _read(String scope) async {
    final raw = await _storage.read(scope);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      throw StateError(
        'Pending changes could not be recovered. Contact HireD before submitting more changes.',
      );
    }
  }

  Future<String> begin(String server, String subject, String fingerprint) =>
      _serial(() async {
        final scope = _scope(server, subject), values = await _read(scope);
        if (values[fingerprint] is String) return values[fingerprint] as String;
        if (values.length >= 100)
          throw StateError(
            'Too many changes need confirmation. Contact HireD support.',
          );
        final key = newRequestKey();
        values[fingerprint] = key;
        await _storage.write(scope, jsonEncode(values));
        return key;
      });
  Future<void> acknowledge(String server, String subject, String fingerprint) =>
      _serial(() async {
        final scope = _scope(server, subject), values = await _read(scope);
        values.remove(fingerprint);
        await _storage.write(scope, jsonEncode(values));
      });
}
