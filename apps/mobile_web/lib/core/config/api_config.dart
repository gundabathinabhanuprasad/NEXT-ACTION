import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

/// Centralized API configuration for NextAction.
///
/// Supports dynamic base URL selection for Web, Android Emulator,
/// desktop, and physical devices without hardcoded single-environment URLs.
class ApiConfig {
  ApiConfig._();

  /// Default port for the NextAction FastAPI backend.
  static const int defaultPort = 8000;

  /// Custom base URL override (if provided at runtime or via environment).
  static String? _customBaseUrl;

  /// Set a runtime override for the API base URL.
  static void setBaseUrl(String? url) {
    _customBaseUrl = url;
  }

  /// Resolve the appropriate API base URL depending on the platform environment.
  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }

    // Compile-time environment variable override: --dart-define=API_BASE_URL=https://...
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      if (kReleaseMode && envUrl.startsWith('http://') && !envUrl.contains('localhost') && !envUrl.contains('127.0.0.1')) {
        debugPrint('[ApiConfig] Warning: Production API base URL should use HTTPS.');
      }
      return envUrl;
    }

    if (kIsWeb) {
      if (kReleaseMode) {
        return 'https://nextaction-backend-jkrp.onrender.com';
      }
      // Flutter Web development host
      return 'http://127.0.0.1:$defaultPort';
    }

    try {
      if (Platform.isAndroid) {
        // Android Emulator routes 10.0.2.2 to the development host's 127.0.0.1
        return 'http://10.0.2.2:$defaultPort';
      }
    } catch (_) {
      // Fallback if Platform is unsupported on target runtime
    }

    // Default for Desktop (Windows, macOS, Linux) and local testing
    return 'http://127.0.0.1:$defaultPort';
  }

  /// Full API v1 prefix URL.
  static String get v1BaseUrl => '$baseUrl/api/v1';

  /// Standard request timeout duration.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// Google Web OAuth Client ID configured at compile-time via --dart-define=GOOGLE_WEB_CLIENT_ID=...
  static const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Google Server / Audience Client ID configured at compile-time via --dart-define=GOOGLE_SERVER_CLIENT_ID=...
  static const String googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
}
