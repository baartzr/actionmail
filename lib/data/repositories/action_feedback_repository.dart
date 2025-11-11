import 'package:domail/data/db/app_database.dart';
import 'package:domail/services/actions/ml_action_extractor.dart';
import 'package:domail/services/actions/action_extractor.dart';
import 'package:sqflite/sqflite.dart';

/// Repository for storing and retrieving action extraction feedback
class ActionFeedbackRepository {
  final AppDatabase _dbProvider = AppDatabase();

  /// Store feedback about action extraction results
  Future<void> storeFeedback(ActionFeedback feedback) async {
    final db = await _dbProvider.database;
    
    await db.insert(
      'action_feedback',
      {
        'messageId': feedback.messageId,
        'subject': feedback.subject,
        'snippet': feedback.snippet,
        'bodyContent': feedback.bodyContent,
        'detectedActionDate': feedback.detectedResult?.actionDate.millisecondsSinceEpoch,
        'detectedActionConfidence': feedback.detectedResult?.confidence,
        'detectedActionText': feedback.detectedResult?.insightText,
        'userActionDate': feedback.userCorrectedResult?.actionDate.millisecondsSinceEpoch,
        'userActionConfidence': feedback.userCorrectedResult?.confidence,
        'userActionText': feedback.userCorrectedResult?.insightText,
        'feedbackType': feedback.feedbackType.name,
        'timestamp': feedback.timestamp.millisecondsSinceEpoch,
      },
    );
  }

  /// Get all feedback entries for export
  Future<List<ActionFeedback>> getAllFeedback() async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'action_feedback',
      orderBy: 'timestamp DESC',
    );

    return rows.map((row) {
      return ActionFeedback(
        messageId: row['messageId'] as String,
        subject: row['subject'] as String,
        snippet: row['snippet'] as String,
        bodyContent: row['bodyContent'] as String?,
        detectedResult: _buildActionResult(
          row['detectedActionDate'] as int?,
          row['detectedActionConfidence'] as double?,
          row['detectedActionText'] as String?,
        ),
        userCorrectedResult: _buildActionResult(
          row['userActionDate'] as int?,
          row['userActionConfidence'] as double?,
          row['userActionText'] as String?,
        ),
        feedbackType: FeedbackType.values.firstWhere(
          (e) => e.name == row['feedbackType'] as String,
          orElse: () => FeedbackType.correction,
        ),
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      );
    }).toList();
  }

  /// Export all feedback as JSON (for model training)
  Future<Map<String, dynamic>> exportFeedbackAsJson() async {
    final feedbacks = await getAllFeedback();
    return {
      'version': '1.0',
      'timestamp': DateTime.now().toIso8601String(),
      'feedbackCount': feedbacks.length,
      'feedbacks': feedbacks.map((f) => f.toJson()).toList(),
    };
  }

  /// Delete feedback entries (after export)
  Future<void> deleteFeedback(List<int> ids) async {
    final db = await _dbProvider.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'action_feedback',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Get count of feedback entries
  Future<int> getFeedbackCount() async {
    final db = await _dbProvider.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM action_feedback');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Helper to build ActionResult from database row
  ActionResult? _buildActionResult(int? dateMs, double? confidence, String? text) {
    if (dateMs == null && text == null) return null;
    
    return ActionResult(
      actionDate: dateMs != null 
          ? DateTime.fromMillisecondsSinceEpoch(dateMs)
          : DateTime.now(), // Fallback - shouldn't happen
      confidence: confidence ?? 0.0,
      insightText: text ?? '',
    );
  }
}

