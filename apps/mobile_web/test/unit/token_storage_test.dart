import 'package:flutter_test/flutter_test.dart';
import 'package:nextaction/core/storage/token_storage.dart';

class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }

  @override
  Future<String?> getToken() async {
    return _token;
  }

  @override
  Future<void> deleteToken() async {
    _token = null;
  }

  @override
  Future<bool> hasToken() async {
    return _token != null && _token!.isNotEmpty;
  }
}

void main() {
  group('TokenStorage Tests', () {
    late TokenStorage storage;

    setUp(() {
      storage = FakeTokenStorage();
    });

    test('initially has no token', () async {
      expect(await storage.hasToken(), isFalse);
      expect(await storage.getToken(), isNull);
    });

    test('saveToken persists token and hasToken returns true', () async {
      const sampleJwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.jwt';
      await storage.saveToken(sampleJwt);

      expect(await storage.hasToken(), isTrue);
      expect(await storage.getToken(), equals(sampleJwt));
    });

    test('deleteToken clears stored token', () async {
      const sampleJwt = 'sample.token.payload';
      await storage.saveToken(sampleJwt);
      expect(await storage.hasToken(), isTrue);

      await storage.deleteToken();
      expect(await storage.hasToken(), isFalse);
      expect(await storage.getToken(), isNull);
    });
  });
}
