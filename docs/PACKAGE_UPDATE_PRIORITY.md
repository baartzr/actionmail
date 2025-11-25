# Package Update Priority & Testing Recommendations

## 🔴 Critical Priority (Security & Core Functionality)

### 1. **flutter_secure_storage** (`^9.0.0` → Latest: `^9.2.2`)
**Why Critical:**
- Stores sensitive authentication tokens
- Security vulnerabilities in older versions
- Breaking changes unlikely but possible

**Current Usage:**
- Token storage for Google OAuth
- Secure credential management

**Tests Needed:**
- ✅ **Existing:** Token storage/retrieval tests
- ➕ **Add:** 
  - Migration tests for stored tokens after update
  - Platform-specific secure storage tests (Windows, macOS, Linux)
  - Error handling tests for storage failures

**Location:** `lib/services/auth/google_auth_service.dart`

---

### 2. **firebase_core** (`^3.6.0` → Latest: `^3.7.0+`) & **cloud_firestore** (`^5.4.4` → Latest: `^6.1.0`)
**Why Critical:**
- Major version jump (5.x → 6.x) indicates breaking changes
- Cross-device sync dependency
- Security and performance improvements

**Current Usage:**
- Cross-device email metadata sync
- Real-time updates between devices

**Breaking Changes Expected:**
- API method signature changes
- Query syntax updates
- Migration to Firestore v2 API

**Tests Needed:**
- ➕ **Add:**
  - Firestore sync service integration tests
  - Migration tests for existing Firestore data
  - Network failure handling tests
  - Concurrent write conflict resolution tests
  - Real-time listener tests

**Locations:**
- `lib/services/sync/firebase_sync_service.dart`
- `lib/main.dart`

---

### 3. **googleapis** (`^11.4.0` → Latest: `^15.0.0`) & **googleapis_auth** (`^1.4.1` → Latest: `^2.0.0`)
**Why Critical:**
- Major version updates (11.x → 15.x, 1.x → 2.x)
- Gmail API changes
- Authentication flow improvements
- Breaking changes highly likely

**Current Usage:**
- Gmail API calls (sync, fetch, labels)
- OAuth token management

**Breaking Changes Expected:**
- API method signatures
- Request/response format changes
- Authentication token handling

**Tests Needed:**
- ✅ **Existing:** Basic Gmail sync tests
- ➕ **Add:**
  - Gmail API integration tests (mock HTTP responses)
  - OAuth token refresh tests
  - API error handling tests (429 rate limits, 403 permissions)
  - Backward compatibility tests
  - Migration path tests

**Locations:**
- `lib/services/gmail/gmail_sync_service.dart`
- `lib/services/auth/google_auth_service.dart`

---

### 4. **flutter_riverpod** (`^2.5.1` → Latest: `^3.0.3`)
**Why Critical:**
- Major version update (2.x → 3.x)
- Core state management library
- Used throughout the app

**Current Usage:**
- Email list state management
- Provider architecture
- State notifiers

**Breaking Changes Expected:**
- Provider API changes
- StateNotifier API updates
- AsyncValue handling changes
- Provider scope changes

**Tests Needed:**
- ✅ **Existing:** Basic provider tests in `mock_providers.dart`
- ➕ **Add:**
  - Provider migration tests
  - StateNotifier upgrade path tests
  - AsyncValue migration tests
  - Provider override tests
  - State persistence tests

**Locations:**
- All feature files using Riverpod
- `lib/features/home/domain/providers/email_list_provider.dart`
- `test/helpers/mock_providers.dart`

---

## 🟠 High Priority (Stability & Performance)

### 5. **sqflite** (`^2.3.0` → Latest: `^2.4.0`) & **sqflite_common_ffi** (`^2.3.0` → Latest: `^2.4.0`)
**Why Important:**
- Database operations
- Potential migration path issues
- Performance improvements

**Current Usage:**
- Local email storage
- Message repository
- Action feedback storage

**Tests Needed:**
- ✅ **Existing:** Integration tests in `test/integration/email_sync_test.dart`
- ➕ **Add:**
  - Database migration tests (schema version 14 → future versions)
  - Transaction rollback tests
  - Concurrent access tests
  - Database corruption recovery tests
  - FFI-specific tests for desktop platforms

**Locations:**
- `lib/data/db/app_database.dart`
- `lib/data/repositories/message_repository.dart`
- `test/integration/email_sync_test.dart`

---

