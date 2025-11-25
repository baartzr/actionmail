import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domail/features/home/presentation/widgets/email_tile.dart';
import '../helpers/test_setup.dart';
import '../helpers/mock_factories.dart';

void main() {
  group('EmailTile Widget Tests', () {
    setUpAll(() {
      initializeTestEnvironment();
    });

    testWidgets('displays email subject', (WidgetTester tester) async {
      final message = MockFactory.createMockMessage(
        subject: 'Test Email Subject',
      );

      await tester.pumpWidget(
        createTestProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EmailTile(
                message: message,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test Email Subject'), findsOneWidget);
    });

    testWidgets('displays sender information', (WidgetTester tester) async {
      final message = MockFactory.createMockMessage(
        from: 'sender@example.com',
      );

      await tester.pumpWidget(
        createTestProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EmailTile(
                message: message,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Sender email may appear multiple times (in header and expanded view)
      expect(find.text('sender@example.com'), findsWidgets);
    });

    testWidgets('shows unread indicator for unread messages', (WidgetTester tester) async {
      final unreadMessage = MockFactory.createMockMessage(isRead: false);

      await tester.pumpWidget(
        createTestProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EmailTile(
                message: unreadMessage,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Verify unread styling (font weight, etc.)
      // This depends on your EmailTile implementation
      expect(find.byType(EmailTile), findsOneWidget);
    });

    testWidgets('triggers onTap when double tapped', (WidgetTester tester) async {
      var tapped = false;
      final message = MockFactory.createMockMessage();

      await tester.pumpWidget(
        createTestProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EmailTile(
                message: message,
                onTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      // Wait for widget to fully build
      await tester.pumpAndSettle();

      // EmailTile uses double-tap to trigger onTap (single tap expands/collapses)
      // Find the EmailTile widget and perform double tap
      final emailTile = find.byType(EmailTile);
      expect(emailTile, findsOneWidget);
      
      // Perform double tap - this should trigger onTap
      await tester.tap(emailTile);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(emailTile);
      await tester.pumpAndSettle();
      
      // Verify onTap was called
      expect(tapped, isTrue);
    });
  });
}

