# Tagging Process Summary

This document summarizes the current two-phase tagging process for Subscriptions, Attachments, Actions, and Shopping categories.

## **Subscriptions:**

**Phase 1:** Check email header on download for unsubscribe link
- Checks for `List-Unsubscribe` or `List-ID` headers
- If found, extracts unsubscribe link from `List-Unsubscribe` header
- Tags email as subscription immediately (no body download)

**Phase 2:** For remaining emails, check for likely candidates and open body to search for Unsubscribe link
- Skips emails already tagged in Phase 1
- Heuristic check: looks for subscription keywords (`newsletter`, `news`, `digest`, `alert`, `update`, `weekly`, `daily`, `monthly`) in subject, or `unsubscribe` in subject, or `noreply` in from address, or Gmail categories containing `forum`/`update`
- If candidate: downloads email body and searches for unsubscribe links using regex patterns with scoring
- Tags as subscription ONLY if unsubscribe link is found in body
- Uses scoring system: prioritizes mailto links, exact "Unsubscribe" anchor text, URL keywords; penalizes homepage/index URLs

---

## **Actions:**

**Phase 1:** None
- No action detection in Phase 1

**Phase 2:** For likely emails, open body to heuristic match for actions
- Skips emails that already have actions (preserves user edits)
- Quick candidate check: `ActionExtractor.isActionCandidate()` on subject/snippet only (lightweight, no body download)
  - Looks for action phrases (e.g., "join", "attend", "watch", "live", etc.)
  - Checks for time mentions or relative dates
- If candidate:
  1. Quick detection: `ActionExtractor.detectQuick()` on subject/snippet (low confidence)
  2. If quick result found: downloads email body
  3. Deep detection: `ActionExtractor.detectWithBody()` with full body content (higher confidence)
  4. Uses deep result if confidence ≥ 0.6, otherwise falls back to quick result if confidence ≥ 0.5
- Extracts action date (relative dates prioritized over numeric dates) and generates insight text

---

## **Attachments:**

**Phase 1:** Check payload structure on download
- Recursively checks message payload for parts with `filename` field
- Checks payload itself and all nested parts
- Sets `hasAttachments` flag if any part has a non-empty filename
- No filtering of inline images or content types at this stage

**Phase 2:** None
- Attachment detection is complete in Phase 1 (header-only check)
- No additional processing needed

---

## **Shopping:**

**Phase 1:** Check Gmail labelIds for shopping category
- Checks if `labelIds` contains `CATEGORY_PURCHASES`
- If found, tags email as shopping immediately

**Phase 2:** None
- Shopping detection is complete in Phase 1 (uses Gmail's built-in category)
- No additional processing needed

---

## Summary Table

| Category | Phase 1 | Phase 2 |
|----------|---------|---------|
| **Subscriptions** | Check headers (`List-Unsubscribe`, `List-ID`) | Heuristic candidate check → body search for unsubscribe links |
| **Actions** | None | Candidate check → quick detection → deep body-based detection |
| **Attachments** | Check payload structure for filenames | None |
| **Shopping** | Check Gmail `CATEGORY_PURCHASES` label | None |

---

## Implementation Details

### Subscription Detection
- **Phase 1 Location**: `lib/services/gmail/gmail_sync_service.dart` → `phase1Tagging()`
- **Phase 2 Location**: `lib/services/gmail/gmail_sync_service.dart` → `phase2TaggingNewMessages()`
- **Unsubscribe Link Extraction**: `lib/services/gmail/gmail_sync_service.dart` → `_tryExtractUnsubLink()`
- Uses regex patterns with scoring system for link extraction

### Action Detection
- **Phase 2 Location**: `lib/services/gmail/gmail_sync_service.dart` → `phase2TaggingNewMessages()`
- **Action Extractor**: `lib/services/actions/action_extractor.dart`
- Confidence thresholds: Deep detection ≥ 0.6, Quick detection ≥ 0.5

### Attachment Detection
- **Phase 1 Location**: `lib/data/models/gmail_message.dart` → `_hasAttachments()`
- Recursively checks payload structure for filename fields

### Shopping Detection
- **Phase 1 Location**: `lib/services/gmail/gmail_sync_service.dart` → `phase1Tagging()`
- Uses Gmail's built-in `CATEGORY_PURCHASES` label

