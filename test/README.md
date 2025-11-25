# Testing Package

Comprehensive testing infrastructure for the ActionMail application.

## Structure

```
test/
├── README.md (this file)
├── helpers/
│   ├── test_setup.dart          # Test environment initialization
│   ├── mock_factories.dart      # Factory methods for creating test data
│   ├── mock_providers.dart      # Mock provider overrides
│   └── database_test_helper.dart # Database testing utilities
├── unit/
│   └── services/
│       ├── action_extractor_test.dart
│       └── sms_message_converter_test.dart
├── widget/
│   └── email_tile_test.dart
├── integration/
│   ├── email_sync_test.dart
│   ├── secure_storage_test.dart      # Week 1: Secure storage package update tests
│   └── firebase_sync_test.dart       # Week 1: Firebase/Firestore package update tests
└── widget_test.dart (existing)
```

## Running Tests

### All Tests
```bash
flutter test
```

### Specific Test File
```bash
flutter test test/unit/services/action_extractor_test.dart
```

### Verbose Output
```bash
flutter test --verbose
```

### With Coverage
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Test Helpers

### Test Setup

Use `initializeTestEnvironment()` at the start of tests that need database access:

```dart
void main() {
  setUpAll(() {
    initializeTestEnvironment();
  });
}
```

### Mock Factories

Create test data easily:

```dart
final account = MockFactory.createMockAccount(
  email: 'test@example.com',
);

final message = MockFactory.createMockMessage(
  subject: 'Test Email',
  accountId: account.id,
);

final smsMessage = MockFactory.createMockSmsMessage(
  phoneNumber: '+1234567890',
  messageText: 'Hello!',
);
```

### Provider Overrides

Create test provider scopes with overrides:

```dart
await tester.pumpWidget(
  createTestProviderScope(
    child: MyWidget(),
    overrides: TestProviderOverrides.withMockMessages(
      messages: [message1, message2],
    ),
  ),
);
```

### Database Helpers

Use in-memory databases for fast tests:

```dart
setUp(() async {
  await DatabaseTestHelper.getTestDatabase();
});

tearDown(() async {
  await DatabaseTestHelper.clearTestDatabase();
});
```

## Writing Tests

### Unit Tests

Test individual functions and classes in isolation:

```dart
test('functionName - does expected thing', () {
  // Arrange
  final input = 'test';
  
  // Act
  final result = functionToTest(input);
  
  // Assert
  expect(result, expectedValue);
});
```

### Widget Tests

Test UI components:

```dart
testWidgets('WidgetName - displays correctly', (tester) async {
  await tester.pumpWidget(
    createTestProviderScope(
      child: MyWidget(),
    ),
  );
  
  expect(find.text('Expected Text'), findsOneWidget);
});
```

### Integration Tests

Test multiple components working together:

```dart
test('feature - works end-to-end', () async {
  // Setup
  final repository = MessageRepository();
  
  // Execute
  await repository.upsertMessages([message]);
  
  // Verify
  final saved = await repository.getAll(accountId);
  expect(saved.length, 1);
});
```

## Best Practices

1. **Use descriptive test names**: `functionName_scenario_expectedBehavior`
2. **One assertion per test** (when possible)
3. **Arrange-Act-Assert pattern**
4. **Use setUp/tearDown** for common setup/cleanup
5. **Mock external dependencies** (database, network, etc.)
6. **Test edge cases** (null, empty, invalid input)
7. **Keep tests fast** (use in-memory databases, mocks)

## Test Coverage Goals

- **Unit tests**: 80%+ coverage for services and utilities
- **Widget tests**: All reusable widgets
- **Integration tests**: Critical user flows

## Running Specific Test Suites

```bash
# Unit tests only
flutter test test/unit/

# Widget tests only
flutter test test/widget/

# Integration tests only
flutter test test/integration/
```

## CI/CD Integration

Add to your CI pipeline:

```yaml
# .github/workflows/test.yml
- name: Run tests
  run: flutter test --coverage
  
- name: Upload coverage
  uses: codecov/codecov-action@v3
```

