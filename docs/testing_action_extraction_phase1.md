# Testing Action Extraction Phase 1

## What Phase 1 Provides

Phase 1 implements the **infrastructure** for ML-enhanced action extraction:
- ✅ Feedback collection system (stores when users edit actions)
- ✅ ML extractor architecture (ready for model integration)
- ✅ Database schema for feedback storage
- ✅ Automatic feedback recording when actions are edited

**Note**: Currently still uses rule-based extraction, but now **collects feedback** for future ML training.

## How to Test Feedback Collection

### Step 1: Trigger Action Detection

1. Make sure you have emails that would normally get actions detected
2. Let the app sync emails and detect actions automatically
3. Check the debug logs for action detection:
   ```
   [Phase2] ✓ ACTION: subject="..." -> deep/quick (date, conf=X)
   ```

### Step 2: Edit an Action to Trigger Feedback

1. Find an email with a detected action
2. Click to edit the action (either from email tile or Actions window)
3. Make one of these changes:
   - **Change the date** → Records as `correction`
   - **Change the action text** → Records as `correction`
   - **Remove the action** (set to null) → Records as `falsePositive`
   - **Add an action** where none was detected → Records as `falseNegative`
   - **Save without changes** → Records as `confirmation`

### Step 3: Check Debug Logs

Look for feedback collection messages:
```
[MLActionExtractor] Feedback recorded: correction for message <messageId>
[MLActionExtractor] Feedback recorded: falsePositive for message <messageId>
[MLActionExtractor] Feedback recorded: falseNegative for message <messageId>
[MLActionExtractor] Feedback recorded: confirmation for message <messageId>
```

### Step 4: Verify Feedback in Database

You can check the feedback table directly, or export the data:

**Using Flutter DevTools or Database Browser:**
- Open your SQLite database: `domail.db`
- Query: `SELECT * FROM action_feedback ORDER BY timestamp DESC LIMIT 10;`

**Future**: Export functionality will be added to export feedback for training.

## Testing Scenarios

### Scenario 1: Correct an Incorrect Date
1. Email has action detected with wrong date (e.g., detected "2-Mar" but should be "today")
2. Edit the action, correct the date
3. **Expected**: Feedback type = `correction`, both detected and user-corrected actions stored

### Scenario 2: Remove False Positive
1. Email has action detected but shouldn't have one
2. Edit the action, remove it (set date/text to null)
3. **Expected**: Feedback type = `falsePositive`, detected action stored, user action = null

### Scenario 3: Add Missing Action
1. Email doesn't have action detected but should have one
2. Edit and add an action manually
3. **Expected**: Feedback type = `falseNegative`, detected action = null, user action stored

### Scenario 4: Confirm Correct Detection
1. Email has action detected correctly
2. Edit the action but don't change anything (or make minor change then revert)
3. **Expected**: Feedback type = `confirmation` or `correction`

## Current Limitations (Phase 1)

- ML model not yet integrated (still uses rule-based)
- No UI for viewing/exporting feedback yet
- Feedback is stored but not actively used for training (that's Phase 2+)

## Expected Behavior

✅ **Working Now:**
- Actions detected using rule-based extraction
- Feedback collected when users edit actions
- Feedback stored in database
- Debug logs show feedback recording

⏳ **Not Yet Implemented:**
- ML model inference
- Feedback export UI
- Model training from feedback
- Hybrid ML + rule-based results

## Debug Commands

To check if feedback is being collected:

```dart
// Add this temporarily to test (in HomeScreen or a test button)
final repo = ActionFeedbackRepository();
final count = await repo.getFeedbackCount();
print('Total feedback entries: $count');
```

## Next Steps (Phase 2+)

1. Load ML model (TFLite/ONNX)
2. Run ML inference on emails
3. Combine ML + rule-based results
4. Use feedback data to improve model

