import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/errors/api_exception.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/services/auth/auth_service.dart';

import 'package:google_sign_in/google_sign_in.dart';

class InMemoryTokenStorage implements TokenStorage {
  String? token;
  InMemoryTokenStorage([this.token]);

  @override
  Future<void> saveToken(String token) async => this.token = token;
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> deleteToken() async => token = null;
  @override
  Future<bool> hasToken() async => token != null && token!.isNotEmpty;
}

class FakeGoogleSignInAuthentication implements GoogleSignInAuthentication {
  @override
  final String? accessToken;
  @override
  final String? idToken;
  @override
  final String? serverAuthCode;

  FakeGoogleSignInAuthentication({
    this.accessToken = 'mock_google_access_token',
    this.idToken = 'mock_google_id_token',
    this.serverAuthCode,
  });
}

class FakeGoogleSignInAccount implements GoogleSignInAccount {
  @override
  final String email;
  @override
  final String id;
  @override
  final String displayName;
  @override
  final String? photoUrl;
  @override
  final String? serverAuthCode;
  final String? _mockIdToken;

  FakeGoogleSignInAccount({
    required this.email,
    required this.id,
    required this.displayName,
    this.photoUrl,
    this.serverAuthCode,
    String? mockIdToken,
  }) : _mockIdToken = mockIdToken;

  @override
  Future<GoogleSignInAuthentication> get authentication async =>
      FakeGoogleSignInAuthentication(idToken: _mockIdToken);

  @override
  Future<Map<String, String>> get authHeaders async => {};

  @override
  Future<void> clearAuthCache() async {}
}

class FakeGoogleSignIn implements GoogleSignIn {
  final GoogleSignInAccount? accountToReturn;
  final bool shouldThrow;
  bool signedOutCalled = false;
  bool _isSignedIn = false;

  FakeGoogleSignIn({
    this.accountToReturn,
    this.shouldThrow = false,
    bool initiallySignedIn = false,
  }) : _isSignedIn = initiallySignedIn;

  @override
  Future<GoogleSignInAccount?> signIn() async {
    if (shouldThrow) {
      throw Exception('Simulated Google Sign-In exception');
    }
    if (accountToReturn != null) {
      _isSignedIn = true;
    }
    return accountToReturn;
  }

  @override
  Future<bool> isSignedIn() async => _isSignedIn;

  @override
  Future<GoogleSignInAccount?> signOut() async {
    signedOutCalled = true;
    _isSignedIn = false;
    return null;
  }

  @override
  Future<GoogleSignInAccount?> disconnect() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AuthService Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = InMemoryTokenStorage();
    });

    test('login success stores access token and returns TokenResponse', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'test_jwt_access_token_123',
              'token_type': 'bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      final tokenResponse = await authService.login('alice@example.com', 'secret123');

      expect(tokenResponse.accessToken, equals('test_jwt_access_token_123'));
      expect(tokenResponse.expiresIn, equals(3600));
      expect(await tokenStorage.getToken(), equals('test_jwt_access_token_123'));
      expect(await authService.hasStoredToken(), isTrue);
    });

    test('login failure throws ApiException and does not store token', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid email or password.',
          }),
          401,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      expect(
        () async => await authService.login('alice@example.com', 'wrong_pass'),
        throwsA(isA<ApiException>().having((e) => e.errorCode, 'errorCode', 'INVALID_CREDENTIALS')),
      );

      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('getCurrentUser retrieves user profile using stored JWT', () async {
      tokenStorage.token = 'valid_token';

      final mockClient = MockClient((request) async {
        expect(request.headers['Authorization'], equals('Bearer valid_token'));
        return http.Response(
          jsonEncode({
            'id': 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
            'name': 'Alice Smith',
            'email': 'alice@example.com',
            'is_active': true,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      final user = await authService.getCurrentUser();
      expect(user.id, equals('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d'));
      expect(user.name, equals('Alice Smith'));
      expect(user.email, equals('alice@example.com'));
      expect(user.isActive, isTrue);
    });

    test('logout clears stored token', () async {
      tokenStorage.token = 'existing_token';
      expect(await tokenStorage.hasToken(), isTrue);

      final apiClient = ApiClient(httpClient: MockClient((_) async => http.Response('', 200)), tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      await authService.logout();
      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('signInWithGoogle success exchanges ID token with backend and stores session', () async {
      final fakeAccount = FakeGoogleSignInAccount(
        id: 'google_123',
        email: 'google.alice@example.com',
        displayName: 'Google Alice',
        mockIdToken: 'google_verified_id_token_abc',
      );
      final fakeGoogle = FakeGoogleSignIn(accountToReturn: fakeAccount);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/google') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['id_token'], equals('google_verified_id_token_abc'));
          return http.Response(
            jsonEncode({
              'access_token': 'nextaction_google_jwt_access',
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'nextaction_google_jwt_refresh',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      final result = await authService.signInWithGoogle(customGoogleSignIn: fakeGoogle);

      expect(result, isNotNull);
      expect(result!.accessToken, equals('nextaction_google_jwt_access'));
      expect(result.refreshToken, equals('nextaction_google_jwt_refresh'));
      expect(await tokenStorage.getToken(), equals('nextaction_google_jwt_access'));
      expect(await authService.hasStoredToken(), isTrue);
    });

    test('signInWithGoogle cancellation returns null without calling backend', () async {
      final fakeGoogle = FakeGoogleSignIn(accountToReturn: null); // Cancelled
      var backendCalled = false;

      final mockClient = MockClient((request) async {
        backendCalled = true;
        return http.Response('Should not be called', 500);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      final result = await authService.signInWithGoogle(customGoogleSignIn: fakeGoogle);

      expect(result, isNull);
      expect(backendCalled, isFalse);
      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('signInWithGoogle throws ApiException when idToken is missing', () async {
      final fakeAccount = FakeGoogleSignInAccount(
        id: 'google_123',
        email: 'alice@example.com',
        displayName: 'Alice',
        mockIdToken: null, // Missing ID token
      );
      final fakeGoogle = FakeGoogleSignIn(accountToReturn: fakeAccount);

      final apiClient = ApiClient(httpClient: MockClient((_) async => http.Response('', 200)), tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      expect(
        () async => await authService.signInWithGoogle(customGoogleSignIn: fakeGoogle),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('signInWithGoogle throws ApiException on backend 401 rejection', () async {
      final fakeAccount = FakeGoogleSignInAccount(
        id: 'google_123',
        email: 'alice@example.com',
        displayName: 'Alice',
        mockIdToken: 'bad_token',
      );
      final fakeGoogle = FakeGoogleSignIn(accountToReturn: fakeAccount);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'INVALID_CREDENTIALS',
            'message': 'Invalid token signature',
          }),
          401,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      expect(
        () async => await authService.signInWithGoogle(customGoogleSignIn: fakeGoogle),
        throwsA(isA<ApiException>().having((e) => e.errorCode, 'errorCode', 'INVALID_CREDENTIALS')),
      );
      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('logout invokes Google sign out when signed in', () async {
      final fakeGoogle = FakeGoogleSignIn(initiallySignedIn: true);
      final apiClient = ApiClient(httpClient: MockClient((_) async => http.Response('', 200)), tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);

      await authService.logout(customGoogleSignIn: fakeGoogle);

      expect(fakeGoogle.signedOutCalled, isTrue);
    });
  });
}
