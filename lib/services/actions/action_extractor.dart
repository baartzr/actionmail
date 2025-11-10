import 'dart:math' as math;

class ActionExtractor {
  static final RegExp _numericDate = RegExp(r'\b(\d{1,2})\s*(?:\/|\-|\.)\s*(\d{1,2})(?:\s*(?:\/|\-|\.)\s*(\d{2,4}))?\b');
  static final RegExp _monthDay = RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2})\b', caseSensitive: false);
  static final RegExp _weekdayMonthDay = RegExp(r'\b(Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*\s*,?\s*(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\b', caseSensitive: false);
  static final RegExp _isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');
  static final RegExp _phrases = RegExp(r'\b(due|by|on|arrives|delivery|deliver|flight|depart|departure|arrive|meeting|appointment|deadline|payment|invoice|order|shipment|party|event|birthday|gathering|celebration|wedding|dinner|lunch|breakfast|conference|call|webinar|seminar|join|live|attend|watch|show|stream|broadcast|session|workshop|training|class|lesson)\b', caseSensitive: false);
  static final RegExp _relativeDate = RegExp(r'\b(tomorrow|today|next\s+(week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|new\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b', caseSensitive: false);

  /// Quick heuristic check on subject/snippet only (lightweight, no body download)
  /// Returns true if action phrase is found (date extraction happens later in body for better accuracy)
  static bool isActionCandidate(String subject, String snippet) {
    final text = '$subject $snippet'.toLowerCase();
    
    // Exclude common non-action emails
    if (text.contains('unsubscribe') && 
        (text.contains('automatically generated') || 
         text.contains('list-unsubscribe') ||
         snippet.contains('automatically generated'))) {
      return false;
    }
    
    // Check for action phrase - if found, consider it a candidate
    // Date extraction will happen in the body for more accurate detection
    final hasActionPhrase = _phrases.hasMatch(text);
    
    // Also check for time mentions (e.g., "6 p.m.", "at 3pm") which might indicate events happening today
    final hasTime = RegExp(r'\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?|am|pm)\b', caseSensitive: false).hasMatch(text);
    
    // If we have an action phrase, it's a candidate (even without explicit date)
    // The body content will be checked for dates during deep detection
    if (hasActionPhrase) {
      // If there's also a time mention, it's likely happening today/soon
      if (hasTime) {
        return true;
      }
      // Also check for relative dates or explicit dates
      final now = DateTime.now();
      DateTime? date = _extractDate(text, now, fallbackYear: now.year) ?? _extractRelativeDate(text, now);
      if (date != null) {
        return true;
      }
      // For action phrases like "join", "live", "attend", "watch" without explicit date,
      // still consider it a candidate - the body might have the date
      final eventPhrases = RegExp(r'\b(join|live|attend|watch|show|stream|broadcast|session|workshop|training|class|lesson)\b', caseSensitive: false);
      if (eventPhrases.hasMatch(text)) {
        return true;
      }
    }
    
    return false;
  }

  /// Deep detection with full body content (higher confidence)
  /// Returns action result with confidence score (0.0-1.0)
  static ActionResult? detectWithBody(String subject, String snippet, String bodyContent) {
    final text = '$subject $snippet $bodyContent';
    final now = DateTime.now();

    // Check relative dates FIRST (they're more explicit and should take priority)
    // Only fall back to numeric/extracted dates if no relative date is found
    DateTime? detectedDate = _extractRelativeDate(text, now) ?? _extractDate(text, now, fallbackYear: now.year);
    
    // If no date found but there's a time mention (e.g., "6 p.m.", "at 3pm"), assume today
    if (detectedDate == null) {
      final hasTime = RegExp(r'\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?|am|pm)\b', caseSensitive: false).hasMatch(text);
      if (hasTime && _phrases.hasMatch(text)) {
        // Time mentions with action phrases likely mean "today"
        detectedDate = DateTime(now.year, now.month, now.day);
      }
    }

    if (detectedDate == null) return null;

    // Normalize to date only (no time)
    detectedDate = DateTime(detectedDate.year, detectedDate.month, detectedDate.day);

    // Calculate confidence based on multiple signals
    double confidence = _calculateConfidence(text, detectedDate, now);

    // Extract action verb and context
    final verb = _phrases.hasMatch(text) ? _phrases.firstMatch(text)!.group(0)!.toLowerCase() : 'on';
    final monthStr = _monthName(detectedDate.month);
    final label = _buildInsight(verb, detectedDate, monthStr, text);

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

    // Check relative dates FIRST (they're more explicit and should take priority)
    // Only fall back to numeric/extracted dates if no relative date is found
    DateTime? detectedDate = _extractRelativeDate(text, now) ?? _extractDate(text, now, fallbackYear: now.year);
    
    // If no date found but there's a time mention (e.g., "6 p.m.", "at 3pm"), assume today
    if (detectedDate == null) {
      final hasTime = RegExp(r'\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?|am|pm)\b', caseSensitive: false).hasMatch(text);
      if (hasTime && _phrases.hasMatch(text)) {
        // Time mentions with action phrases likely mean "today"
        detectedDate = DateTime(now.year, now.month, now.day);
      }
    }
    
    if (detectedDate == null) return null;

    detectedDate = DateTime(detectedDate.year, detectedDate.month, detectedDate.day);
    final verb = _phrases.hasMatch(text) ? _phrases.firstMatch(text)!.group(0)!.toLowerCase() : 'on';
    final monthStr = _monthName(detectedDate.month);
    final label = _buildInsight(verb, detectedDate, monthStr, text);

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
    // Next weekday (e.g., "next Monday" or "new Wednesday" - typo handling)
    final weekdayMatch = RegExp(r'(?:next|new)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)', caseSensitive: false).firstMatch(phrase);
    if (weekdayMatch != null) {
      final weekday = _weekdayFromName(weekdayMatch.group(1)!);
      if (weekday != null) {
        var date = DateTime(now.year, now.month, now.day);
        // Find the next occurrence of this weekday (add at least 1 day to ensure it's "next")
        date = date.add(const Duration(days: 1));
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

  static String? _buildInsight(String verb, DateTime date, String monthStr, String text) {
    final day = date.day;
    final lowerText = text.toLowerCase();
    
    // Try to extract event context from the text
    String? eventContext;
    
    // Check for specific event types
    if (lowerText.contains('party') || lowerText.contains('birthday') || lowerText.contains('celebration')) {
      eventContext = 'party';
    } else if (lowerText.contains('meeting')) {
      eventContext = 'meeting';
    } else if (lowerText.contains('appointment')) {
      eventContext = 'appointment';
    } else if (lowerText.contains('conference') || lowerText.contains('webinar') || lowerText.contains('seminar')) {
      eventContext = 'conference';
    } else if (lowerText.contains('dinner') || lowerText.contains('lunch') || lowerText.contains('breakfast')) {
      eventContext = lowerText.contains('dinner') ? 'dinner' : (lowerText.contains('lunch') ? 'lunch' : 'breakfast');
    } else if (lowerText.contains('wedding')) {
      eventContext = 'wedding';
    } else if (lowerText.contains('event') || lowerText.contains('gathering')) {
      eventContext = 'event';
    } else if (lowerText.contains('flight') || lowerText.contains('departure') || lowerText.contains('arrival')) {
      eventContext = 'flight';
    } else if (lowerText.contains('delivery') || lowerText.contains('arrives') || lowerText.contains('shipment')) {
      eventContext = 'delivery';
    } else if (lowerText.contains('invoice') || lowerText.contains('payment') || lowerText.contains('due')) {
      eventContext = 'payment due';
    } else if (lowerText.contains('deadline')) {
      eventContext = 'deadline';
    } else if (lowerText.contains('call')) {
      eventContext = 'call';
    }
    
    // Build descriptive text with event context if found
    if (eventContext != null) {
      // Capitalize first letter
      final capitalized = eventContext[0].toUpperCase() + eventContext.substring(1);
      return '$capitalized on $day $monthStr.';
    }
    
    // Fallback to verb-based descriptions if no event context
    switch (verb) {
      case 'due':
      case 'by':
        return 'Due by $day $monthStr.';
      case 'arrives':
      case 'delivery':
      case 'deliver':
        return 'Delivery on $day $monthStr.';
      case 'flight':
      case 'depart':
      case 'departure':
      case 'arrive':
        return 'Flight on $day $monthStr.';
      default:
        return null;
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

    // 4) Numeric MM/DD[/YYYY] - but skip if it looks like a URL, code, or version number
    final nd = _numericDate.firstMatch(text);
    if (nd != null) {
      final matchStart = nd.start;
      final matchEnd = nd.end;
      // Check context - if surrounded by URL-like characters, skip it
      if (matchStart > 0 && matchEnd < text.length) {
        final before = text.substring(math.max(0, matchStart - 3), matchStart);
        final after = text.substring(matchEnd, math.min(text.length, matchEnd + 3));
        // Skip if it's part of a URL (http, www, .com, etc.) or code (contains letters before/after)
        if (before.toLowerCase().contains('http') || 
            before.toLowerCase().contains('www') ||
            after.toLowerCase().contains('.com') ||
            after.toLowerCase().contains('.org') ||
            RegExp(r'[a-z]', caseSensitive: false).hasMatch(before) && RegExp(r'[a-z]', caseSensitive: false).hasMatch(after)) {
          // Skip this match, continue to next check
        } else {
          final m = int.tryParse(nd.group(1)!);
          final d = int.tryParse(nd.group(2)!);
          final y = nd.group(3) != null ? int.tryParse(nd.group(3)!) : null;
          if (m != null && d != null && m <= 12 && d <= 31) {
            final year = y ?? _inferYear(m, d, now, fallbackYear);
            return DateTime(year, m, d);
          }
        }
      } else {
        // No context to check, proceed normally
        final m = int.tryParse(nd.group(1)!);
        final d = int.tryParse(nd.group(2)!);
        final y = nd.group(3) != null ? int.tryParse(nd.group(3)!) : null;
        if (m != null && d != null && m <= 12 && d <= 31) {
          final year = y ?? _inferYear(m, d, now, fallbackYear);
          return DateTime(year, m, d);
        }
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
  final String? insightText;

  ActionResult({
    required this.actionDate,
    required this.confidence,
    required this.insightText,
  });
}


