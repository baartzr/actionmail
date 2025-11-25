# Error Prompts Analysis

This document explains when network error and sign-in error prompts are displayed, and identifies inconsistencies.

## Network Error Prompts

### Test/Condition
A network error is detected when `GoogleAuthService.isLastErrorNetworkError(accountId) == true`. This is set when:
- `SocketException` is caught during token validation
- `ClientException` (which wraps network errors) is caught
- Network errors occur during token refresh

### Display Locations

#### 1. **Via `networkErrorProvider` (home_provider_listeners.dart:29-56)**
**Trigger:** When `networkErrorProvider` becomes `true`

**Dialog:** Simple `AlertDialog`
- Title: "Network Issue"
- Message: "There's a network issue. Please try again later."
- Button: "OK"
- **Clears provider immediately** before showing dialog

**When Set:**
- `email_list_provider.dart:432` - Token check fails with network error in `_syncFolderAndUpdateCurrent()`
- `email_list_provider.dart:484` - `incrementalSync()` fails with network error in `_syncFolderAndUpdateCurrent()`

**Note:** This is only for manual refresh (`_syncFolderAndUpdateCurrent`), NOT for background sync. Background sync silently skips network errors (line 231 in email_list_provider.dart).

#### 2. **Via Menu Refresh Button (home_menu_button.dart:66-88)**
**Trigger:** User clicks "Refresh" menu item, `ensureAccountAuthenticated()` returns `false`, AND `isLastErrorNetworkError(accountId) == true`

**Dialog:** Simple `AlertDialog`
- Title: "Network Issue"
- Message: "There's a network issue. Please try again later."
- Button: "OK"

**Inconsistency:** This is a separate code path that shows the same dialog independently of `networkErrorProvider`. The menu button checks the error state but doesn't use the provider system.

### Network Error Suppression

Network errors are **suppressed** (no prompt shown) during:
- **Background incremental sync** (`email_list_provider.dart:231`) - silently skipped
- **Incremental tick sync** (`email_list_provider.dart:229-234`) - silently skipped

## Sign-In/Auth Error Prompts

### Test/Condition
An auth error is detected when:
- `ensureValidAccessToken()` returns `null` or empty token
- AND `isLastErrorNetworkError(accountId) == false` (not a network error)
- OR `isLastErrorNetworkError(accountId) == null` (unknown error type)

### Display Location

#### Via `authFailureProvider` (home_provider_listeners.dart:58-73)
**Trigger:** When `authFailureProvider` is set to an account ID

**Condition:** Only shows if `next == selectedAccountId` (the failed account is currently selected)

**Action:** Calls `onHandleReauthNeeded(next)` which triggers `_handleReauthNeeded()` in `home_screen.dart:374-507`

**Dialog:** `ReauthPromptDialog` (reauth_prompt_dialog.dart)
- Two variants based on `isConnectionError`:

  **Network Variant** (`isConnectionError: true`):
  - Title: "Connection Problem"
  - Message: "There's a problem connecting to Gmail."
  - Actions: "Cancel", "Retry", "Reconnect"

  **Auth Variant** (`isConnectionError: false`):
  - Title: "Re-authentication Required"
  - Message: "Your Google account session has expired."
  - Actions: "Cancel", "Re-authenticate"

**When Set:**
- `email_list_provider.dart:239` - Background incremental sync token check fails (auth error)
- `email_list_provider.dart:441` - Manual sync token check fails (auth error)

**Inconsistency:** The `ReauthPromptDialog` can show network error variant, but this conflicts with the separate network error dialog system above.

## Key Inconsistencies

### 1. **Network Error Detection Logic Conflict**

The `ReauthPromptDialog` has a network error variant (`isConnectionError: true`), but network errors are also handled by a separate `networkErrorProvider` system. This creates two competing paths:

- Path A: `networkErrorProvider` → Simple "Network Issue" dialog
- Path B: `authFailureProvider` with `isConnectionError=true` → "Connection Problem" dialog with Retry/Reconnect

**Current behavior:**
- Manual refresh errors use Path A (`networkErrorProvider`)
- Auth failures use Path B (`authFailureProvider` with network variant)
- But if an auth check fails with a network error, it might trigger Path B instead of Path A

### 2. **Network Error in Menu Refresh**

The menu refresh button (`home_menu_button.dart:66-88`) checks for network errors independently and shows its own dialog, bypassing the `networkErrorProvider` system. This could result in:
- Menu refresh showing network error dialog
- Provider-based network error dialog showing simultaneously
- Or one showing but not the other, depending on timing

### 3. **Network Error State Clearing**

In `home_provider_listeners.dart:35`, the `networkErrorProvider` is cleared immediately when it becomes `true`, before the dialog is shown. This means:
- If multiple network errors occur quickly, only the first might show a dialog
- The state is cleared synchronously, but the dialog is shown in a post-frame callback

### 4. **Auth Error vs Network Error Detection Timing**

The error type (`networkError` vs `authError`) is determined at different times:
- During token check in `ensureValidAccessToken()`
- During `incrementalSync()` - error state checked AFTER the call

This creates a race condition where:
- Token check might fail with network error → sets network error state
- `incrementalSync()` might then fail with auth error → but network error state is still set
- Or vice versa

### 5. **Error State Not Cleared Before New Checks**

In `email_list_provider.dart:466`, error state is cleared before `incrementalSync()`, but this only happens in one code path (`_syncFolderAndUpdateCurrent`). Other paths might have stale error states.

## Recommendations

1. **Unify network error handling:** Use a single provider-based system for all network errors, including menu refresh
2. **Separate network vs auth errors:** Don't use `authFailureProvider` for network errors - use `networkErrorProvider` exclusively
3. **Clear error state consistently:** Clear error state before new operations, not just in some paths
4. **Add debouncing:** Prevent multiple error dialogs from showing simultaneously
5. **Improve error type detection:** Make error type detection more reliable and consistent across all code paths

