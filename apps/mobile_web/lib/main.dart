import 'package:flutter/material.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/auth/auth_service.dart';
import 'services/client/client_service.dart';
import 'services/settings/settings_service.dart';
import 'services/task/task_service.dart';
import 'services/workflow/workflow_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final tokenStorage = SecureTokenStorage();
  final apiClient = ApiClient(tokenStorage: tokenStorage);
  final authService = AuthService(apiClient: apiClient);
  final authProvider = AuthProvider(authService: authService);
  apiClient.onUnauthorized = () {
    authProvider.handleSessionExpired('Your session has expired. Please sign in again.');
  };
  final taskService = TaskService(apiClient: apiClient);
  final clientService = ClientService(apiClient: apiClient);
  final workflowService = WorkflowService(apiClient: apiClient);
  final settingsService = SettingsService(apiClient: apiClient);
  final settingsProvider = SettingsProvider(settingsService: settingsService);

  // Trigger startup session validation against /api/v1/auth/me
  authProvider.checkAuthStatus();

  runApp(NextActionApp(
    authProvider: authProvider,
    taskService: taskService,
    clientService: clientService,
    workflowService: workflowService,
    settingsProvider: settingsProvider,
  ));
}

/// Root Application Widget for NextAction with dynamic ThemeMode and Personalization.
class NextActionApp extends StatefulWidget {
  final AuthProvider authProvider;
  final TaskService taskService;
  final ClientService? clientService;
  final WorkflowService? workflowService;
  final SettingsProvider? settingsProvider;

  const NextActionApp({
    super.key,
    required this.authProvider,
    required this.taskService,
    this.clientService,
    this.workflowService,
    this.settingsProvider,
  });

  @override
  State<NextActionApp> createState() => _NextActionAppState();
}

class _NextActionAppState extends State<NextActionApp> {
  late final SettingsProvider _settingsProvider;
  bool _hasLoadedSettings = false;

  @override
  void initState() {
    super.initState();
    _settingsProvider = widget.settingsProvider ?? SettingsProvider();
    widget.authProvider.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  @override
  void dispose() {
    widget.authProvider.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (widget.authProvider.status == AuthStatus.authenticated && !_hasLoadedSettings) {
      _hasLoadedSettings = true;
      _settingsProvider.loadSettings();
    } else if (widget.authProvider.status != AuthStatus.authenticated) {
      _hasLoadedSettings = false;
      _settingsProvider.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.authProvider, _settingsProvider]),
      builder: (context, _) {
        return MaterialApp(
          title: 'NextAction',
          debugShowCheckedModeBanner: false,
          themeMode: _settingsProvider.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1E88E5),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            cardTheme: CardTheme(
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1E88E5),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            cardTheme: CardTheme(
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          home: _buildHomeForState(),
        );
      },
    );
  }

  Widget _buildHomeForState() {
    switch (widget.authProvider.status) {
      case AuthStatus.checking:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.task_alt,
                  size: 64,
                  color: Color(0xFF1E88E5),
                ),
                SizedBox(height: 24),
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Verifying NextAction session...',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        );

      case AuthStatus.authenticated:
        return HomeScreen(
          authProvider: widget.authProvider,
          taskService: widget.taskService,
          clientService: widget.clientService,
          workflowService: widget.workflowService,
          settingsProvider: _settingsProvider,
        );

      case AuthStatus.unauthenticated:
      case AuthStatus.error:
      default:
        return LoginScreen(
          authProvider: widget.authProvider,
        );
    }
  }
}
