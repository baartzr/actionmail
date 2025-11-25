import 'package:flutter_test/flutter_test.dart';
import 'package:domail/services/actions/action_extractor.dart';

void main() {
  group('ActionExtractor', () {
    test('detectQuick - detects meeting action', () {
      final subject = 'Meeting tomorrow at 3pm';
      final snippet = 'We need to discuss the project';
      
      final result = ActionExtractor.detectQuick(subject, snippet);
      
      expect(result, isNotNull);
      final insightText = result!.insightText;
      expect(insightText, isNotNull);
      expect(insightText!.toLowerCase(), contains('meeting'));
      expect(result.actionDate, isNotNull);
    });

    test('detectQuick - detects deadline action', () {
      final subject = 'Due: Friday by 5pm';
      final snippet = 'Please submit your report';
      
      final result = ActionExtractor.detectQuick(subject, snippet);
      
      expect(result, isNotNull);
      expect(result!.insightText?.toLowerCase() ?? '', anyOf(
        contains('due'),
        contains('deadline'),
        contains('submit'),
      ));
    });

    test('detectQuick - returns null for non-action emails', () {
      final subject = 'Newsletter update';
      final snippet = 'Check out our latest deals';
      
      final result = ActionExtractor.detectQuick(subject, snippet);
      
      expect(result, isNull);
    });

    test('isActionCandidate - identifies candidates correctly', () {
      expect(
        ActionExtractor.isActionCandidate('Meeting tomorrow', 'Discuss project'),
        isTrue,
      );
      
      expect(
        ActionExtractor.isActionCandidate('Newsletter', 'Latest deals'),
        isFalse,
      );
    });

    test('detectWithBody - extracts date from body content', () {
      final subject = 'Important meeting';
      final snippet = 'We need to meet';
      // Use an explicit future date that won't be misinterpreted
      // Use ISO format which is more reliable for year parsing
      final now = DateTime.now();
      final testDate = DateTime(now.year + 2, 6, 15); // June 15, 2 years from now
      final body = 'Let\'s schedule a meeting on ${testDate.year}-${testDate.month.toString().padLeft(2, '0')}-${testDate.day.toString().padLeft(2, '0')} at 2pm';
      
      final result = ActionExtractor.detectWithBody(subject, snippet, body);
      
      expect(result, isNotNull);
      expect(result!.actionDate, isNotNull);
      // Verify date is parsed correctly (allow for some year inference tolerance)
      final date = result.actionDate;
      // The parser should extract the explicit year from ISO format
      expect(date.year, testDate.year);
      expect(date.month, testDate.month);
      expect(date.day, testDate.day);
    });
  });
}

