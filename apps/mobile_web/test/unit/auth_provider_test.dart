import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/providers/auth_provider.dart';
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
  group('AuthProvider Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = InMemoryTokenStorage();
    });

    test('initial checkAuthStatus with no token transitions to unauthenticated', () async {
      final mockClient = MockClient((_) async => http.Response('Not reached', 500));
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      expect(provider.status, equals(AuthStatus.checking));

      await provider.checkAuthStatus();

      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.currentUser, isNull);
      expect(provider.isAuthenticated, isFalse);
    });

    test('checkAuthStatus with valid token transitions to authenticated', () async {
      tokenStorage.token = 'valid_token_xyz';

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 'b1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
              'name': 'Bob Tester',
              'email': 'bob@example.com',
              'is_active': true,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      await provider.checkAuthStatus();

      expect(provider.status, equals(AuthStatus.authenticated));
      expect(provider.currentUser, isNotNull);
      expect(provider.currentUser?.email, equals('bob@example.com'));
      expect(provider.isAuthenticated, isTrue);
    });

    test('checkAuthStatus with expired/invalid 401 token deletes token and becomes unauthenticated', () async {
      tokenStorage.token = 'expired_token';

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'INVALID_TOKEN', 'message': 'Token expired or signature invalid'}),
          401,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      await provider.checkAuthStatus();

      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.currentUser, isNull);
      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('login establishes authenticated state with user profile', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'new_valid_token',
              'token_type': 'bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 'u100',
              'name': 'Charlie',
              'email': 'charlie@example.com',
              'is_active': true,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final success = await provider.login('charlie@example.com', 'mypassword');

      expect(success, isTrue);
      expect(provider.status, equals(AuthStatus.authenticated));
      expect(provider.currentUser?.name, equals('Charlie'));
    });

    test('logout transitions state to unauthenticated', () async {
      tokenStorage.token = 'sample_token';
      final apiClient = ApiClient(httpClient: MockClient((_) async => http.Response('', 200)), tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      await provider.logout();

      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.currentUser, isNull);
      expect(await tokenStorage.hasToken(), isFalse);
    });

    test('checkAuthStatus with network timeout transitions to unauthenticated without setting errorMessage and preserves token', () async {
      tokenStorage.token = 'existing_token_xyz';

      final mockClient = MockClient((request) async {
        throw TimeoutException('Request timed out while backend waking');
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      await provider.checkAuthStatus();

      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.currentUser, isNull);
      expect(provider.errorMessage, isNull);
      expect(await tokenStorage.hasToken(), isTrue);
    });

    test('checkAuthStatus with 503 Service Unavailable (cold start waking) transitions to unauthenticated without setting errorMessage', () async {
      tokenStorage.token = 'existing_token_xyz';

      final mockClient = MockClient((request) async {
        return http.Response('Service Unavailable: Cold Start Waking', 503);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      await provider.checkAuthStatus();

      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.currentUser, isNull);
      expect(provider.errorMessage, isNull);
    });

    test('login failure with timeout still sets errorMessage for user feedback', () async {
      final mockClient = MockClient((request) async {
        throw TimeoutException('Login connection timed out');
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final success = await provider.login('user@example.com', 'wrong_or_slow');

      expect(success, isFalse);
      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.errorMessage, contains('Request timed out'));
    });

    test('login failure with 401 still sets errorMessage for user feedback', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'INVALID_CREDENTIALS', 'message': 'Invalid email or password'}),
          401,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final success = await provider.login('user@example.com', 'bad_pw');

      expect(success, isFalse);
      expect(provider.status, equals(AuthStatus.unauthenticated));
      expect(provider.errorMessage, equals('Invalid email or password'));
    });

    test('register failure with network timeout still sets errorMessage for user feedback', () async {
      final mockClient = MockClient((request) async {
        throw TimeoutException('Registration timeout');
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final user = await provider.register('Alice', 'alice@example.com', 'secret');

      expect(user, isNull);
      expect(provider.errorMessage, contains('Request timed out'));
    });

    test('signInWithGoogle success transitions to authenticated and sets currentUser', () async {
      final fakeAccount = FakeGoogleSignInAccount(
        id: 'google_777',
        email: 'google_provider@example.com',
        displayName: 'Google Provider User',
        mockIdToken: 'valid_id_token_xyz',
      );
      final fakeGoogle = FakeGoogleSignIn(accountToReturn: fakeAccount);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/google') {
          return http.Response(
            jsonEncode({
              'access_token': 'nextaction_google_jwt_access_provider',
              'token_type': 'bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 'u1-google-uuid',
              'name': 'Google Provider User',
              'email': 'google_provider@example.com',
              'is_active': true,
              'created_at': '2026-09-27T10:00:00Z',
              'updated_at': '2026-09-27T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final success = await provider.signInWithGoogle(customGoogleSignIn: fakeGoogle);

      expect(success, isTrue);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.status, equals(AuthStatus.authenticated));
      expect(provider.currentUser?.email, equals('google_provider@example.com'));
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('signInWithGoogle cancellation returns false without setting error message', () async {
      final fakeGoogle = FakeGoogleSignIn(accountToReturn: null); // Cancelled

      final mockClient = MockClient((_) async => http.Response('Should not be called', 500));
      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final success = await provider.signInWithGoogle(customGoogleSignIn: fakeGoogle);

      expect(success, isFalse);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.status, equals(AuthStatus.unauthenticated));
      // CRITICAL: User cancellation MUST NOT display any error message
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('signInWithGoogle backend failure sets errorMessage and remains unauthenticated', () async {
      final fakeAccount = FakeGoogleSignInAccount(
        id: 'google_777',
        email: 'bad@example.com',
        displayName: 'Bad',
        mockIdToken: 'bad_token',
      );
      final fakeGoogle = FakeGoogleSignIn(accountToReturn: fakeAccount);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'INVALID_CREDENTIALS',
            'message': 'Google credential token expired or signature invalid',
          }),
          401,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final success = await provider.signInWithGoogle(customGoogleSignIn: fakeGoogle);

      expect(success, isFalse);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.errorMessage, contains('Google credential token expired'));
      expect(provider.isLoading, isFalse);
    });

    test('signInWithGoogle unexpected exception sets errorMessage gracefully', () async {
      final fakeGoogle = FakeGoogleSignIn(shouldThrow: true); // Throws exception

      final apiClient = ApiClient(httpClient: MockClient((_) async => http.Response('', 200)), tokenStorage: tokenStorage);
      final authService = AuthService(apiClient: apiClient);
      final provider = AuthProvider(authService: authService);

      final success = await provider.signInWithGoogle(customGoogleSignIn: fakeGoogle);

      expect(success, isFalse);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.errorMessage, contains('Google sign-in failed'));
      expect(provider.isLoading, isFalse);
    });
  });
}
