import 'package:domail/services/actions/action_extractor.dart';
import 'package:domail/data/repositories/action_feedback_repository.dart';
import 'package:flutter/foundation.dart';

/// ML-enhanced action extractor using hybrid rule-based + ML approach
/// Phase 1: Infrastructure for model loading and hybrid architecture
class MLActionExtractor {
  static bool _mlModelAvailable = false;
  static bool _mlInitialized = false;

  /// Initialize ML model (if available)
  /// Returns true if ML model was successfully loaded
  static Future<bool> initialize() async {
    if (_mlInitialized) return _mlModelAvailable;

    try {
      // Phase 1: Model loading infrastructure
      // For now, ML model is not available - this is a placeholder
      // Future: Load TFLite model (mobile) or ONNX model (desktop)
      
      // TODO: Implement actual model loading
      // - Check for model file existence
      // - Load TFLite/ONNX model
      // - Initialize interpreter/runtime
      
      _mlModelAvailable = false; // Set to true once model is available
      _mlInitialized = true;
      
      debugPrint('[MLActionExtractor] Initialized (ML model available: $_mlModelAvailable)');
      return _mlModelAvailable;
    } catch (e) {
      debugPrint('[MLActionExtractor] Error initializing: $e');
      _mlInitialized = true;
      _mlModelAvailable = false;
      return false;
    }
  }

  /// Check if ML model is available and ready
  static bool get isMLAvailable => _mlModelAvailable && _mlInitialized;

  /// Hybrid detection: combines rule-based + ML approaches
  /// Falls back to rule-based if ML is not available
  static Future<ActionResult?> detectWithBody(
    String subject,
    String snippet,
    String bodyContent,
  ) async {
    // Always run rule-based detection first (baseline)
    final ruleBasedResult = ActionExtractor.detectWithBody(subject, snippet, bodyContent);

    // If ML is not available, use rule-based result
    if (!isMLAvailable) {
      return ruleBasedResult;
    }

    // Phase 1: Hybrid approach - ML + rule-based
    // TODO: Implement ML inference
    // - Preprocess text (tokenization, encoding)
    // - Run ML model inference
    // - Extract entities (dates, action phrases)
    // - Combine with rule-based results

    // For now, return rule-based result
    // Future: Combine ML and rule-based results with weighted confidence
    return ruleBasedResult;
  }

  /// Quick detection using hybrid approach
  static Future<ActionResult?> detectQuick(String subject, String snippet) async {
    // Always run rule-based detection first
    final ruleBasedResult = ActionExtractor.detectQuick(subject, snippet);

    // If ML is not available, use rule-based result
    if (!isMLAvailable) {
      return ruleBasedResult;
    }

    // Phase 1: Hybrid approach for quick detection
    // TODO: Implement ML inference on subject/snippet
    // For now, return rule-based result
    return ruleBasedResult;
  }

  /// Check if email is an action candidate (hybrid approach)
  static Future<bool> isActionCandidate(String subject, String snippet) async {
    // Always run rule-based check first
    final ruleBasedCandidate = ActionExtractor.isActionCandidate(subject, snippet);

    // If ML is not available, use rule-based result
    if (!isMLAvailable) {
      return ruleBasedCandidate;
    }

    // Phase 1: Hybrid candidate detection
    // TODO: Use ML for candidate detection
    // For now, return rule-based result
    return ruleBasedCandidate;
  }

  /// Record user feedback for training data collection
  /// This will be used to improve the ML model
  static Future<void> recordFeedback({
    required String messageId,
    required String subject,
    required String snippet,
    String? bodyContent,
    required ActionResult? detectedResult,
    required ActionResult? userCorrectedResult,
    required FeedbackType feedbackType,
  }) async {
    try {
      final feedback = ActionFeedback(
        messageId: messageId,
        subject: subject,
        snippet: snippet,
        bodyContent: bodyContent,
        detectedResult: detectedResult,
        userCorrectedResult: userCorrectedResult,
        feedbackType: feedbackType,
        timestamp: DateTime.now(),
      );

      final repo = ActionFeedbackRepository();
      await repo.storeFeedback(feedback);
      debugPrint('[MLActionExtractor] Feedback recorded: $feedbackType for message $messageId');
    } catch (e) {
      debugPrint('[MLActionExtractor] Error recording feedback: $e');
    }
  }
}

/// Type of feedback from user
enum FeedbackType {
  /// User corrected the detected action (date or text)
  correction,
  /// User marked as "no action" when action was detected
  falsePositive,
  /// User added action when none was detected
  falseNegative,
  /// User confirmed the detected action was correct
  confirmation,
}

/// Feedback data structure for training
class ActionFeedback {
  final String messageId;
  final String subject;
  final String snippet;
  final String? bodyContent;
  final ActionResult? detectedResult;
  final ActionResult? userCorrectedResult;
  final FeedbackType feedbackType;
  final DateTime timestamp;

  ActionFeedback({
    required this.messageId,
    required this.subject,
    required this.snippet,
    this.bodyContent,
    this.detectedResult,
    this.userCorrectedResult,
    required this.feedbackType,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'subject': subject,
      'snippet': snippet,
      'bodyContent': bodyContent,
      'detectedResult': detectedResult?.toJson(),
      'userCorrectedResult': userCorrectedResult?.toJson(),
      'feedbackType': feedbackType.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Extension to serialize ActionResult to JSON
extension ActionResultJson on ActionResult {
  Map<String, dynamic> toJson() {
    return {
      'actionDate': actionDate.toIso8601String(),
      'confidence': confidence,
      'insightText': insightText,
    };
  }
}

