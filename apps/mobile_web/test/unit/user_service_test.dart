import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextaction/core/network/api_client.dart';
import 'package:nextaction/core/storage/token_storage.dart';
import 'package:nextaction/models/auth/auth_models.dart';
import 'package:nextaction/services/user/user_service.dart';

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
  group('UserService and UserListResponse Tests', () {
    late TokenStorage tokenStorage;

    setUp(() {
      tokenStorage = InMemoryTokenStorage('test_jwt_token');
    });

    test('UserListResponse parses correctly from backend JSON', () {
      final json = {
        'items': [
          {
            'id': 'u-101',
            'name': 'Bhanu Pratap',
            'email': 'bhanu@nextaction.local',
            'is_active': true,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          },
          {
            'id': 'u-102',
            'name': 'Sarah Connor',
            'email': 'sarah@nextaction.local',
            'is_active': false,
            'created_at': '2026-09-28T08:00:00Z',
            'updated_at': '2026-09-28T09:00:00Z',
          }
        ],
        'total': 2,
        'page': 1,
        'page_size': 20,
      };

      final response = UserListResponse.fromJson(json);

      expect(response.total, equals(2));
      expect(response.page, equals(1));
      expect(response.pageSize, equals(20));
      expect(response.items.length, equals(2));

      final first = response.items[0];
      expect(first.id, equals('u-101'));
      expect(first.name, equals('Bhanu Pratap'));
      expect(first.email, equals('bhanu@nextaction.local'));
      expect(first.isActive, isTrue);

      final second = response.items[1];
      expect(second.id, equals('u-102'));
      expect(second.name, equals('Sarah Connor'));
      expect(second.isActive, isFalse);
    });

    test('UserService.getCurrentUser calls /auth/me with Bearer token', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/auth/me'));
        expect(request.headers['Authorization'], equals('Bearer test_jwt_token'));
        return http.Response(
          jsonEncode({
            'id': 'u-me',
            'name': 'Current User',
            'email': 'me@nextaction.local',
            'is_active': true,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = UserService(apiClient: apiClient);

      final user = await service.getCurrentUser();
      expect(user.id, equals('u-me'));
      expect(user.name, equals('Current User'));
      expect(user.email, equals('me@nextaction.local'));
      expect(user.isActive, isTrue);
    });

    test('UserService.getUsers sends search, is_active and pagination queries', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/users'));
        expect(request.url.queryParameters['search'], equals('Sarah'));
        expect(request.url.queryParameters['is_active'], equals('true'));
        expect(request.url.queryParameters['page'], equals('1'));
        expect(request.url.queryParameters['page_size'], equals('50'));
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'u-102',
                'name': 'Sarah Connor',
                'email': 'sarah@nextaction.local',
                'is_active': true,
                'created_at': '2026-09-28T08:00:00Z',
                'updated_at': '2026-09-28T09:00:00Z',
              }
            ],
            'total': 1,
            'page': 1,
            'page_size': 50,
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = UserService(apiClient: apiClient);

      final response = await service.getUsers(
        search: 'Sarah',
        isActive: true,
        page: 1,
        pageSize: 50,
      );

      expect(response.total, equals(1));
      expect(response.items.first.name, equals('Sarah Connor'));
    });

    test('UserService.getUser fetches single user by ID', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/users/u-999'));
        return http.Response(
          jsonEncode({
            'id': 'u-999',
            'name': 'Target User',
            'email': 'target@nextaction.local',
            'is_active': true,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(httpClient: mockClient, tokenStorage: tokenStorage);
      final service = UserService(apiClient: apiClient);

      final user = await service.getUser('u-999');
      expect(user.id, equals('u-999'));
      expect(user.name, equals('Target User'));
    });
  });
}
