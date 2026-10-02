import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstract interface for local authentication token persistence.
abstract class TokenStorage {
  /// Save the signed JWT access token.
  Future<void> saveToken(String token);

  /// Retrieve the stored JWT access token, or null if not found.
  Future<String?> getToken();

  /// Delete the stored JWT access token.
  Future<void> deleteToken();

  /// Check whether a valid non-empty token is stored locally.
  Future<bool> hasToken();
}

/// Abstract interface for refresh token lifecycle persistence.
abstract class RefreshTokenStorage {
  /// Save the opaque refresh token.
  Future<void> saveRefreshToken(String token);

  /// Retrieve the stored refresh token, or null if not found.
  Future<String?> getRefreshToken();

  /// Delete the stored refresh token.
  Future<void> deleteRefreshToken();

  /// Delete all stored authentication credentials (access and refresh tokens).
  Future<void> clearAllTokens();
}

/// Secure token storage implementation using [FlutterSecureStorage].
///
/// Platforms:
/// - Android: Uses Android Keystore + EncryptedSharedPreferences (AES256).
/// - iOS/macOS: Uses Keychain Services.
/// - Windows: Uses Windows Data Protection API (DPAPI).
/// - Linux: Uses libsecret.
/// - Web: Uses browser local storage / IndexedDB with Web Cryptography API.
///   (Note: Web storage is subject to XSS attack vectors as the browser does
///   not possess an isolated hardware security module accessible to client JS).
class SecureTokenStorage implements TokenStorage, RefreshTokenStorage {
  static const String _tokenKey = 'nextaction_access_token';
  static const String _refreshTokenKey = 'nextaction_refresh_token';

  final FlutterSecureStorage _storage;
  String? _inMemoryCache;
  String? _inMemoryRefreshCache;

  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              wOptions: WindowsOptions(),
              webOptions: WebOptions(
                dbName: 'nextaction_secure_storage',
                publicKey: 'nextaction_web_enc_key',
              ),
            );

  @override
  Future<void> saveToken(String token) async {
    _inMemoryCache = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (e) {
      debugPrint('[SecureTokenStorage] Warning: Failed writing token to platform storage: $e');
    }
  }

  @override
  Future<String?> getToken() async {
    if (_inMemoryCache != null && _inMemoryCache!.isNotEmpty) {
      return _inMemoryCache;
    }
    try {
      final token = await _storage.read(key: _tokenKey);
      _inMemoryCache = token;
      return token;
    } catch (e) {
      debugPrint('[SecureTokenStorage] Warning: Failed reading token from platform storage: $e');
      return _inMemoryCache;
    }
  }

  @override
  Future<void> deleteToken() async {
    _inMemoryCache = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('[SecureTokenStorage] Warning: Failed deleting token from platform storage: $e');
    }
  }

  @override
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.trim().isNotEmpty;
  }

  @override
  Future<void> saveRefreshToken(String token) async {
    _inMemoryRefreshCache = token;
    try {
      await _storage.write(key: _refreshTokenKey, value: token);
    } catch (e) {
      debugPrint('[SecureTokenStorage] Warning: Failed writing refresh token: $e');
    }
  }

  @override
  Future<String?> getRefreshToken() async {
    if (_inMemoryRefreshCache != null && _inMemoryRefreshCache!.isNotEmpty) {
      return _inMemoryRefreshCache;
    }
    try {
      final token = await _storage.read(key: _refreshTokenKey);
      _inMemoryRefreshCache = token;
      return token;
    } catch (e) {
      debugPrint('[SecureTokenStorage] Warning: Failed reading refresh token: $e');
      return _inMemoryRefreshCache;
    }
  }

  @override
  Future<void> deleteRefreshToken() async {
    _inMemoryRefreshCache = null;
    try {
      await _storage.delete(key: _refreshTokenKey);
    } catch (e) {
      debugPrint('[SecureTokenStorage] Warning: Failed deleting refresh token: $e');
    }
  }

  @override
  Future<void> clearAllTokens() async {
    _inMemoryCache = null;
    _inMemoryRefreshCache = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    try {
      await _storage.delete(key: _refreshTokenKey);
    } catch (_) {}
  }
}
