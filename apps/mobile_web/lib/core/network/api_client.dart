import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../errors/api_exception.dart';
import '../storage/token_storage.dart';

/// Centralized HTTP API Client for NextAction backend communication.
///
/// Encapsulates authentication headers, token refresh rotation,
/// JSON encoding/decoding, centralized error mapping, and network failure resiliency.
class ApiClient {
  final http.Client _httpClient;
  final TokenStorage _tokenStorage;
  final RefreshTokenStorage? _refreshTokenStorage;
  VoidCallback? onUnauthorized;

  Future<bool>? _refreshFuture;

  ApiClient({
    http.Client? httpClient,
    TokenStorage? tokenStorage,
    RefreshTokenStorage? refreshTokenStorage,
    this.onUnauthorized,
  })  : _httpClient = httpClient ?? http.Client(),
        _tokenStorage = tokenStorage ?? SecureTokenStorage(),
        _refreshTokenStorage = refreshTokenStorage ??
            (tokenStorage is RefreshTokenStorage
                ? tokenStorage as RefreshTokenStorage
                : (tokenStorage == null ? SecureTokenStorage() : null));

  TokenStorage get tokenStorage => _tokenStorage;
  RefreshTokenStorage? get refreshTokenStorage => _refreshTokenStorage;

  /// Build complete request headers, injecting Authorization Bearer token if present.
  Future<Map<String, String>> _buildHeaders({
    Map<String, String>? customHeaders,
    bool requiresAuth = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requiresAuth) {
      final token = await _tokenStorage.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    if (customHeaders != null) {
      headers.addAll(customHeaders);
    }

    return headers;
  }

  /// Construct a target URI relative to the API v1 base.
  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '${ApiConfig.v1BaseUrl}$cleanPath';

    if (queryParams == null || queryParams.isEmpty) {
      return Uri.parse(fullUrl);
    }

    // Filter out null query parameters and format to string values
    final filteredParams = <String, String>{};
    queryParams.forEach((key, value) {
      if (value != null) {
        if (value is DateTime) {
          filteredParams[key] = value.toIso8601String();
        } else {
          filteredParams[key] = value.toString();
        }
      }
    });

    return Uri.parse(fullUrl).replace(queryParameters: filteredParams);
  }

