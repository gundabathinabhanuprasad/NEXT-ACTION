import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/config/api_config.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';
import 'package:nextaction/services/client/client_service.dart';
import 'package:nextaction/services/workflow/workflow_service.dart';

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

void main() {
  group('ClientService and WorkflowService Tests', () {
    late InMemoryTokenStorage tokenStorage;

    setUp(() {
      ApiConfig.setBaseUrl('http://127.0.0.1:8000');
      tokenStorage = InMemoryTokenStorage('valid_test_token');
    });

    test('ClientService.getClients sends search and authorization header', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/clients'));
        expect(request.url.queryParameters['search'], equals('Wayne'));
        expect(request.headers['Authorization'], equals('Bearer valid_test_token'));
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'c-101',
                'name': 'Wayne Enterprises',
                'company': 'Wayne Corp',
                'email': 'contact@wayne.com',
                'phone': '12345',
                'notes': 'Notes',
                'created_at': '2026-09-27T10:00:00Z',
                'updated_at': '2026-09-27T10:00:00Z',
              }
            ],
            'total': 1,
            'page': 1,
            'page_size': 100,
          }),
          200,
        );
      });

      final apiClient = ApiClient(tokenStorage: tokenStorage, httpClient: mockClient);
      final clientService = ClientService(apiClient: apiClient);

      final response = await clientService.getClients(search: 'Wayne');
      expect(response.total, 1);
      expect(response.items.first.name, 'Wayne Enterprises');
    });

    test('ClientService.getClient fetches single client by ID', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/clients/c-101'));
        return http.Response(
          jsonEncode({
            'id': 'c-101',
            'name': 'Wayne Enterprises',
            'company': 'Wayne Corp',
            'email': 'contact@wayne.com',
            'phone': '12345',
            'notes': 'Notes',
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(tokenStorage: tokenStorage, httpClient: mockClient);
      final clientService = ClientService(apiClient: apiClient);

      final client = await clientService.getClient('c-101');
      expect(client.id, 'c-101');
      expect(client.name, 'Wayne Enterprises');
    });

    test('ClientService.createClient posts new client payload', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/clients'));
        expect(request.method, equals('POST'));
        final body = jsonDecode(request.body);
        expect(body['name'], equals('Stark Industries'));
        return http.Response(
          jsonEncode({
            'id': 'c-202',
            'name': 'Stark Industries',
            'company': 'Stark Corp',
            'email': null,
            'phone': null,
            'notes': null,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          201,
        );
      });

      final apiClient = ApiClient(tokenStorage: tokenStorage, httpClient: mockClient);
      final clientService = ClientService(apiClient: apiClient);

      final created = await clientService.createClient(
        const ClientCreateRequest(name: 'Stark Industries', company: 'Stark Corp'),
      );
      expect(created.id, 'c-202');
      expect(created.name, 'Stark Industries');
    });

    test('ClientService.updateClient sends PATCH request', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/clients/c-202'));
        expect(request.method, equals('PATCH'));
        final body = jsonDecode(request.body);
        expect(body['name'], equals('Stark Global'));
        return http.Response(
          jsonEncode({
            'id': 'c-202',
            'name': 'Stark Global',
            'company': 'Stark Corp',
            'email': null,
            'phone': null,
            'notes': null,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:30:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(tokenStorage: tokenStorage, httpClient: mockClient);
      final clientService = ClientService(apiClient: apiClient);

      final updated = await clientService.updateClient(
        'c-202',
        const ClientUpdateRequest(name: 'Stark Global'),
      );
      expect(updated.name, 'Stark Global');
    });

    test('WorkflowService.getWorkflows queries /api/v1/workflows with is_active filter', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/workflows'));
        expect(request.url.queryParameters['is_active'], equals('true'));
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'w-1',
                'name': 'Onboarding Pipeline',
                'description': '14-day pipeline',
                'is_active': true,
                'created_at': '2026-09-27T08:00:00Z',
                'updated_at': '2026-09-27T08:00:00Z',
              }
            ],
            'total': 1,
            'page': 1,
            'page_size': 100,
          }),
          200,
        );
      });

      final apiClient = ApiClient(tokenStorage: tokenStorage, httpClient: mockClient);
      final workflowService = WorkflowService(apiClient: apiClient);

      final response = await workflowService.getWorkflows(isActive: true);
      expect(response.total, 1);
      expect(response.items.first.name, 'Onboarding Pipeline');
    });

    test('WorkflowService.createWorkflow and updateWorkflow operate cleanly', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'id': 'w-2',
              'name': 'Sprint Cycle',
              'description': 'Bi-weekly sprint',
              'is_active': true,
              'created_at': '2026-09-27T08:00:00Z',
              'updated_at': '2026-09-27T08:00:00Z',
            }),
            201,
          );
        } else if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'id': 'w-2',
              'name': 'Sprint Cycle v2',
              'description': 'Bi-weekly sprint',
              'is_active': false,
              'created_at': '2026-09-27T08:00:00Z',
              'updated_at': '2026-09-27T08:30:00Z',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(tokenStorage: tokenStorage, httpClient: mockClient);
      final workflowService = WorkflowService(apiClient: apiClient);

      final created = await workflowService.createWorkflow(
        const WorkflowCreateRequest(name: 'Sprint Cycle', description: 'Bi-weekly sprint'),
      );
      expect(created.id, 'w-2');
      expect(created.isActive, isTrue);

      final updated = await workflowService.updateWorkflow(
        'w-2',
        const WorkflowUpdateRequest(name: 'Sprint Cycle v2', isActive: false),
      );
      expect(updated.name, 'Sprint Cycle v2');
      expect(updated.isActive, isFalse);
    });
  });
}
