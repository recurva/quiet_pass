import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Firebase ID token on-device so it can be attached as the
/// `Authorization: Bearer <token>` header on backend requests without
/// re-reading it from FirebaseAuth on every call.
class AuthTokenStore {
  AuthTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'quietpass.id_token';

  final FlutterSecureStorage _storage;

  Future<void> save(String idToken) => _storage.write(key: _tokenKey, value: idToken);

  Future<String?> read() => _storage.read(key: _tokenKey);

  Future<void> clear() => _storage.delete(key: _tokenKey);
}
