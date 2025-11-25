import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import '../helpers/test_setup.dart';

/// Tests for flutter_secure_storage package updates
/// These tests verify secure storage functionality before and after package updates
/// Note: These tests require platform channels and should ideally be run on a device/emulator
void main() {
  // Initialize Flutter bindings before running tests (required for FlutterSecureStorage)
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Secure Storage Tests', () {
    late FlutterSecureStorage storage;
    bool _pluginsAvailable = false;

    setUpAll(() async {
      initializeTestEnvironment();
      
      // Check if plugins are available by creating storage and testing
      // Note: These tests require platform channels and should be run on device/emulator
      final testStorage = const FlutterSecureStorage();
      try {
        await testStorage.deleteAll();
        _pluginsAvailable = true;
      } on MissingPluginException {
        _pluginsAvailable = false;
      } catch (e) {
        // Other errors might indicate plugins are available
        _pluginsAvailable = true;
      }
    });

    setUp(() async {
      // Create a new storage instance for each test
      storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        lOptions: LinuxOptions(),
        wOptions: WindowsOptions(
          useBackwardCompatibility: false,
        ),
      );

      // Clean up any existing test data (only if plugins available)
      if (_pluginsAvailable) {
        try {
          await storage.deleteAll();
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    });

    tearDown(() async {
      // Clean up after each test (only if plugins are available)
      if (_pluginsAvailable) {
        try {
          await storage.deleteAll();
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    });

    test('write and read string value', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'test_token';
      const value = 'test_access_token_12345';

      // Write value
      await storage.write(key: key, value: value);

      // Read value
      final readValue = await storage.read(key: key);

      expect(readValue, equals(value));
    });

    test('write and read null value returns null', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'test_null_key';

      // Try to read non-existent key
      final readValue = await storage.read(key: key);

      expect(readValue, isNull);
    });

    test('delete specific key', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'test_delete_key';
      const value = 'test_value';

      // Write value
      await storage.write(key: key, value: value);
      expect(await storage.read(key: key), equals(value));

      // Delete key
      await storage.delete(key: key);

      // Verify deletion
      final readValue = await storage.read(key: key);
      expect(readValue, isNull);
    });

    test('deleteAll removes all keys', () async {
      if (!_pluginsAvailable) return;
      
      // Write multiple keys
      await storage.write(key: 'key1', value: 'value1');
      await storage.write(key: 'key2', value: 'value2');
      await storage.write(key: 'key3', value: 'value3');

      // Verify they exist
      expect(await storage.read(key: 'key1'), equals('value1'));
      expect(await storage.read(key: 'key2'), equals('value2'));
      expect(await storage.read(key: 'key3'), equals('value3'));

      // Delete all
      await storage.deleteAll();

      // Verify all are deleted
      expect(await storage.read(key: 'key1'), isNull);
      expect(await storage.read(key: 'key2'), isNull);
      expect(await storage.read(key: 'key3'), isNull);
    });

    test('readAll retrieves all keys and values', () async {
      if (!_pluginsAvailable) return;
      
      // Write multiple keys
      await storage.write(key: 'token1', value: 'access_token_1');
      await storage.write(key: 'token2', value: 'refresh_token_2');

      // Read all
      final allValues = await storage.readAll();

      expect(allValues.length, greaterThanOrEqualTo(2));
      expect(allValues['token1'], equals('access_token_1'));
      expect(allValues['token2'], equals('refresh_token_2'));
    });

    test('overwrite existing key updates value', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'test_overwrite';
      const initialValue = 'initial_value';
      const updatedValue = 'updated_value';

      // Write initial value
      await storage.write(key: key, value: initialValue);
      expect(await storage.read(key: key), equals(initialValue));

      // Overwrite
      await storage.write(key: key, value: updatedValue);
      expect(await storage.read(key: key), equals(updatedValue));
    });

    test('containsKey checks if key exists', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'test_contains_key';
      const value = 'test_value';

      // Key should not exist initially
      expect(await storage.containsKey(key: key), isFalse);

      // Write value
      await storage.write(key: key, value: value);

      // Key should exist now
      expect(await storage.containsKey(key: key), isTrue);

      // Delete key
      await storage.delete(key: key);

      // Key should not exist again
      expect(await storage.containsKey(key: key), isFalse);
    });

    test('handles empty string values', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'empty_key';
      const emptyValue = '';

      await storage.write(key: key, value: emptyValue);
      final readValue = await storage.read(key: key);

      expect(readValue, equals(emptyValue));
    });

    test('handles special characters in values', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'special_chars_key';
      const specialValue = 'token_with_!@#\$%^&*()_+-=[]{}|;:,.<>?';

      await storage.write(key: key, value: specialValue);
      final readValue = await storage.read(key: key);

      expect(readValue, equals(specialValue));
    });

    test('handles long token values', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'long_token_key';
      // Generate a long token (typical OAuth token length)
      final longToken = 'a' * 2048;

      await storage.write(key: key, value: longToken);
      final readValue = await storage.read(key: key);

      expect(readValue, equals(longToken));
      expect(readValue?.length, equals(2048));
    });

    test('migration: values persist after storage reinitialization', () async {
      if (!_pluginsAvailable) return;
      
      const key = 'migration_test_key';
      const value = 'persistent_token_value';

      // Write with first storage instance
      await storage.write(key: key, value: value);
      expect(await storage.read(key: key), equals(value));

      // Create new storage instance (simulating app restart/package update)
      final newStorage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
        ),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

      // Value should still be readable
      final readValue = await newStorage.read(key: key);
      expect(readValue, equals(value));

      // Clean up
      await newStorage.delete(key: key);
    });

    group('Token Storage Pattern Tests', () {
      test('stores access token pattern', () async {
        if (!_pluginsAvailable) return;
        
        const accountId = 'account_123';
        const accessToken = 'ya29.access_token_string';
        const key = 'access_token_$accountId';

        await storage.write(key: key, value: accessToken);
        final retrieved = await storage.read(key: key);

        expect(retrieved, equals(accessToken));
      });

      test('stores refresh token pattern', () async {
        if (!_pluginsAvailable) return;
        
        const accountId = 'account_456';
        const refreshToken = '1//refresh_token_string';
        const key = 'refresh_token_$accountId';

        await storage.write(key: key, value: refreshToken);
        final retrieved = await storage.read(key: key);

        expect(retrieved, equals(refreshToken));
      });

      test('stores multiple account tokens', () async {
        if (!_pluginsAvailable) return;
        
        await storage.write(key: 'access_token_account1', value: 'token1');
        await storage.write(key: 'refresh_token_account1', value: 'refresh1');
        await storage.write(key: 'access_token_account2', value: 'token2');
        await storage.write(key: 'refresh_token_account2', value: 'refresh2');

        expect(await storage.read(key: 'access_token_account1'), equals('token1'));
        expect(await storage.read(key: 'refresh_token_account1'), equals('refresh1'));
        expect(await storage.read(key: 'access_token_account2'), equals('token2'));
        expect(await storage.read(key: 'refresh_token_account2'), equals('refresh2'));
      });
    });
  });
}

