import '../../core/network/api_client.dart';
import '../../models/client/client_models.dart';

/// Service for interacting with Client endpoints in the FastAPI backend.
class ClientService {
  final ApiClient _apiClient;

  ClientService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  ApiClient get apiClient => _apiClient;

  /// Retrieve a list of clients with optional search and pagination.
  Future<ClientListResponse> getClients({
    String? search,
    int page = 1,
    int pageSize = 100,
  }) async {
    final queryParams = <String, dynamic>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
      'page_size': pageSize,
    };

    final response = await _apiClient.get(
      '/clients',
      queryParameters: queryParams,
      requiresAuth: true,
    );

    return ClientListResponse.fromJson(response as Map<String, dynamic>);
  }

  /// Retrieve a single client by its ID.
  Future<Client> getClient(String clientId) async {
    final response = await _apiClient.get(
      '/clients/$clientId',
      requiresAuth: true,
    );
    return Client.fromJson(response as Map<String, dynamic>);
  }

  /// Create a new client.
  Future<Client> createClient(ClientCreateRequest request) async {
    final response = await _apiClient.post(
      '/clients',
      body: request.toJson(),
      requiresAuth: true,
    );
    return Client.fromJson(response as Map<String, dynamic>);
  }

  /// Update an existing client.
  Future<Client> updateClient(String clientId, ClientUpdateRequest request) async {
    final response = await _apiClient.patch(
      '/clients/$clientId',
      body: request.toJson(),
      requiresAuth: true,
    );
    return Client.fromJson(response as Map<String, dynamic>);
  }
}
