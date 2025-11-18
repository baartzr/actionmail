import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

/// Appends structured feedback about an action-detection result to a JSONL log.
///
/// Usage example:
/// ```sh
/// dart run tool/log_action_feedback.dart \
///   --email-id sample_party \
///   --detected-date 2025-11-22 \
///   --detected-label "Party on 22 Nov" \
///   --detected-confidence 0.62 \
///   --error-type false_positive \
///   --cause "Political party mention misclassified" \
///   --analyzed-by robin \
///   --extractor-revision 123abc
/// ```
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption(
      'log-path',
      defaultsTo: 'docs/action_detection_feedback.jsonl',
      help: 'Path to the JSONL log file.',
    )
    ..addOption(
      'email-id',
      abbr: 'e',
      help: 'Stable identifier for the email/sample.',
      mandatory: true,
    )
    ..addOption(
      'detected-date',
      help: 'Detected action date (ISO-8601).',
    )
    ..addOption(
      'detected-label',
      help: 'Detected insight/label text.',
    )
    ..addOption(
      'detected-confidence',
      help: 'Confidence score (0-1).',
    )
    ..addOption(
      'ground-truth-date',
      help: 'Expected action date (ISO-8601) or omit if none.',
    )
    ..addOption(
      'ground-truth-label',
      help: 'Expected insight/label text.',
    )
    ..addOption(
      'error-type',
      abbr: 't',
      help: 'Classification of the error (false_positive, wrong_date, etc.).',
    )
    ..addOption(
      'cause',
      abbr: 'c',
      help: 'Short free-text causation note.',
    )
    ..addOption(
      'analyzed-by',
      abbr: 'a',
      help: 'Name/initials of reviewer.',
    )
    ..addOption(
      'analyzed-at',
      help: 'Timestamp override (ISO-8601). Defaults to current UTC time.',
    )
    ..addOption(
      'extractor-revision',
      help: 'Git revision or version of the extractor.',
    );

  late ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (error) {
    stderr.writeln('Error: $error');
    stderr.writeln(parser.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  final logPath = results['log-path'] as String;
  final emailId = results['email-id'] as String;
  final detectedDate = results['detected-date'] as String?;
  final detectedLabel = results['detected-label'] as String?;
  final detectedConfidence = _parseDouble(results['detected-confidence'] as String?);
  final groundTruthDate = results['ground-truth-date'] as String?;
  final groundTruthLabel = results['ground-truth-label'] as String?;
  final errorType = results['error-type'] as String?;
  final cause = results['cause'] as String?;
  final analyzedBy = results['analyzed-by'] as String?;
  final analyzedAt = results['analyzed-at'] as String?;
  final extractorRevision = results['extractor-revision'] as String?;

  final entry = <String, dynamic>{
    'emailId': emailId,
    if (detectedDate != null ||
        detectedLabel != null ||
        detectedConfidence != null)
      'detectorOutput': {
        if (detectedDate != null) 'actionDate': detectedDate,
        if (detectedLabel != null) 'insightText': detectedLabel,
        if (detectedConfidence != null) 'confidence': detectedConfidence,
      },
    'groundTruth': (groundTruthDate == null && groundTruthLabel == null)
        ? null
        : {
            if (groundTruthDate != null) 'actionDate': groundTruthDate,
            if (groundTruthLabel != null) 'insightText': groundTruthLabel,
          },
    if (errorType != null) 'errorType': errorType,
    if (cause != null) 'causationComment': cause,
    'analyzedBy': analyzedBy ?? Platform.environment['USER'] ?? Platform.environment['USERNAME'],
    'analyzedAt': analyzedAt ?? DateTime.now().toUtc().toIso8601String(),
    if (extractorRevision != null) 'extractorRevision': extractorRevision,
  };

  final logFile = File(logPath);
  logFile.createSync(recursive: true);
  logFile.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);

  stdout.writeln('Logged feedback for "$emailId" to ${logFile.path}.');
}

double? _parseDouble(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return double.tryParse(value);
}

