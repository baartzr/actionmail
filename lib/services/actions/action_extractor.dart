import 'package:actionmail/data/models/message_index.dart';

class ActionExtractor {
  static final RegExp _numericDate = RegExp(r'\b(\d{1,2})\s*(?:\/|\-|\.)\s*(\d{1,2})(?:\s*(?:\/|\-|\.)\s*(\d{2,4}))?\b');
  static final RegExp _monthDay = RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2})\b', caseSensitive: false);
  static final RegExp _weekdayMonthDay = RegExp(r'\b(Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*\s*,?\s*(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\b', caseSensitive: false);
  static final RegExp _isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');
  static final RegExp _phrases = RegExp(r'\b(due|by|on|arrives|delivery|deliver|flight|depart|departure|arrive|meeting|appointment|deadline|payment|invoice|order|shipment)\b', caseSensitive: false);
  static final RegExp _relativeDate = RegExp(r'\b(tomorrow|today|next\s+(week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b', caseSensitive: false);

  /// Quick heuristic check on subject/snippet only (lightweight, no body download)
  /// Returns true only if both an action phrase AND a date are found (to avoid false positives)
  static bool isActionCandidate(String subject, String snippet) {
    final text = '$subject $snippet'.toLowerCase();
    final now = DateTime.now();
    
    // Exclude common non-action emails
    if (text.contains('unsubscribe') && 
        (text.contains('automatically generated') || 
         text.contains('list-unsubscribe') ||
         snippet.contains('automatically generated'))) {
      return false;
    }
    
    // Require both action phrase AND date for candidate status
    final hasActionPhrase = _phrases.hasMatch(text);
    final hasDate = _extractDate(text, now, fallbackYear: now.year) != null;
    
    return hasActionPhrase && hasDate;
  }

  /// Deep detection with full body content (higher confidence)
  /// Returns action result with confidence score (0.0-1.0)
  static ActionResult? detectWithBody(String subject, String snippet, String bodyContent) {
    final text = '$subject $snippet $bodyContent';
    final now = DateTime.now();

    DateTime? detectedDate = _extractDate(text, now, fallbackYear: now.year);
    if (detectedDate == null) {
      // Try relative dates
      detectedDate = _extractRelativeDate(text, now);
    }

    if (detectedDate == null) return null;

    // Normalize to date only (no time)
    detectedDate = DateTime(detectedDate.year, detectedDate.month, detectedDate.day);

    // Calculate confidence based on multiple signals
    double confidence = _calculateConfidence(text, detectedDate, now);

    // Extract action verb and context
    final verb = _phrases.hasMatch(text) ? _phrases.firstMatch(text)!.group(0)!.toLowerCase() : 'on';
    final monthStr = _monthName(detectedDate.month);
    final label = _buildInsight(verb, detectedDate, monthStr);

    return ActionResult(
      actionDate: detectedDate,
      confidence: confidence,
      insightText: label,
    );
  }

  /// Quick heuristic on subject/snippet only (for Phase 2 candidate filtering)
  static ActionResult? detectQuick(String subject, String snippet) {
    final text = '$subject $snippet';
    final now = DateTime.now();

    DateTime? detectedDate = _extractDate(text, now, fallbackYear: now.year);
    if (detectedDate == null) return null;

    detectedDate = DateTime(detectedDate.year, detectedDate.month, detectedDate.day);
    final verb = _phrases.hasMatch(text) ? _phrases.firstMatch(text)!.group(0)!.toLowerCase() : 'on';
    final monthStr = _monthName(detectedDate.month);
    final label = _buildInsight(verb, detectedDate, monthStr);

    // Lower confidence for quick detection (subject/snippet only)
    return ActionResult(
      actionDate: detectedDate,
      confidence: 0.5,
      insightText: label,
    );
  }

  static DateTime? _extractRelativeDate(String text, DateTime now) {
    final match = _relativeDate.firstMatch(text.toLowerCase());
    if (match == null) return null;

    final phrase = match.group(0)!;
    if (phrase.contains('tomorrow')) {
      return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    }
    if (phrase.contains('today')) {
      return DateTime(now.year, now.month, now.day);
    }
    if (phrase.contains('next week')) {
      return DateTime(now.year, now.month, now.day).add(const Duration(days: 7));
    }
    if (phrase.contains('next month')) {
      final nextMonth = now.month == 12 ? DateTime(now.year + 1, 1, now.day) : DateTime(now.year, now.month + 1, now.day);
      return nextMonth;
    }
    // Next weekday (e.g., "next Monday")
    final weekdayMatch = RegExp(r'next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)', caseSensitive: false).firstMatch(phrase);
    if (weekdayMatch != null) {
      final weekday = _weekdayFromName(weekdayMatch.group(1)!);
      if (weekday != null) {
        var date = DateTime(now.year, now.month, now.day);
        while (date.weekday != weekday) {
          date = date.add(const Duration(days: 1));
        }
        return date;
      }
    }
    return null;
  }

  static int? _weekdayFromName(String name) {
    final n = name.toLowerCase();
    const map = {
      'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
      'friday': 5, 'saturday': 6, 'sunday': 7,
    };
    return map[n];
  }

  static double _calculateConfidence(String text, DateTime date, DateTime now) {
    double confidence = 0.5; // Base confidence

    // Higher confidence if action phrase found
    if (_phrases.hasMatch(text)) confidence += 0.2;

    // Higher confidence for ISO dates (more structured)
    if (_isoDate.hasMatch(text)) confidence += 0.1;

    // Higher confidence if date is in the future (likely an action)
    if (date.isAfter(now)) confidence += 0.1;

    // Higher confidence for specific contexts
    final lowerText = text.toLowerCase();
    if (lowerText.contains('invoice') || lowerText.contains('payment') || lowerText.contains('due')) confidence += 0.1;
    if (lowerText.contains('meeting') || lowerText.contains('appointment') || lowerText.contains('calendar')) confidence += 0.1;
    if (lowerText.contains('delivery') || lowerText.contains('shipment')) confidence += 0.05;

    return confidence.clamp(0.0, 1.0);
  }

  static String _buildInsight(String verb, DateTime date, String monthStr) {
    final day = date.day;
    switch (verb) {
      case 'due':
      case 'by':
        return 'Possible action date: $day $monthStr (due).';
      case 'arrives':
      case 'delivery':
      case 'deliver':
        return 'Possible action date: $day $monthStr (delivery).';
      case 'flight':
      case 'depart':
      case 'departure':
      case 'arrive':
        return 'Possible action date: $day $monthStr (flight).';
      default:
        return 'Possible action date: $day $monthStr.';
    }
  }

  static DateTime? _extractDate(String text, DateTime now, {required int fallbackYear}) {
    // 1) ISO date: YYYY-MM-DD (highest priority for structured data)
    final isoMatch = _isoDate.firstMatch(text);
    if (isoMatch != null) {
      final year = int.tryParse(isoMatch.group(1)!);
      final month = int.tryParse(isoMatch.group(2)!);
      final day = int.tryParse(isoMatch.group(3)!);
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }

    // 2) Weekday, DD Mon
    final wmd = _weekdayMonthDay.firstMatch(text);
    if (wmd != null) {
      final day = int.tryParse(wmd.group(2)!);
      final month = _monthFromName(wmd.group(3)!);
      if (day != null && month != null) {
        return _resolveYear(day, month, now, fallbackYear);
      }
    }

    // 3) Mon DD
    final md = _monthDay.firstMatch(text);
    if (md != null) {
      final day = int.tryParse(md.group(2)!);
      final month = _monthFromName(md.group(1)!);
      if (day != null && month != null) {
        return _resolveYear(day, month, now, fallbackYear);
      }
    }

    // 4) Numeric MM/DD[/YYYY]
    final nd = _numericDate.firstMatch(text);
    if (nd != null) {
      final m = int.tryParse(nd.group(1)!);
      final d = int.tryParse(nd.group(2)!);
      final y = nd.group(3) != null ? int.tryParse(nd.group(3)!) : null;
      if (m != null && d != null) {
        final year = y ?? _inferYear(m, d, now, fallbackYear);
        return DateTime(year, m, d);
      }
    }

    return null;
  }

  static int _inferYear(int month, int day, DateTime now, int fallbackYear) {
    // If date already passed this year by > 6 months, assume next year; else current
    final candidate = DateTime(fallbackYear, month, day);
    if (candidate.isBefore(now) && now.difference(candidate).inDays > 183) {
      return fallbackYear + 1;
    }
    return fallbackYear;
  }

  static DateTime _resolveYear(int day, int month, DateTime now, int fallbackYear) {
    return DateTime(_inferYear(month, day, now, fallbackYear), month, day);
  }

  static int? _monthFromName(String name) {
    final n = name.substring(0, 3).toLowerCase();
    const map = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    return map[n];
  }

  static String _monthName(int month) {
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return names[month - 1];
  }
}

/// Result of action detection with confidence score
class ActionResult {
  final DateTime actionDate;
  final double confidence;
  final String insightText;

  ActionResult({
    required this.actionDate,
    required this.confidence,
    required this.insightText,
  });
}