  /// Attempt refresh token rotation on server. Synchronized across concurrent requests.
  Future<bool> _attemptRefresh() async {
    if (_refreshTokenStorage == null) {
      return false;
    }
    if (_refreshFuture != null) {
      return _refreshFuture!;
    }

    _refreshFuture = () async {
      try {
        final currentRefreshToken = await _refreshTokenStorage.getRefreshToken();
        if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
          return false;
        }

        final refreshUri = Uri.parse('${ApiConfig.v1BaseUrl}/auth/refresh');
        final response = await _httpClient.post(
          refreshUri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'refresh_token': currentRefreshToken}),
        ).timeout(ApiConfig.receiveTimeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final newAccess = data['access_token'] as String;
          final newRefresh = data['refresh_token'] as String?;

          await _tokenStorage.saveToken(newAccess);
          if (newRefresh != null && newRefresh.isNotEmpty) {
            await _refreshTokenStorage.saveRefreshToken(newRefresh);
          }
          return true;
        } else {
          return false;
        }
      } catch (e) {
        debugPrint('[ApiClient] Token refresh attempt failed: $e');
        return false;
      } finally {
        _refreshFuture = null;
      }
    }();

    return _refreshFuture!;
  }

  /// Execute a GET request.
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    return _sendWithRefresh(
      path: path,
      requiresAuth: requiresAuth,
      customHeaders: headers,
      requestFn: (reqHeaders) {
        final uri = _buildUri(path, queryParameters);
        return _httpClient.get(uri, headers: reqHeaders);
      },
    );
  }

  /// Execute a GET request returning raw decoded response text (e.g. for CSV exports).
  Future<String> getRaw(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    final result = await _sendWithRefresh(
      path: path,
      requiresAuth: requiresAuth,
      customHeaders: headers,
      isRaw: true,
      requestFn: (reqHeaders) {
        final uri = _buildUri(path, queryParameters);
        return _httpClient.get(uri, headers: reqHeaders);
      },
    );
    return result as String;
  }

  /// Execute a POST request.
  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    final encodedBody = body != null ? jsonEncode(body) : null;
    return _sendWithRefresh(
      path: path,
      requiresAuth: requiresAuth,
      customHeaders: headers,
      requestFn: (reqHeaders) {
        final uri = _buildUri(path, queryParameters);
        return _httpClient.post(uri, headers: reqHeaders, body: encodedBody);
      },
    );
  }

  /// Execute a PATCH request.
  Future<dynamic> patch(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    final encodedBody = body != null ? jsonEncode(body) : null;
    return _sendWithRefresh(
      path: path,
      requiresAuth: requiresAuth,
      customHeaders: headers,
      requestFn: (reqHeaders) {
        final uri = _buildUri(path, queryParameters);
        return _httpClient.patch(uri, headers: reqHeaders, body: encodedBody);
      },
    );
  }

  /// Execute a DELETE request.
  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    return _sendWithRefresh(
      path: path,
      requiresAuth: requiresAuth,
      customHeaders: headers,
      requestFn: (reqHeaders) {
        final uri = _buildUri(path, queryParameters);
        return _httpClient.delete(uri, headers: reqHeaders);
      },
    );
  }

  /// Request execution wrapper with automatic refresh token rotation and retry.
  Future<dynamic> _sendWithRefresh({
    required String path,
    required bool requiresAuth,
    required Future<http.Response> Function(Map<String, String> headers) requestFn,
    Map<String, String>? customHeaders,
    bool isRaw = false,
  }) async {
    final initialHeaders = await _buildHeaders(
      customHeaders: customHeaders,
      requiresAuth: requiresAuth,
    );

    try {
      final response = await requestFn(initialHeaders).timeout(ApiConfig.receiveTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (isRaw) {
          return utf8.decode(response.bodyBytes);
        }
        if (response.body.isEmpty) {
          return null;
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      }

      // Check for automatic refresh candidate:
      final isAuthEndpoint = path.contains('/auth/login') ||
          path.contains('/auth/refresh') ||
          path.contains('/auth/register');

      if (response.statusCode == 401 && requiresAuth && !isAuthEndpoint) {
        final refreshed = await _attemptRefresh();
        if (refreshed) {
          // Retry original request with newly rotated access token:
          final retryHeaders = await _buildHeaders(
            customHeaders: customHeaders,
            requiresAuth: requiresAuth,
          );
          final retryResponse = await requestFn(retryHeaders).timeout(ApiConfig.receiveTimeout);

          if (retryResponse.statusCode >= 200 && retryResponse.statusCode < 300) {
            if (isRaw) {
              return utf8.decode(retryResponse.bodyBytes);
            }
            if (retryResponse.body.isEmpty) {
              return null;
            }
            return jsonDecode(utf8.decode(retryResponse.bodyBytes));
          }

          if (retryResponse.statusCode == 401) {
            await _tokenStorage.deleteToken();
            await _refreshTokenStorage?.clearAllTokens();
            onUnauthorized?.call();
          }
          throw ApiException.fromResponse(retryResponse.statusCode, retryResponse.body);
        } else {
          // Token refresh failed or no refresh token stored
          await _tokenStorage.deleteToken();
          await _refreshTokenStorage?.clearAllTokens();
          onUnauthorized?.call();
          throw ApiException.fromResponse(response.statusCode, response.body);
        }
      }

      if (response.statusCode == 401) {
        await _tokenStorage.deleteToken();
        await _refreshTokenStorage?.clearAllTokens();
        onUnauthorized?.call();
      }

      throw ApiException.fromResponse(response.statusCode, response.body);
    } on ApiException {
      rethrow;
    } on SocketException catch (e) {
      throw ApiException.network('Network connection failed: ${e.message}');
    } on TimeoutException {
      throw ApiException.network('Request timed out. Please verify your connection.');
    } catch (e) {
      if (e is FormatException) {
        throw const ApiException(
          statusCode: 500,
          errorCode: 'INVALID_JSON_RESPONSE',
          message: 'Received invalid data from server.',
        );
      }
      throw ApiException.network('Network error occurred: ${e.toString()}');
    }
  }

  /// Close underlying HTTP client resources.
  void close() {
    _httpClient.close();
  }
}
