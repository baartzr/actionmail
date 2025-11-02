# Hybrid ML + Rule-Based Action Extraction Architecture Plan

## Executive Summary

This plan outlines a hybrid architecture combining:
1. **Rule-based extraction** (fast, reliable for clear patterns)
2. **ML-based NER** (context-aware, handles ambiguity)
3. **User feedback collection** (continuous improvement)
4. **Personalized learning** (future enhancement)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Email Processing Pipeline                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────┐
        │   Fast Rule-Based Pre-filter          │
        │   (High confidence patterns)          │
        └───────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
        High Confidence            Low Confidence/Ambiguous
              │                           │
              ▼                           ▼
    ┌───────────────────┐      ┌──────────────────────┐
    │   Return Result   │      │   ML NER Inference   │
    │   (Rule-based)    │      │   (TFLite/ONNX)      │
    └───────────────────┘      └──────────────────────┘
                                      │
                                      ▼
                            ┌──────────────────────┐
                            │   Confidence Scoring  │
                            │   & Result Fusion    │
                            └──────────────────────┘
                                      │
                                      ▼
                            ┌──────────────────────┐
                            │   Rule-Based Date    │
                            │   Normalization      │
                            └──────────────────────┘
                                      │
                                      ▼
                            ┌──────────────────────┐
                            │   Final Action       │
                            │   (with metadata)    │
                            └──────────────────────┘
                                      │
                                      ▼
                            ┌──────────────────────┐
                            │   User Feedback      │
                            │   Collection         │
                            └──────────────────────┘
```

---

## Phase 1: Enhanced Rule-Based System (Foundation)

### Goals
- Improve current regex/pattern matching
- Add robust date parsing
- Create confidence scoring system
- Prepare extraction pipeline structure

### Components

#### 1.1 Enhanced Action Extractor (`lib/services/actions/action_extractor_v2.dart`)
- **Current**: `lib/services/actions/action_extractor.dart`
- **Enhancements**:
  - Confidence scoring (0.0 - 1.0) for each extraction
  - Multiple extraction strategies with fallback
  - Better context awareness
  - Action phrase classification (meeting, deadline, task, etc.)

#### 1.2 Dart Date Parser (`lib/services/actions/date_parser.dart`)
- **Purpose**: Equivalent to Python's `dateparser`
- **Features**:
  - Relative dates: "today", "tomorrow", "next week"
  - Absolute dates: "March 15", "15/03/2024"
  - Time parsing: "6 p.m. ET", "14:30"
  - Timezone handling
  - Context-aware parsing (email date context)
  - Uses `intl` package, extends with custom logic

#### 1.3 Extraction Result Model (`lib/models/action_extraction_result.dart`)
```dart
class ActionExtractionResult {
  final String? actionText;
  final DateTime? actionDate;
  final double confidence;  // 0.0 - 1.0
  final ExtractionMethod method;  // ruleBased, ml, hybrid
  final List<String> actionPhrases;  // Detected phrases
  final String sourceText;  // Original text used
  final Map<String, dynamic> metadata;
}

enum ExtractionMethod {
  ruleBased,
  mlNer,
  hybrid,
  userCorrected
}
```

### Implementation Steps
1. Refactor `ActionExtractor` to use new models
2. Implement `DateParser` utility
3. Add confidence scoring to rules
4. Create extraction strategy chain
5. Update existing code to use new structure

**Timeline**: 2-3 days

---

## Phase 2: Feedback Collection System

### Goals
- Capture user corrections and confirmations
- Store feedback locally with privacy controls
- Enable future training data generation
- Track model performance metrics

### Components

#### 2.1 Feedback Data Model (`lib/models/action_feedback.dart`)
```dart
class ActionFeedback {
  final String id;
  final String messageId;
  final String accountId;
  
  // Original extraction
  final ActionExtractionResult original;
  
  // User correction (if provided)
  final ActionExtractionResult? userCorrection;
  
  // User action type
  final FeedbackAction action;  // corrected, confirmed, dismissed
  
  // Context
  final String emailSubject;
  final String emailSnippet;  // Sanitized, no PII
  final DateTime timestamp;
  
  // Privacy/Sharing
  final bool shareAnonymously;  // User opt-in
  final bool isShared;  // Has been uploaded
}

