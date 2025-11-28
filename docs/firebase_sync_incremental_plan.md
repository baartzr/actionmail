## Firebase Email Meta Sync – Incremental Cursor Plan

### Goals
- Only download metadata changes that happened after the last successful sync.
- Keep network/storage usage minimal so SMS/MMS payloads can be added later without blowing budgets.
- Maintain compatibility with legacy two-doc schema while we refactor to single-doc.

### Current Pain Points
1. `_loadInitialValues()` calls `.get()` on the entire `emailMeta` subcollection (hundreds of docs) every startup.
2. Real-time listener still sees every doc once because we always start from scratch.
3. SMS messages will multiply the document count, so full scans become expensive.

### Incremental Cursor Strategy
1. **Change log collection**  
   - Introduce `users/{userId}/emailMetaLog`.  
   - Each time we update `emailMeta/{messageId}`, also append a lightweight log doc:
     ```
     {
       id: auto,
       messageId,
       type: 'status' | 'action',
       lastModified: serverTimestamp,
       checksum: hash(fields) // optional dedupe aid
     }
     ```
   - Writing the log inside a batch with the metadata update ensures ordering.

2. **Cursor storage**  
   - Store `lastLogCursor_{accountId}` (timestamp + docId) in `SharedPreferences`.
   - On startup call `fetchChangesSince(cursor)` which runs:
     ```
     emailMetaLog
       .orderBy('lastModified')
       .startAfter([cursor.timestamp, cursor.docId])
       .limit(batchSize)
     ```

3. **Batch processing loop**  
   - Process changes in chunks of 100 (tunable).  
   - After each batch, persist the cursor (timestamp + last docId).  
   - Stop when batch < limit.  
   - For each log entry, read just the targeted `emailMeta/{messageId}` doc (or trust the payload if we embed it later).

4. **Listener interplay**  
   - Real-time listener still handles newly arriving updates while the app is in foreground.  
   - When we pause/resume Firestore we record the latest cursor so we can backfill anything missed during downtime before re-enabling the listener.

5. **Legacy fallback**  
   - If no cursor exists (first install) fall back to the current `_loadInitialValues()` full scan, but immediately seed the cursor with `now()` to avoid reprocessing.

### Benefits
- Cold start cost drops from “read every doc” to “read only new docs since last run”.
- Network usage scales with actual change volume (required before adding SMS/MMS entries).
- Cursor gives us a natural point to expire data (e.g., delete log entries older than 7 days in a Cloud Function).

### Next Steps
1. Update write path to batch metadata update + log insert.
2. Implement `fetchChangesSinceCursor()` + persistence.
3. Replace `_loadInitialValues()` with incremental replay + fallback.
4. Wire cursor advancement into pause/resume + listener restart.

