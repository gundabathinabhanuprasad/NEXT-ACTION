import 'package:flutter/foundation.dart';
import '../core/errors/api_exception.dart';
import '../models/auth/auth_models.dart';
import '../services/auth/auth_service.dart';

enum AuthStatus {
  checking,
  unauthenticated,
  authenticated,
  error,
}

/// Authentication state manager coordinating session state across the application.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthStatus _status = AuthStatus.checking;
  User? _currentUser;
  String? _errorMessage;
  bool _isLoading = false;

  AuthProvider({AuthService? authService})
      : _authService = authService ?? AuthService();

  AuthStatus get status => _status;
  User? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _status == AuthStatus.authenticated && _currentUser != null;

  AuthService get authService => _authService;

  /// Validate authentication state on application startup.
  Future<void> checkAuthStatus() async {
    _status = AuthStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final hasToken = await _authService.hasStoredToken();
      if (!hasToken) {
        _status = AuthStatus.unauthenticated;
        _currentUser = null;
        notifyListeners();
        return;
      }

      // Backend /auth/me is the authoritative source of truth
      final user = await _authService.getCurrentUser();
      _currentUser = user;
      _status = AuthStatus.authenticated;
      _errorMessage = null;
    } on ApiException catch (e) {
      debugPrint('[AuthProvider] Startup auth check failed: ${e.message} (${e.statusCode})');
      // Token is invalid, expired, or rejected by backend
      await _authService.logout();
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      if (e.statusCode != 401) {
        // Network or server error on startup
        _errorMessage = e.message;
      }
    } catch (e) {
      debugPrint('[AuthProvider] Startup auth check unexpected error: $e');
      await _authService.logout();
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = 'Unable to verify authentication session.';
    } finally {
      notifyListeners();
    }
  }

  /// Authenticate user credentials.
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.login(email, password);
      final user = await _authService.getCurrentUser();
      _currentUser = user;
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _isLoading = false;
      _status = AuthStatus.unauthenticated;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _status = AuthStatus.unauthenticated;
      _errorMessage = 'Login failed: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Register a new user account.
  Future<User?> register(String name, String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.register(name, email, password);
      _isLoading = false;
      notifyListeners();
      return user;
    } on ApiException catch (e) {
      _isLoading = false;
      _errorMessage = e.message;
      notifyListeners();
      return null;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Registration failed: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  /// Invalidate session and log out.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.logout();
    } finally {
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Centralized handler for HTTP 401 session expiry or token invalidation.
  Future<void> handleSessionExpired([String message = 'Your session has expired. Please sign in again.']) async {
    if (_status == AuthStatus.unauthenticated && _currentUser == null) {
      return;
    }
    try {
      await _authService.logout();
    } catch (_) {}
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = message;
    _isLoading = false;
    notifyListeners();
  }

  /// Change authenticated user's password.
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.changePassword(currentPassword, newPassword);
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _isLoading = false;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to change password: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Clear any transient error message.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
