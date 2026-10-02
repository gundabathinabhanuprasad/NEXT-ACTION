import 'dart:convert';

/// Represents a structured API or network error originating from the FastAPI backend.
class ApiException implements Exception {
  final int statusCode;
  final String errorCode;
  final String message;
  final dynamic details;

  const ApiException({
    required this.statusCode,
    required this.errorCode,
    required this.message,
    this.details,
  });

  /// Parse an HTTP response into a structured [ApiException].
  factory ApiException.fromResponse(int statusCode, String responseBody) {
    String errorCode = 'UNKNOWN_ERROR';
    String message = 'An unexpected server error occurred (HTTP $statusCode).';
    dynamic details;

    try {
      if (responseBody.isNotEmpty) {
        final decoded = jsonDecode(responseBody);
        if (decoded is Map<String, dynamic>) {
          // Standard NextAction Domain Error format: {"error": "...", "message": "..."}
          if (decoded.containsKey('error') && decoded['error'] is String) {
            errorCode = decoded['error'] as String;
          }
          if (decoded.containsKey('message') && decoded['message'] is String) {
            message = decoded['message'] as String;
          } else if (decoded.containsKey('detail')) {
            final detail = decoded['detail'];
            if (detail is String) {
              message = detail;
              errorCode = _mapStatusToCode(statusCode);
            } else if (detail is List) {
              errorCode = 'VALIDATION_ERROR';
              message = _formatValidationErrors(detail);
              details = detail;
            }
          }
        }
      }
    } catch (_) {
      // Non-JSON response body fallback
      message = 'Server response error ($statusCode): ${responseBody.take(100)}';
    }

    if (errorCode == 'UNKNOWN_ERROR') {
      errorCode = _mapStatusToCode(statusCode);
    }

    return ApiException(
      statusCode: statusCode,
      errorCode: errorCode,
      message: message,
      details: details,
    );
  }

  /// Factory for client-side connection/timeout network errors.
  factory ApiException.network(String message) {
    return ApiException(
      statusCode: 0,
      errorCode: 'NETWORK_UNAVAILABLE',
      message: message,
    );
  }

  /// Factory for unauthorized session errors.
  factory ApiException.unauthorized([String message = 'Authentication required. Please sign in.']) {
    return ApiException(
      statusCode: 401,
      errorCode: 'AUTHENTICATION_REQUIRED',
      message: message,
    );
  }

  static String _mapStatusToCode(int status) {
    switch (status) {
      case 400:
        return 'BAD_REQUEST';
      case 401:
        return 'UNAUTHORIZED';
      case 403:
        return 'FORBIDDEN';
      case 404:
        return 'NOT_FOUND';
      case 409:
        return 'CONFLICT';
      case 422:
        return 'VALIDATION_ERROR';
      case 500:
        return 'INTERNAL_SERVER_ERROR';
      default:
        return 'HTTP_$status';
    }
  }

  static String _formatValidationErrors(List<dynamic> detailList) {
    final messages = <String>[];
    for (final item in detailList) {
      if (item is Map<String, dynamic>) {
        final loc = (item['loc'] as List<dynamic>?)?.join(' -> ') ?? '';
        final msg = item['msg'] ?? 'invalid value';
        if (loc.isNotEmpty) {
          messages.add('$loc: $msg');
        } else {
          messages.add('$msg');
        }
      }
    }
    return messages.isNotEmpty ? messages.join(', ') : 'Validation failed for request fields.';
  }

  @override
  String toString() => 'ApiException [$errorCode ($statusCode)]: $message';
}

extension _StringHelper on String {
  String take(int count) => length <= count ? this : substring(0, count);
}