enum FeedbackAction {
  corrected,    // User edited the action
  confirmed,    // User accepted as-is
  dismissed,    // User marked as "not an action"
  edited,       // User edited after extraction
}
```

#### 2.2 Feedback Storage (`lib/services/feedback/feedback_storage_service.dart`)
- **Database**: SQLite table `action_feedback`
- **Operations**:
  - `saveFeedback(Feedback)` - Store locally
  - `getUnsyncedFeedbacks()` - For future sync
  - `markAsSynced(String id)` - After upload
  - `getFeedbackStats()` - For analytics
  - `deleteOldFeedback(Duration)` - Privacy cleanup

#### 2.3 Feedback Collector (`lib/services/feedback/feedback_collector.dart`)
- **Integration Points**:
  - `EmailTile` - When user edits action
  - `ActionsSummaryWindow` - When user marks complete
  - `EmailViewerDialog` - When user confirms/dismisses action
- **Automatic Collection**:
  - Capture when `actionInsightText` changes
  - Compare original vs. new values
  - Determine feedback type automatically

#### 2.4 Feedback UI (`lib/features/feedback/`)
- **Settings Toggle**: Opt-in/opt-out for sharing
- **Feedback Stats**: Show user contribution metrics
- **Privacy Info**: Explain what's collected

### Database Schema
```sql
CREATE TABLE action_feedback (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  
  -- Original extraction (JSON)
  original_text TEXT,
  original_date TEXT,
  original_confidence REAL,
  original_method TEXT,
  
  -- User correction (JSON, nullable)
  user_text TEXT,
  user_date TEXT,
  
  -- Feedback type
  action TEXT NOT NULL,  -- corrected, confirmed, dismissed
  
  -- Context (sanitized)
  email_subject TEXT,
  email_snippet TEXT,
  timestamp INTEGER NOT NULL,
  
  -- Sharing
  share_anonymously INTEGER DEFAULT 0,
  is_shared INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE INDEX idx_feedback_message ON action_feedback(message_id);
CREATE INDEX idx_feedback_unsynced ON action_feedback(is_shared) WHERE is_shared = 0;
```

### Implementation Steps
1. Create feedback data models
2. Add database migration
3. Implement `FeedbackStorageService`
4. Integrate `FeedbackCollector` into action editing flows
5. Add privacy settings UI
6. Add feedback stats display

**Timeline**: 3-4 days

---

## Phase 3: ML Model Integration

### Goals
- Integrate TFLite (mobile) and ONNX (desktop) models
- Create inference pipeline
- Implement model loading and caching
- Add fallback to rule-based system

### Components

#### 3.1 Model Interface (`lib/services/ml/model_provider.dart`)
```dart
abstract class ActionExtractionModel {
  Future<void> initialize();
  Future<MLActionResult?> predict(String text, Map<String, dynamic> context);
  bool get isInitialized;
  String get modelVersion;
}

class MLActionResult {
  final String? actionText;
  final DateTime? actionDate;
  final double confidence;
  final Map<String, double> entityScores;  // NER entity probabilities
}
```

#### 3.2 TFLite Provider (`lib/services/ml/tflite_provider.dart`)
- **Platform**: Android, iOS
- **Model Format**: `.tflite` (quantized INT8)
- **Dependencies**: `tflite_flutter` or `tflite_flutter_helper`
- **Model Location**: `assets/models/action_extractor.tflite`
- **Features**:
  - Model loading from assets
  - Input preprocessing (tokenization)
  - Inference execution
  - Output post-processing

#### 3.3 ONNX Provider (`lib/services/ml/onnx_provider.dart`)
- **Platform**: Windows, macOS, Linux
- **Model Format**: `.onnx` (quantized)
- **Dependencies**: `onnxruntime` (if available) or native bindings
- **Model Location**: `assets/models/action_extractor.onnx`
- **Features**:
  - Model loading from assets or file system
  - Input preprocessing
  - Inference execution
  - Output post-processing

#### 3.4 Text Preprocessor (`lib/services/ml/text_preprocessor.dart`)
- **Tokenization**: Convert text to model input format
- **Normalization**: Clean email text, handle HTML entities
- **Padding/Truncation**: Ensure consistent input length
- **Context Encoding**: Add email metadata if model supports it

#### 3.5 Hybrid Extractor (`lib/services/actions/hybrid_action_extractor.dart`)
- **Orchestration**: Combines rule-based + ML results
- **Strategy**:
  1. Run rule-based first (fast)
  2. If confidence < threshold, run ML inference
  3. Fuse results with weighted confidence
  4. Apply date normalization
- **Fallback**: If ML unavailable/fails, use rule-based only

### Model Requirements

#### Initial Model (Placeholder/Minimal)
- **Architecture**: Simple LSTM or Transformer-based NER
- **Input**: Tokenized email text (subject + snippet)
- **Output**: 
  - Action text span (start, end, confidence)
  - Date entities (normalized)
  - Intent classification (meeting, deadline, task)
- **Size Target**: <10MB quantized
- **Performance Target**: <100ms inference on mobile

#### Future Model (Trained)
- Fine-tuned on user feedback data
- Larger vocabulary for email domain
- Better context understanding
- Regular updates via OTA model downloads

### Implementation Steps
1. Research and select TFLite/ONNX packages
2. Create model interface abstraction
3. Implement TFLite provider for mobile
4. Implement ONNX provider for desktop
5. Create text preprocessing pipeline
6. Build hybrid extractor orchestrator
7. Add model loading error handling
8. Add fallback mechanisms

**Timeline**: 5-7 days (depends on model availability)

---

## Phase 4: Result Fusion & Confidence Scoring

### Goals
- Combine rule-based and ML results intelligently
- Provide reliable confidence scores
- Handle conflicts between methods
- Optimize performance

### Components

#### 4.1 Confidence Fusion (`lib/services/actions/confidence_fusion.dart`)
- **Weighted Average**: Combine confidence scores
- **Agreement Detection**: If both methods agree, boost confidence
- **Disagreement Handling**: If methods conflict, use heuristic rules
- **Calibration**: Adjust scores based on historical accuracy

#### 4.2 Extraction Strategy (`lib/services/actions/extraction_strategy.dart`)
- **Decision Tree**:
  ```
  If rule-based confidence > 0.9:
    Return rule-based result
  Else if ML is available:
    Run ML inference
    If ML confidence > 0.7:
      Return ML result (or fused)
    Else:
      Return rule-based with low confidence flag
  Else:
    Return rule-based result
  ```

### Implementation Steps
1. Implement confidence fusion logic
2. Create extraction strategy engine
3. Add performance metrics tracking
4. Tune confidence thresholds
5. Add A/B testing capability

**Timeline**: 2-3 days

---

## Phase 5: Model Training Pipeline (Future)

### Goals
- Generate training data from user feedback
- Train/retrain models periodically
- Distribute updated models to users
- Track model performance improvements

### Components

#### 5.1 Training Data Generator (`lib/services/ml/training_data_generator.dart`)
- **Input**: User feedback database
- **Process**:
  - Anonymize emails (remove PII)
  - Format for NER training (CoNLL/BIO format)
  - Balance dataset (corrected vs. confirmed)
  - Split train/validation/test
- **Output**: Training dataset files

#### 5.2 Model Trainer (Backend/External)
- **Not in Flutter app** - separate Python service
- Uses collected feedback (anonymized, opt-in only)
- Fine-tunes pre-trained NER model
- Validates on test set
- Exports to TFLite/ONNX formats

#### 5.3 Model Distribution
- **Option A**: Include in app updates
- **Option B**: OTA download from server
- **Versioning**: Track model versions
- **Rollback**: Ability to revert to previous model

### Implementation Steps
1. Design training data export format
2. Create backend API for feedback upload (opt-in)
3. Build Python training pipeline
4. Set up model versioning system
5. Implement OTA model download (if chosen)

**Timeline**: 10-14 days (includes backend work)

---

## Phase 6: Personalization (Future Enhancement)

### Goals
- Fine-tune model per user locally
- Improve accuracy for user-specific patterns
- Maintain privacy (all training on-device)

### Components

#### 6.1 On-Device Trainer (`lib/services/ml/local_trainer.dart`)
- **Federated Learning Lite**: Train on user's feedback only
- **Incremental Learning**: Update model weights gradually
- **Resource Management**: Train during idle time, low battery check

#### 6.2 Personal Model Storage
- Separate storage for user-specific model weights
- Merge with global model during inference
- Version tracking per user

### Implementation Steps
1. Research on-device training feasibility in Flutter
2. Implement lightweight training loop
3. Add battery/performance safeguards
4. Test model accuracy improvements

**Timeline**: 7-10 days (research-heavy)

---

## File Structure

```
lib/
├── models/
│   ├── action_extraction_result.dart
│   ├── action_feedback.dart
│   └── ml_action_result.dart
│
├── services/
│   ├── actions/
│   │   ├── action_extractor.dart (legacy, keep for now)
│   │   ├── action_extractor_v2.dart (enhanced rules)
│   │   ├── date_parser.dart
│   │   ├── hybrid_action_extractor.dart
│   │   ├── confidence_fusion.dart
│   │   └── extraction_strategy.dart
│   │
│   ├── ml/
│   │   ├── model_provider.dart
│   │   ├── tflite_provider.dart
│   │   ├── onnx_provider.dart
│   │   ├── text_preprocessor.dart
│   │   ├── training_data_generator.dart
│   │   └── local_trainer.dart (future)
│   │
│   └── feedback/
│       ├── feedback_collector.dart
│       ├── feedback_storage_service.dart
│       └── feedback_analytics.dart
│
├── features/
│   └── feedback/
│       ├── feedback_settings_screen.dart
│       └── feedback_stats_widget.dart
│
└── database/
    └── migrations/
        └── 004_add_action_feedback_table.dart

assets/
└── models/
    ├── action_extractor.tflite (mobile)
    ├── action_extractor.onnx (desktop)
    └── README.md (model info)
```

---

## Dependencies

### Required (Phase 1-2)
```yaml
# Already in project or standard
intl: ^0.19.0  # Date parsing
sqflite: ^2.3.0  # Feedback storage
```

### Required (Phase 3)
```yaml
# Mobile (TFLite)
tflite_flutter: ^0.10.0  # Or tflite_flutter_helper

# Desktop (ONNX) - Research needed
# Option 1: Native bindings
# Option 2: HTTP API to local service
# Option 3: Dart FFI bindings
```

### Optional (Phase 5)
```yaml
# For future model download
http: ^1.1.0  # Already in project
package_info_plus: ^5.0.0  # Version checking
```

---

## Privacy & Security

### Data Collection
- **Opt-in only**: User must explicitly enable sharing
- **Anonymization**: 
  - Remove email addresses, names, PII
  - Hash identifiers
  - Keep only action phrases and patterns
- **Local-first**: All feedback stored locally by default
- **User control**: View, export, delete feedback

### Data Transmission (if sharing enabled)
- **Encryption**: HTTPS only
- **Minimal data**: Only action text patterns, no full emails
- **Consent**: Clear explanation of what's shared
- **GDPR compliance**: Right to delete, export data

---

## Testing Strategy

### Unit Tests
- Date parser (various formats)
- Rule-based extractor
- Confidence scoring
- Feedback collection

### Integration Tests
- Hybrid extractor pipeline
- Model loading (mock models)
- Feedback storage/retrieval

### Performance Tests
- Inference latency (<100ms target)
- Memory usage
- Battery impact

### User Acceptance Tests
- Accuracy comparison (rule-based vs. ML)
- Feedback collection flow
- Privacy controls

---

## Implementation Timeline

### Sprint 1 (Week 1-2): Foundation
- Phase 1: Enhanced rule-based system
- Phase 2: Feedback collection system
- **Deliverable**: Improved extraction + feedback capture

### Sprint 2 (Week 3-4): ML Integration
- Phase 3: ML model integration (with placeholder model)
- Phase 4: Result fusion
- **Deliverable**: Hybrid system working end-to-end

### Sprint 3 (Week 5+): Training & Optimization
- Phase 5: Training pipeline (backend)
- Model updates and distribution
- Performance optimization
- **Deliverable**: Production-ready system with continuous improvement

### Future: Personalization
- Phase 6: On-device training (research phase)
- **Timeline**: TBD based on feasibility

---

## Success Metrics

### Extraction Accuracy
- **Baseline**: Current rule-based accuracy (~60-70%)
- **Target**: ML-enhanced accuracy (>80%)
- **Measure**: User feedback (confirmed vs. corrected rate)

### Performance
- **Inference time**: <100ms on mobile
- **Model size**: <10MB
- **Memory usage**: <50MB additional

### User Engagement
- **Feedback rate**: % of actions with user corrections
- **Sharing opt-in**: % of users sharing feedback
- **Accuracy improvement**: Measured over time

---

## Risk Mitigation

### Model Unavailable/Delayed
- **Mitigation**: Start with rule-based only, add ML later
- **Fallback**: Always have rule-based as backup

### Privacy Concerns
- **Mitigation**: Opt-in only, clear communication
- **Fallback**: Fully local mode (no sharing)

### Performance Issues
- **Mitigation**: Quantized models, lazy loading
- **Fallback**: Disable ML, use rules only

### Training Data Quality
- **Mitigation**: Validation, filtering noisy feedback
- **Fallback**: Weight feedback by user trust/accuracy

---

## Open Questions

1. **Model Source**: 
   - Train from scratch?
   - Fine-tune existing NER model?
   - Use pre-trained email-specific model?

2. **ONNX Runtime**: 
   - Is there a Flutter package?
   - Need native bindings?
   - Alternative approach?

3. **Model Updates**:
   - Via app updates?
   - OTA downloads?
   - Both?

4. **Training Frequency**:
   - Weekly?
   - Monthly?
   - Based on feedback volume?

5. **Personalization Priority**:
   - Is it worth the complexity?
   - When to implement?

---

## Next Steps (When Ready to Build)

1. **Immediate**: Review and refine this plan
2. **Phase 1 Start**: Begin with enhanced rule-based system
3. **Research**: Investigate TFLite/ONNX packages for Flutter
4. **Model Strategy**: Decide on model source (train vs. fine-tune vs. pre-trained)
5. **Backend Planning**: If sharing feedback, design API and data pipeline

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Status**: Planning Phase

