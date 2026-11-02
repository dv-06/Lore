import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the LORE backend session token and lock preferences.
///
/// Production uses Android Keystore-backed encrypted storage. The token is
/// never written to shared preferences, logs, or the project database.
abstract class AuthStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clearToken();
  Future<int?> readAutoLockSeconds();
  Future<void> writeAutoLockSeconds(int seconds);
}

class SecureAuthStore implements AuthStore {
  static const _tokenKey = 'lore.auth.session_token';
  static const _autoLockKey = 'lore.auth.auto_lock_seconds';

  final FlutterSecureStorage _storage;

  SecureAuthStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: true,
              keyCipherAlgorithm:
                  KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
              storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
            ),
          );

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  @override
  Future<int?> readAutoLockSeconds() async {
    final raw = await _storage.read(key: _autoLockKey);
    return raw == null ? null : int.tryParse(raw);
  }

  @override
  Future<void> writeAutoLockSeconds(int seconds) =>
      _storage.write(key: _autoLockKey, value: seconds.toString());
}
