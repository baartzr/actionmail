## SMS/MMS Sync Architecture

### Overview
Domail relies on the Android “SMS Companion” app to read SMS/MMS from the system inbox and expose them via a ContentProvider. Domail polls that provider on a fixed cadence and copies messages into its own local store. Outgoing SMS/MMS requests also flow through the companion app so Android’s native `SmsManager` delivers them.

---

### Companion App (`sms-companion`)

1. **Monitoring**
   - `SmsSyncService` registers a `ContentObserver` on `Telephony.Sms` and `Telephony.Sms.Sent`.
   - Any time Android writes a new SMS/MMS, the observer fires and launches `syncNewMessages()`.

2. **Sync Logic**
   - Reads new entries from the system SMS/MMS database (`readSmsFromSystemSince` / `readMmsFromSystemSince`).
   - Deduplicates by normalized phone, timestamp (±1 s) and body text before inserting into the Room DB (`SmsMessage`).
   - Tracks a `last_sync_timestamp` in `SharedPreferences` so each run only pulls messages since the previous successful sync.
   - Runs a fallback poll every 10 s (`SYNC_INTERVAL_MS`) via `Handler.postDelayed`—this is purely a safety net if the observer is missed.

3. **Exposing data**
   - `SmsContentProvider` exposes `content://com.domail.smscompanion.provider/messages` (plus filtered URIs) so clients can list messages.
   - `insert(action=send)` routes outgoing SMS/MMS through `SmsSender`, which uses Android’s `SmsManager`.
   - After Domail saves a message, it calls `deleteMessage(id)` so the companion DB remains a short-lived queue.

---

### Domail App (`lib/services/sms`)

1. **Periodic pull (`SmsSyncManager`)**
   - On startup, `startCompanionSync` schedules `Timer.periodic(const Duration(seconds: 15), …)` and triggers an immediate `syncFromCompanionApp`.
   - This timer is the *only* mechanism Domail has to retrieve SMS/MMS from the companion ContentProvider (there is no push channel from the companion to Domail).

2. **Fetching and storing**
   - `CompanionSmsService.fetchAllMessages` queries the provider, mapping each row to `MessageIndex` (SMS text stored in `subject`, snippet = truncated subject).
   - `SmsSyncManager` deduplicates against existing Domail records, writes new ones via `MessageRepository.upsertMessages`, and calls `deleteMessages` on the companion for every successfully processed ID.

3. **UI behavior**
   - `EmailViewerDialog` renders SMS “subjects” as the message body; snippets are shown only if they differ from the subject.
   - When expanded, the body is suppressed if it matches the subject (common for SMS), preventing double display.

---

### Trade-offs / Tuning

- **Responsiveness**: Android’s ContentObserver gives near‑instant ingestion on the companion side; Domail sees updates within 15 s worst case (timer tick). Increasing the timer interval saves wakeups but lengthens that worst-case delay.
- **Battery**: Companion’s 10 s fallback poll and Domail’s 15 s poll are both configurable constants (`SYNC_INTERVAL_MS` in `SmsSyncService` and the `Timer.periodic` interval in `SmsSyncManager`). Longer intervals reduce background work at the cost of slower “missed observer” recovery.
- **Complexity**: Pushing DOM updates directly (e.g., via broadcasts) would reduce polling but requires additional IPC/security handling. The current pull model keeps the architecture straightforward.


