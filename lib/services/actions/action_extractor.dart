import 'package:actionmail/data/models/message_index.dart';

class ActionExtractor {
  static final RegExp _numericDate = RegExp(r'\b(\d{1,2})\s*(?:\/|\-|\.)\s*(\d{1,2})(?:\s*(?:\/|\-|\.)\s*(\d{2,4}))?\b');
  static final RegExp _monthDay = RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2})\b', caseSensitive: false);
  static final RegExp _weekdayMonthDay = RegExp(r'\b(Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*\s*,?\s*(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\b', caseSensitive: false);
  static final RegExp _phrases = RegExp(r'\b(due|by|on|arrives|delivery|deliver|flight|depart|departure|arrive)\b', caseSensitive: false);

  static List<MessageIndex> enrich(List<MessageIndex> messages) {
    return messages.map(_enrichOne).toList();
  }

  static MessageIndex _enrichOne(MessageIndex m) {
    final text = '${m.subject} ${m.snippet ?? ''}';
    final now = DateTime.now();

    DateTime? detectedDate = _extractDate(text, now, fallbackYear: now.year);
    if (detectedDate == null) return m;

    // Ensure time component normalized
    detectedDate = DateTime(detectedDate.year, detectedDate.month, detectedDate.day);

    final verb = _phrases.hasMatch(text) ? _phrases.firstMatch(text)!.group(0)!.toLowerCase() : 'on';
    final monthStr = _monthName(detectedDate.month);
    final label = _buildInsight(verb, detectedDate, monthStr);

    return m.copyWith(
      actionDate: detectedDate,
      actionConfidence: 0.7,
      actionInsightText: label,
    );
  }

  static String _buildInsight(String verb, DateTime date, String monthStr) {
    final day = date.day;
    switch (verb) {
      case 'due':
      case 'by':
        return 'It looks like this is due on $day $monthStr.';
      case 'arrives':
      case 'delivery':
      case 'deliver':
        return 'It looks like your package arrives on $day $monthStr.';
      case 'flight':
      case 'depart':
      case 'departure':
      case 'arrive':
        return 'It looks like your flight is on $day $monthStr.';
      default:
        return 'It looks like the date is $day $monthStr.';
    }
  }

  static DateTime? _extractDate(String text, DateTime now, {required int fallbackYear}) {
    // 1) Weekday, DD Mon
    final wmd = _weekdayMonthDay.firstMatch(text);
    if (wmd != null) {
      final day = int.tryParse(wmd.group(2)!);
      final month = _monthFromName(wmd.group(3)!);
      if (day != null && month != null) {
        return _resolveYear(day, month, now, fallbackYear);
      }
    }

    // 2) Mon DD
    final md = _monthDay.firstMatch(text);
    if (md != null) {
      final day = int.tryParse(md.group(2)!);
      final month = _monthFromName(md.group(1)!);
      if (day != null && month != null) {
        return _resolveYear(day, month, now, fallbackYear);
      }
    }

    // 3) Numeric MM/DD[/YYYY]
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