### 6. **flutter_appauth** (`^6.0.2` → Latest: `^11.0.0`)
**Why Important:**
- Major version jump (6.x → 11.x)
- OAuth authentication
- Breaking changes likely

**Current Usage:**
- Google OAuth flow
- Token exchange

**Tests Needed:**
- ➕ **Add:**
  - OAuth flow integration tests
  - Token refresh tests
  - Platform-specific OAuth tests (mobile vs desktop)
  - Error scenario tests (user cancellation, network errors)

**Locations:**
- `lib/services/auth/google_auth_service.dart`

---

### 7. **http** (`^1.1.0` → Latest: `^1.6.0`)
**Why Important:**
- Core networking library
- Security improvements
- Performance enhancements

**Current Usage:**
- Pushbullet REST API calls
- Gmail API requests
- WhatsApp API calls

**Tests Needed:**
- ✅ **Existing:** Basic HTTP usage tests
- ➕ **Add:**
  - HTTP timeout handling tests
  - Retry logic tests
  - Request/response interception tests
  - Network error handling tests

**Locations:**
- `lib/services/sms/pushbullet_rest_service.dart`
- `lib/services/whatsapp/whatsapp_api_service.dart`
- `lib/services/gmail/gmail_sync_service.dart`

---

## 🟡 Medium Priority (Feature Updates)

### 8. **web_socket_channel** (`^2.4.0` → Latest: `^3.0.3`)
**Why Important:**
- Real-time SMS sync
- Major version update

**Tests Needed:**
- ➕ **Add:**
  - WebSocket connection tests
  - Reconnection logic tests
  - Message parsing tests
  - Connection failure handling tests

**Locations:**
- `lib/services/sms/sms_sync_manager.dart`

---

### 9. **flutter_inappwebview** (`^6.1.5` → Latest: `^6.1.0+`)
**Why Important:**
- Email HTML rendering
- Security updates

**Tests Needed:**
- ➕ **Add:**
  - WebView initialization tests
  - HTML rendering tests
  - JavaScript injection tests
  - Security policy tests

**Locations:**
- `lib/features/home/presentation/widgets/email_viewer_dialog.dart`

---

## 📋 Recommended Test Suite Structure

After updating packages, create these test files:

### New Test Files Needed:

1. **`test/integration/firebase_sync_test.dart`**
   - Firestore read/write operations
   - Real-time listener behavior
   - Conflict resolution
   - Migration from v5 to v6

2. **`test/integration/gmail_api_test.dart`**
   - Mock Gmail API responses
   - Token refresh scenarios
   - Rate limiting handling
   - Error recovery

3. **`test/integration/auth_flow_test.dart`**
   - OAuth flow end-to-end
   - Token storage/retrieval
   - Multi-account handling
   - Re-authentication scenarios

4. **`test/unit/providers/riverpod_migration_test.dart`**
   - Provider API compatibility
   - StateNotifier migration
   - AsyncValue handling

5. **`test/integration/database_migration_test.dart`**
   - Schema version upgrades
   - Data integrity checks
   - Rollback scenarios

---

## 🔄 Update Strategy

### Phase 1: Security Critical (Week 1)
1. `flutter_secure_storage` → Add storage migration tests
2. `firebase_core` + `cloud_firestore` → Full integration test suite

### Phase 2: Core Functionality (Week 2-3)
3. `googleapis` + `googleapis_auth` → API integration tests
4. `flutter_riverpod` → Provider migration tests

### Phase 3: Stability (Week 4)
5. `sqflite` + `sqflite_common_ffi` → Database migration tests
6. `flutter_appauth` → OAuth flow tests
7. `http` → Network error handling tests

### Phase 4: Features (Week 5+)
8. `web_socket_channel` → WebSocket tests
9. `flutter_inappwebview` → WebView tests

---

## ✅ Testing Checklist

Before updating each package:

- [ ] Review changelog for breaking changes
- [ ] Check migration guides
- [ ] Identify affected code paths
- [ ] Create/update test cases
- [ ] Test in isolation first
- [ ] Run full test suite
- [ ] Manual testing on all platforms
- [ ] Monitor for regressions

---

## 📚 Resources

- [Flutter Package Update Guide](https://docs.flutter.dev/packages-and-plugins/developing-packages)
- [Riverpod 3.0 Migration](https://riverpod.dev/docs/migration/from_riverpod_2.0)
- [Firebase Flutter Migration Guides](https://firebase.google.com/docs/flutter/setup)
- [sqflite Changelog](https://pub.dev/packages/sqflite/changelog)

