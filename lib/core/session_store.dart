import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  const SecureSessionStore();
  static const _storage = FlutterSecureStorage();
  static const _key = 'hired.driver.session.v1';
  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) await _storage.delete(key: 'driver_token');
    return value;
  }

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: 'driver_token');
  }
}
