import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/models/client/client_models.dart';
import 'package:nextaction/models/workflow/workflow_models.dart';

void main() {
  group('Client and Workflow Model Serialization Tests', () {
    test('Client model parses correctly from backend JSON', () {
      final json = {
        'id': 'c7f9e8a1-3b4c-4d5e-a6f7-1a2b3c4d5e6f',
        'name': 'Wayne Enterprises',
        'company': 'Wayne Corp',
        'email': 'bruce@wayne.com',
        'phone': '+1-555-0100',
        'notes': 'Key accounts',
        'created_at': '2026-09-27T10:00:00Z',
        'updated_at': '2026-09-27T10:30:00Z',
      };

      final client = Client.fromJson(json);

      expect(client.id, 'c7f9e8a1-3b4c-4d5e-a6f7-1a2b3c4d5e6f');
      expect(client.name, 'Wayne Enterprises');
      expect(client.company, 'Wayne Corp');
      expect(client.email, 'bruce@wayne.com');
      expect(client.phone, '+1-555-0100');
      expect(client.notes, 'Key accounts');
      expect(client.displayName, 'Wayne Enterprises (Wayne Corp)');
      expect(client.createdAt, DateTime.parse('2026-09-27T10:00:00Z'));
      expect(client.updatedAt, DateTime.parse('2026-09-27T10:30:00Z'));
    });

    test('ClientListResponse parses multiple items and pagination', () {
      final json = {
        'items': [
          {
            'id': 'c1',
            'name': 'Client One',
            'company': null,
            'email': null,
            'phone': null,
            'notes': null,
            'created_at': '2026-09-27T10:00:00Z',
            'updated_at': '2026-09-27T10:00:00Z',
          },
          {
            'id': 'c2',
            'name': 'Client Two',
            'company': 'Company B',
            'email': 'b@b.com',
            'phone': '123',
            'notes': 'Test note',
            'created_at': '2026-09-27T11:00:00Z',
            'updated_at': '2026-09-27T11:00:00Z',
          }
        ],
        'total': 2,
        'page': 1,
        'page_size': 100,
      };

      final response = ClientListResponse.fromJson(json);

      expect(response.total, 2);
      expect(response.items.length, 2);
      expect(response.items[0].name, 'Client One');
      expect(response.items[0].displayName, 'Client One');
      expect(response.items[1].name, 'Client Two');
      expect(response.items[1].displayName, 'Client Two (Company B)');
    });

    test('Workflow model parses correctly from backend JSON', () {
      final json = {
        'id': 'w123-456',
        'name': 'Enterprise Onboarding',
        'description': '14-day workflow pipeline',
        'is_active': true,
        'created_at': '2026-09-27T08:00:00Z',
        'updated_at': '2026-09-27T08:00:00Z',
      };

      final workflow = Workflow.fromJson(json);

      expect(workflow.id, 'w123-456');
      expect(workflow.name, 'Enterprise Onboarding');
      expect(workflow.description, '14-day workflow pipeline');
      expect(workflow.isActive, isTrue);
      expect(workflow.createdAt, DateTime.parse('2026-09-27T08:00:00Z'));
    });

    test('WorkflowListResponse parses multiple items and pagination', () {
      final json = {
        'items': [
          {
            'id': 'w1',
            'name': 'Workflow Alpha',
            'description': null,
            'is_active': true,
            'created_at': '2026-09-27T08:00:00Z',
            'updated_at': '2026-09-27T08:00:00Z',
          },
          {
            'id': 'w2',
            'name': 'Workflow Beta',
            'description': 'Inactive legacy workflow',
            'is_active': false,
            'created_at': '2026-09-27T08:00:00Z',
            'updated_at': '2026-09-27T08:00:00Z',
          }
        ],
        'total': 2,
        'page': 1,
        'page_size': 50,
      };

      final response = WorkflowListResponse.fromJson(json);

      expect(response.total, 2);
      expect(response.items.length, 2);
      expect(response.items[0].name, 'Workflow Alpha');
      expect(response.items[0].isActive, isTrue);
      expect(response.items[1].name, 'Workflow Beta');
      expect(response.items[1].isActive, isFalse);
    });

    test('ClientCreateRequest and ClientUpdateRequest serialize correctly', () {
      const createReq = ClientCreateRequest(
        name: 'Stark Industries',
        company: 'Stark Corp',
        email: 'tony@stark.com',
        phone: '999',
        notes: 'VIP Client',
      );
      final createJson = createReq.toJson();
      expect(createJson['name'], 'Stark Industries');
      expect(createJson['company'], 'Stark Corp');
      expect(createJson['email'], 'tony@stark.com');
      expect(createJson['phone'], '999');
      expect(createJson['notes'], 'VIP Client');

      const updateReq = ClientUpdateRequest(
        name: 'Stark Global',
      );
      final updateJson = updateReq.toJson();
      expect(updateJson['name'], 'Stark Global');
      expect(updateJson.containsKey('company'), isFalse);
    });

    test('WorkflowCreateRequest and WorkflowUpdateRequest serialize correctly', () {
      const createReq = WorkflowCreateRequest(
        name: 'Sprint Pipeline',
        description: 'Two-week sprint cycle',
        isActive: true,
      );
      final createJson = createReq.toJson();
      expect(createJson['name'], 'Sprint Pipeline');
      expect(createJson['description'], 'Two-week sprint cycle');
      expect(createJson['is_active'], isTrue);

      const updateReq = WorkflowUpdateRequest(
        isActive: false,
      );
      final updateJson = updateReq.toJson();
      expect(updateJson['is_active'], isFalse);
      expect(updateJson.containsKey('name'), isFalse);
    });
  });
}
