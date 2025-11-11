import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:actionmail/constants/app_constants.dart';
import 'package:actionmail/data/models/gmail_message.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/services/actions/action_extractor.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Custom exception class to carry HTTP status code for better error handling
class _GmailApiException implements Exception {
  final String message;
  final int statusCode;
  _GmailApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}

class ReplyContext {
  final String? messageIdHeader;
  final List<String> references;

  const ReplyContext({
    required this.messageIdHeader,
    required this.references,
  });
}

class GmailAttachmentData {
  final String filename;
  final String mimeType;
  final Uint8List bytes;

  const GmailAttachmentData({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });
}

class OriginalMessageContent {
  final String? htmlBody;
  final String? plainBody;
  final List<GmailAttachmentData> attachments;

  const OriginalMessageContent({
    required this.htmlBody,
    required this.plainBody,
    this.attachments = const [],
  });

  bool get hasHtml => htmlBody != null && htmlBody!.trim().isNotEmpty;
  bool get hasPlain => plainBody != null && plainBody!.trim().isNotEmpty;
  bool get hasAttachments => attachments.isNotEmpty;
}

class _InlineImage {
  final String mimeType;
  final String base64Data;

  const _InlineImage({
    required this.mimeType,
    required this.base64Data,
  });
}

/// Service to simulate Gmail API sync
/// In production, this would call the actual Gmail API
class GmailSyncService {
  final MessageRepository _repo = MessageRepository();
  static const String _possibleActionPrefix = 'Possible action: ';
  /// Load from local DB only
  Future<List<MessageIndex>> loadLocal(String accountId, {required String folderLabel}) async {
    return _repo.getByFolder(accountId, folderLabel);
  }
  /// Check if account has a history ID (has been synced before)
  Future<bool> hasHistoryId(String accountId) async {
    final historyId = await _repo.getLastHistoryId(accountId);
    return historyId != null;
  }
  /// Download messages from Gmail API for the given account
  Future<List<GmailMessage>> downloadMessages(String accountId, {String label = 'INBOX', int maxResults = 50}) async {
    final account = await GoogleAuthService().ensureValidAccessToken(accountId);
    if (account == null || account.accessToken.isEmpty) {
      return [];
    }
    final headers = {'Authorization': 'Bearer ${account.accessToken}'};
    // List message IDs
    Uri listUri;
    if (label == 'ARCHIVE') {
      // Archived: not in INBOX, SPAM, TRASH, DRAFT
      final q = '-in:inbox -in:spam -in:trash -in:draft';
      listUri = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages')
          .replace(queryParameters: {
        'q': q,
        'maxResults': '$maxResults',
      });
    } else {
      listUri = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages')
          .replace(queryParameters: {
        'labelIds': label,
        'maxResults': '$maxResults',
      });
    }
    final listResp = await http.get(listUri, headers: headers);
    if (listResp.statusCode != 200) return [];
    final listJson = (listResp.body.isNotEmpty) ? listResp.body : '{}';
    final listMap = jsonDecode(listJson) as Map<String, dynamic>;
    final items = (listMap['messages'] as List<dynamic>?) ?? [];
    
    // Fetch all messages in parallel
    final futures = items.map((item) async {
      final id = (item as Map<String, dynamic>)['id'] as String;
      final msgResp = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=full'),
        headers: headers,
      );
      if (msgResp.statusCode != 200) return null;
      final msgMap = jsonDecode(msgResp.body) as Map<String, dynamic>;
      return GmailMessage.fromJson(msgMap);
    }).toList();
    
    final results = await Future.wait(futures);
    return results.whereType<GmailMessage>().toList();
  }
  
  /// Convert Gmail API messages to MessageIndex and apply heuristics
  /// This simulates the process: Gmail API -> MessageIndex -> Action Detection
  Future<List<MessageIndex>> syncMessages(String accountId, {String folderLabel = 'INBOX'}) async {
    debugPrint('[Gmail] syncMessages starting account=$accountId folder=$folderLabel');
    final syncStart = DateTime.now();
    // Download from Gmail API
    final gmailMessages = await downloadMessages(accountId, label: folderLabel);
    final downloadDuration = DateTime.now().difference(syncStart);
    debugPrint('[Gmail] syncMessages downloaded ${gmailMessages.length} messages in ${downloadDuration.inMilliseconds}ms');
    
    // Convert Gmail format to MessageIndex
    final messageIndexes = gmailMessages.map((gmailMsg) => gmailMsg.toMessageIndex(accountId)).toList();
    
    // Log attachment candidates
    // Note: hasAttachments is basic check (any filename), verification happens in attachments window
    // Shopping and subscription checks happen in Phase 1 tagging
    for (var i = 0; i < gmailMessages.length && i < messageIndexes.length; i++) {
      final mi = messageIndexes[i];
      final subject = mi.subject;
      
      if (mi.hasAttachments) {
        debugPrint('[Sync] ✓ ATTACHMENT CANDIDATE: subject="$subject" -> has filename (needs verification)');
      }
    }

    // Preserve local fields when present locally (before applying sender prefs)
    // This ensures existing tags are preserved
    final idMap = await _repo.getByIds(accountId, messageIndexes.map((e) => e.id).toList());
    debugPrint('[SenderPrefs] syncMessages: loaded ${idMap.length} existing messages from DB');
    
    // Apply sender preferences (auto-apply local tag) only to messages without existing tags
    final messagesWithPrefs = await _applySenderPreferences(accountId, messageIndexes, idMap, context: 'syncMessages');
    
    // Note: Action detection moved to Phase 2 (deeper body-based detection)
    var enriched = messagesWithPrefs;

    // Preserve other local fields when present locally
    enriched = enriched.map((m) {
      final existing = idMap[m.id];
      if (existing != null) {
        // Folder moves
        if (existing.folderLabel == 'TRASH' || existing.folderLabel == 'ARCHIVE') {
          if (m.folderLabel != existing.folderLabel) {
            return m.copyWith(folderLabel: existing.folderLabel);
          }
        }
        // Action fields: prefer local when set
        final actDate = existing.actionDate ?? m.actionDate;
        final actText = existing.actionInsightText ?? m.actionInsightText;
        // Local classification fields: preserve existing values (subscription, shopping)
        // Note: unsubLink is preserved separately in upsertMessages method
        final subs = existing.subsLocal || m.subsLocal; // Preserve if either is true
        final shopping = existing.shoppingLocal || m.shoppingLocal; // Preserve if either is true
        final unsubscribed = existing.unsubscribedLocal || m.unsubscribedLocal; // Preserve if either is true
        
        // Check if any local fields need to be preserved
        bool needsUpdate = false;
        if (actDate != m.actionDate || actText != m.actionInsightText) needsUpdate = true;
        if (subs != m.subsLocal) needsUpdate = true;
        if (shopping != m.shoppingLocal) needsUpdate = true;
        if (unsubscribed != m.unsubscribedLocal) needsUpdate = true;
        
        if (needsUpdate) {
          return m.copyWith(
            actionDate: actDate,
            actionInsightText: actText,
            subsLocal: subs,
            shoppingLocal: shopping,
            unsubscribedLocal: unsubscribed,
          );
        }
      }
      return m;
    }).toList();
    
    // Persist to DB
    await _repo.upsertMessages(enriched);
    
    // Identify NEW emails (not in DB before this sync)
    final existingIds = idMap.keys.toSet();
    final newGmailMessages = gmailMessages.where((gm) => !existingIds.contains(gm.id)).toList();
    
    // Phase 1 and Phase 2 tagging on new messages for INBOX only (run in background)
    if (newGmailMessages.isNotEmpty && folderLabel == 'INBOX') {
      unawaited(_runBackgroundTaggingInSyncMessages(accountId, newGmailMessages));
    }
    
    // Save the latest historyId for future incremental syncs
    String? latestHistoryId;
    for (final gm in gmailMessages) {
      if (gm.historyId != null) {
        // Keep the maximum (latest) historyId
        if (latestHistoryId == null || 
            (int.tryParse(gm.historyId!) != null && int.tryParse(latestHistoryId) != null &&
             int.parse(gm.historyId!) > int.parse(latestHistoryId))) {
          latestHistoryId = gm.historyId;
        }
      }
    }
    if (latestHistoryId != null) {
      debugPrint('[Gmail] syncMessages saving historyId=$latestHistoryId');
      await _repo.setLastHistoryId(accountId, latestHistoryId);
    }
    
    // Return from DB filtered by folder
    final stored = await _repo.getByFolder(accountId, folderLabel);
    final totalDuration = DateTime.now().difference(syncStart);
    debugPrint('[Gmail] syncMessages completed, returned ${stored.length} messages, total time=${totalDuration.inMilliseconds}ms');
    return stored;
    // TODO: Apply action detection heuristics when implemented
  }

  Future<OriginalMessageContent?> fetchOriginalMessageContent(String accountId, String messageId) async {
    try {
      final account = await GoogleAuthService().ensureValidAccessToken(accountId);
      if (account == null || account.accessToken.isEmpty) {
        debugPrint('[Gmail] fetchOriginalMessageContent: No access token for account $accountId');
        return null;
      }

      final resp = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId?format=full'),
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
      );
      if (resp.statusCode != 200) {
        debugPrint('[Gmail] fetchOriginalMessageContent: HTTP ${resp.statusCode}');
        return null;
      }

      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final gm = GmailMessage.fromJson(map);

      String? htmlBody;
      String? plainBody;
      final inlineParts = <MapEntry<MessagePart, String>>[];
      final attachmentParts = <MessagePart>[];

      void collectFromPart(MessagePart? part) {
        if (part == null) return;
        final mimeType = part.mimeType?.toLowerCase() ?? '';
        final bodyData = part.body?.data;

        if (bodyData != null && bodyData.isNotEmpty) {
          try {
            final decoded = utf8.decode(
              base64Url.decode(bodyData.replaceAll('-', '+').replaceAll('_', '/')),
            );
            if (mimeType.contains('text/html') && htmlBody == null) {
              htmlBody = decoded;
            } else if (mimeType.contains('text/plain') && plainBody == null) {
              plainBody = decoded;
            }
          } catch (_) {
            // ignore decoding errors and continue
          }
        }

        final headers = <String, String>{};
        for (final h in part.headers) {
          headers[h.name.toLowerCase()] = h.value;
        }

        final hasAttachmentId = part.body?.attachmentId != null && part.body!.attachmentId!.isNotEmpty;
        if (hasAttachmentId) {
          final contentId = headers['content-id'];
          final disposition = headers['content-disposition']?.toLowerCase() ?? '';
          if (contentId != null && contentId.isNotEmpty && !disposition.contains('attachment')) {
            inlineParts.add(MapEntry(part, contentId.trim()));
          } else {
            attachmentParts.add(part);
          }
        }

        if (part.parts != null) {
          for (final child in part.parts!) {
            collectFromPart(child);
          }
        }
      }

      if (gm.payload?.parts != null) {
        for (final part in gm.payload!.parts!) {
          collectFromPart(part);
        }
      }

      // If payload body contains data directly (no parts)
      final payloadData = gm.payload?.body;
      if (payloadData != null && payloadData.isNotEmpty) {
        try {
          final decoded = utf8.decode(
            base64Url.decode(payloadData.replaceAll('-', '+').replaceAll('_', '/')),
          );
          final payloadMime = gm.payload?.mimeType?.toLowerCase() ?? '';
          if (payloadMime.contains('text/html') && htmlBody == null) {
            htmlBody = decoded;
          } else if (payloadMime.contains('text/plain') && plainBody == null) {
            plainBody = decoded;
          }
        } catch (_) {
          // ignore
        }
      }

      final inlineImages = <String, _InlineImage>{};
      for (final entry in inlineParts) {
        final part = entry.key;
        final cidRaw = entry.value;
        final cid = _normalizeContentId(cidRaw);
        final attachmentId = part.body?.attachmentId;
        if (attachmentId == null) continue;
        final data = await _downloadAttachmentBytes(account.accessToken, messageId, attachmentId);
        if (data == null) continue;
        final base64Data = base64Encode(data);
        final mimeType = part.mimeType ?? 'application/octet-stream';
        inlineImages[cid] = _InlineImage(mimeType: mimeType, base64Data: base64Data);
      }

      var processedHtml = htmlBody;
      if (processedHtml == null && plainBody != null) {
        processedHtml = '<pre style="white-space: pre-wrap; font-family: inherit;">${_escapeHtml(plainBody!)}'
            '</pre>';
      }
      if (processedHtml != null && inlineImages.isNotEmpty) {
        processedHtml = _embedInlineImages(processedHtml, inlineImages);
      }

      final attachments = <GmailAttachmentData>[];
      for (final part in attachmentParts) {
        final attachmentId = part.body?.attachmentId;
        if (attachmentId == null) continue;
        final data = await _downloadAttachmentBytes(account.accessToken, messageId, attachmentId);
        if (data == null) continue;
        var filename = part.filename ?? '';
        if (filename.isEmpty) {
          final headers = <String, String>{};
          for (final h in part.headers) {
            headers[h.name.toLowerCase()] = h.value;
          }
          filename = _extractFilenameFromHeaders(headers) ?? 'attachment';
        }
        final mimeType = part.mimeType ?? 'application/octet-stream';
        attachments.add(GmailAttachmentData(filename: filename, mimeType: mimeType, bytes: data));
      }

      return OriginalMessageContent(
        htmlBody: processedHtml,
        plainBody: plainBody,
        attachments: attachments,
      );
    } catch (e, stack) {
      debugPrint('[Gmail] fetchOriginalMessageContent: Error $e');
      debugPrint(stack.toString());
      return null;
    }
  }

  static const List<String> _monthShortNames = [
    'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  String _formatPossibleActionText(String? insightText, DateTime? detectedDate) {
    final trimmed = insightText?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      if (trimmed.toLowerCase().startsWith(_possibleActionPrefix.toLowerCase())) {
        return trimmed;
      }
      return '$_possibleActionPrefix$trimmed';
    }
    if (detectedDate != null) {
      final local = detectedDate.toLocal();
      final int monthIndex =
          (local.month - 1).clamp(0, _monthShortNames.length - 1);
      final month = _monthShortNames[monthIndex];
      final formatted = '${local.day} $month';
      return '$_possibleActionPrefix$formatted';
    }
    return '${_possibleActionPrefix}detected';
  }

  /// Incremental sync using Gmail History API: fetch changes since last historyId
  /// Returns list of new INBOX messages for background tagging
  Future<List<GmailMessage>> incrementalSync(String accountId) async {
    final account = await GoogleAuthService().ensureValidAccessToken(accountId);
    final accessToken = account?.accessToken;
    if (accessToken == null || accessToken.isEmpty) return [];
    final lastHistoryId = await _repo.getLastHistoryId(accountId);
    if (lastHistoryId == null) return []; // no baseline yet

    debugPrint('[Gmail] incrementalSync account=$accountId historyId=$lastHistoryId');
    final startTime = DateTime.now();
    String? pageToken;
    String? latestHistoryId;
    final gmailMessagesToTag = <GmailMessage>[];
    do {
      // Build URI with array parameters manually
      final queryParams = <String>[
        'startHistoryId=$lastHistoryId',
        'historyTypes=messageAdded',
        'historyTypes=labelAdded',
        'historyTypes=labelRemoved',
        'maxResults=100',
      ];
      if (pageToken != null) {
        queryParams.add('pageToken=$pageToken');
      }
      final uri = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/history?${queryParams.join('&')}');
      debugPrint('[Gmail] incrementalSync fetching history page, pageToken=${pageToken != null ? "exists" : "null"}');
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
      if (resp.statusCode != 200) {
        debugPrint('[Gmail] incrementalSync history API failed, statusCode=${resp.statusCode}, body=${resp.body}');
        break;
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final history = (map['history'] as List<dynamic>?) ?? [];
      debugPrint('[Gmail] incrementalSync history page received, history count=${history.length}, latestHistoryId=${map['historyId']}');
      latestHistoryId = (map['historyId']?.toString()) ?? latestHistoryId;
      int addedCount = 0;
      int labelAddedCount = 0;
      int labelRemovedCount = 0;
      debugPrint('[Gmail] incrementalSync processing ${history.length} history entries');
      int processedCount = 0;
      for (final h in history) {
        processedCount++;
        if (processedCount % 10 == 0) {
          debugPrint('[Gmail] incrementalSync processed $processedCount/${history.length} history entries');
        }
        final hist = h as Map<String, dynamic>;
        final messagesAdded = (hist['messagesAdded'] as List<dynamic>?) ?? [];
        addedCount += messagesAdded.length;
        for (final ma in messagesAdded) {
          final m = (ma as Map<String, dynamic>)['message'] as Map<String, dynamic>;
          final id = m['id'] as String;
          // Fetch full message
          final fullResp = await http.get(
            Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=full'),
            headers: {'Authorization': 'Bearer $accessToken'},
          );
                    if (fullResp.statusCode == 200) {
            final msgMap = jsonDecode(fullResp.body) as Map<String, dynamic>;   
            final gi = GmailMessage.fromJson(msgMap).toMessageIndex(accountId); 

            // Apply sender preferences before saving
            final idMap = await _repo.getByIds(accountId, [gi.id]);
            final messagesWithPrefs = await _applySenderPreferences(accountId, [gi], idMap, context: 'incrementalSync');
            await _repo.upsertMessages(messagesWithPrefs);

            // Only tag INBOX emails (use original gi for folder check, before pref application)
            if (gi.folderLabel == 'INBOX') {
              gmailMessagesToTag.add(GmailMessage.fromJson(msgMap));
            }
          }
        }
        // For labels added/removed, update only the changed fields instead of replacing entire message
        final ids = <String>{};
        for (final la in (hist['labelsAdded'] as List<dynamic>?) ?? []) {
          final msg = (la as Map<String, dynamic>)['message'] as Map<String, dynamic>;
          ids.add(msg['id'] as String);
        }
        labelAddedCount += (hist['labelsAdded'] as List<dynamic>?)?.length ?? 0;
        for (final lr in (hist['labelsRemoved'] as List<dynamic>?) ?? []) {
          final msg = (lr as Map<String, dynamic>)['message'] as Map<String, dynamic>;
          ids.add(msg['id'] as String);
        }
        labelRemovedCount += (hist['labelsRemoved'] as List<dynamic>?)?.length ?? 0;
        for (final id in ids) {
          // Fetch only metadata (not full message) to get current labels
          final metadataResp = await http.get(
            Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=metadata'),
            headers: {'Authorization': 'Bearer $accessToken'},
          );
          if (metadataResp.statusCode == 200) {
            final msgMap = jsonDecode(metadataResp.body) as Map<String, dynamic>;
            final labelIds = (msgMap['labelIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [];
            
            // Extract categories and derive flags/folder from labelIds (same logic as toMessageIndex)
            final gmailCategories = labelIds.where((label) => 
              AppConstants.allGmailCategories.contains(label)
            ).toList();
            
            // Derive flags from label IDs
            final isRead = !labelIds.contains('UNREAD');
            final isStarred = labelIds.contains('STARRED');
            final isImportant = labelIds.contains('IMPORTANT');
            
            // Determine folder from label IDs
            String folder = 'INBOX';
            if (labelIds.contains('TRASH')) {
              folder = 'TRASH';
            } else if (labelIds.contains('SPAM')) {
              folder = 'SPAM';
            } else if (labelIds.contains('SENT')) {
              folder = 'SENT';
            } else if (labelIds.contains('INBOX')) {
              folder = 'INBOX';
            } else {
              folder = 'ARCHIVE';
            }
            
            // Update only the changed fields (labels, flags, folder) without replacing entire message
            await _repo.updateMessageLabelsAndFlags(id, gmailCategories, [], isRead, isStarred, isImportant, folder);
          }
        }
      }
      pageToken = map['nextPageToken'] as String?;
      debugPrint('[Gmail] incrementalSync page processed: added=$addedCount, labelAdded=$labelAddedCount, labelRemoved=$labelRemovedCount, pageToken=${pageToken != null ? "exists" : "null"}');
    } while (pageToken != null);

    if (latestHistoryId != null) {
      debugPrint('[Gmail] incrementalSync saving latestHistoryId=$latestHistoryId');
      await _repo.setLastHistoryId(accountId, latestHistoryId);
    }
    
    final duration = DateTime.now().difference(startTime);
    debugPrint('[Gmail] incrementalSync found ${gmailMessagesToTag.length} new INBOX messages, took ${duration.inMilliseconds}ms');
    return gmailMessagesToTag;
  }

  // Apply pending Gmail modifications with retries
  // Batches operations by account to minimize token checks
  Future<void> processPendingOps() async {
    final pending = await _repo.getPendingOps(limit: 20);
    debugPrint('[Gmail] processPendingOps found ${pending.length} pending operations');
    if (pending.isEmpty) return;

    // Group operations by accountId to batch token checks
    final Map<String, List<Map<String, dynamic>>> opsByAccount = {};
    for (final op in pending) {
      final accountId = op['accountId'] as String;
      opsByAccount.putIfAbsent(accountId, () => []).add(op);
    }

    // Process each account's operations in a batch
    for (final entry in opsByAccount.entries) {
      final accountId = entry.key;
      final ops = entry.value;
      
      // Get token once for this account's batch
      final auth = GoogleAuthService();
      var account = await auth.ensureValidAccessToken(accountId);
      var accessToken = account?.accessToken;
      
      // If token check failed, attempt re-auth once
      if (accessToken == null || accessToken.isEmpty) {
        // ignore: avoid_print
        print('[gmail] attempting reauth for account=$accountId');
        account = await auth.reauthenticateAccount(accountId) ?? account;
        accessToken = account?.accessToken;
      }

      // Process all operations for this account using the same token
      // Check token validity/expiry during batch and refresh if needed
      for (final op in ops) {
        final int id = op['id'] as int;
        final String messageId = op['messageId'] as String;
        final String action = op['action'] as String;
        final int retries = (op['retries'] as int?) ?? 0;
        
        // Check if token is still valid/not expired before each operation
        if (account != null && accessToken != null && accessToken.isNotEmpty) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final isExpired = account.tokenExpiryMs != null && account.tokenExpiryMs! <= nowMs;
          final isNearExpiry = account.tokenExpiryMs != null && account.tokenExpiryMs! <= nowMs + 60000;
          
          // Refresh token if expired or near expiry (within 60 seconds)
          if (isExpired || isNearExpiry) {
            // ignore: avoid_print
            print('[gmail] token expired/near expiry during batch, refreshing account=$accountId remainingMs=${account.tokenExpiryMs != null ? (account.tokenExpiryMs! - nowMs) : -1}');
            final refreshed = await auth.ensureValidAccessToken(accountId);
            if (refreshed != null && refreshed.accessToken.isNotEmpty) {
              account = refreshed;
              accessToken = refreshed.accessToken;
            } else {
              // Refresh failed, try re-auth
              account = await auth.reauthenticateAccount(accountId) ?? account;
              accessToken = account.accessToken;
            }
          }
        }
        
        try {
          // If we have a valid token, use it directly; otherwise try individual re-auth
          if (accessToken != null && accessToken.isNotEmpty) {
            await _applyLabelChangeWithToken(accountId, messageId, action, accessToken);
            await _repo.markOpDone(id);
          } else {
            // Fallback to individual token check if batch token failed
            await _applyLabelChange(accountId, messageId, action);
            await _repo.markOpDone(id);
          }
        } catch (e) {
          // If we get a 401 or 403, the token likely expired - try refreshing once more
          bool isAuthError = false;
          if (e is _GmailApiException) {
            isAuthError = e.statusCode == 401 || e.statusCode == 403;
          } else {
            final errorStr = e.toString();
            isAuthError = errorStr.contains('401') || 
                         errorStr.contains('403') || 
                         errorStr.contains('Unauthorized') ||
                         errorStr.contains('Forbidden');
          }
          
          if (isAuthError) {
            // ignore: avoid_print
            print('[gmail] got auth error during batch, refreshing token account=$accountId error=$e');
            final refreshed = await auth.ensureValidAccessToken(accountId);
            if (refreshed != null && refreshed.accessToken.isNotEmpty) {
              account = refreshed;
              accessToken = refreshed.accessToken;
              // Retry the operation once with refreshed token
              try {
                await _applyLabelChangeWithToken(accountId, messageId, action, accessToken);
                await _repo.markOpDone(id);
                continue; // Success, skip error handling
              } catch (retryError) {
                // Retry also failed, fall through to error handling
              }
            }
          }
          
          // Minimal debug info to trace failures without noisy logs
          // ignore: avoid_print
          print('[gmail] modify failed action=$action id=$messageId retries=$retries error=$e');
          final nextRetries = retries + 1;
          await _repo.markOpAttempted(id, retries: nextRetries, when: DateTime.now());
          if (nextRetries >= 5) {
            await _repo.markOpFailed(id);
          }
        }
      }
    }
  }

  /// Apply label change with a pre-validated access token (for batched operations)
  /// Returns the HTTP status code if the request fails, for better error handling
  Future<void> _applyLabelChangeWithToken(String accountId, String messageId, String action, String accessToken) async {
    final uri = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId/modify');
    final body = _buildModifyBody(action);
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // ignore: avoid_print
      print('[gmail] modify http ${resp.statusCode}: ${resp.body}');
      // Include status code in exception for better error detection
      throw _GmailApiException('Gmail modify failed: ${resp.statusCode}', resp.statusCode);
    }
  }

  /// Apply label change with individual token check (for single operations)
  Future<void> _applyLabelChange(String accountId, String messageId, String action) async {
    final auth = GoogleAuthService();
    var account = await auth.ensureValidAccessToken(accountId);
    var accessToken = account?.accessToken;
    // ensureValidAccessToken already refreshed if needed
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('No access token');
    }

    await _applyLabelChangeWithToken(accountId, messageId, action, accessToken);
  }

  Future<void> restoreMessageToInbox(String accountId, String messageId) async {
    // ignore: avoid_print
    print('[gmail] restoreMessageToInbox account=$accountId message=$messageId');
    await _applyLabelChange(accountId, messageId, 'restore:INBOX');
  }

  Map<String, dynamic> _buildModifyBody(String action) {
    // Support meta in action like 'restore:INBOX'
    final parts = action.split(':');
    final base = parts.first;
    final meta = parts.length > 1 ? parts[1] : null;
    switch (base) {
      case 'trash':
        // Trash: add TRASH label and remove source label
        if (meta == 'SENT') return {'addLabelIds': ['TRASH'], 'removeLabelIds': ['SENT']};
        if (meta == 'SPAM') return {'addLabelIds': ['TRASH'], 'removeLabelIds': ['SPAM']};
        if (meta == 'ARCHIVE') return {'addLabelIds': ['TRASH']}; // Gmail has no ARCHIVE label
        // Default to INBOX - remove INBOX and add TRASH
        return {'addLabelIds': ['TRASH'], 'removeLabelIds': ['INBOX']};
      case 'archive':
        // Archive: only applies to INBOX and SPAM - remove the respective label
        // Cannot archive SENT or TRASH emails
        if (meta == 'SENT') return {}; // SENT emails can't be archived
        if (meta == 'TRASH') return {'removeLabelIds': ['TRASH']}; // Restore from trash
        if (meta == 'SPAM') return {'removeLabelIds': ['SPAM']};
        // Default to INBOX - remove INBOX label to archive
        return {'removeLabelIds': ['INBOX']};
      case 'restore':
        // Restore from trash: remove TRASH and add back the original label
        if (meta == 'INBOX') {
          return {'removeLabelIds': ['TRASH'], 'addLabelIds': ['INBOX']};
        }
        if (meta == 'SPAM') {
          return {'removeLabelIds': ['TRASH'], 'addLabelIds': ['SPAM']};
        }
        if (meta == 'SENT') {
          // Note: SENT might be automatically restored by Gmail, but we try to add it explicitly
          return {'removeLabelIds': ['TRASH'], 'addLabelIds': ['SENT']};
        }
        // Default: just remove TRASH
        return {'removeLabelIds': ['TRASH']};
      case 'star':
        return {'addLabelIds': ['STARRED']};
      case 'unstar':
        return {'removeLabelIds': ['STARRED']};
      case 'markRead':
        return {'removeLabelIds': ['UNREAD']};
      case 'moveToInbox':
        return {'removeLabelIds': ['SPAM'], 'addLabelIds': ['INBOX']};
      default:
        return {};
    }
  }
  
  Future<String?> _tryExtractUnsubLink(String accountId, String messageId) async {
    final account = await GoogleAuthService().ensureValidAccessToken(accountId);
    final accessToken = account?.accessToken;
    if (accessToken == null || accessToken.isEmpty) return null;
    final resp = await http.get(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId?format=full'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (resp.statusCode != 200) return null;
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final gm = GmailMessage.fromJson(map);
    // Collect HTML/plain bodies from parts tree and top-level body
    final bodies = <String>[];
    
    // Check top-level payload body first (some emails have body here, not in parts)
    // Note: MessagePayload.body is a String?, not a MessageBody object
    if (gm.payload?.body != null) {
      try {
        final mime = (gm.payload?.mimeType ?? '').toLowerCase();
        if (mime.contains('text/html') || mime.contains('text/plain')) {
          final decoded = utf8.decode(
            base64Url.decode((gm.payload!.body!).replaceAll('-', '+').replaceAll('_', '/')),
          );
          bodies.add(decoded);
        }
      } catch (_) {}
    }
    
    // Also walk parts tree
    void walkPart(MessagePart? part) {
      if (part == null) return;
      final mime = (part.mimeType ?? '').toLowerCase();
      if ((mime.contains('text/html') || mime.contains('text/plain')) && part.body?.data != null) {
        try {
          final decoded = utf8.decode(
            base64Url.decode((part.body!.data!).replaceAll('-', '+').replaceAll('_', '/')),
          );
          bodies.add(decoded);
        } catch (_) {}
      }
      if (part.parts != null) {
        for (final p in part.parts!) {
          walkPart(p);
        }
      }
    }
    if (gm.payload?.parts != null) {
      for (final p in gm.payload!.parts!) {
        walkPart(p);
      }
    }
    // Regex for unsubscribe-like links - only test for keywords in link TEXT, not URL
    // Common variations: unsubscribe, unsub, opt-out, opt out, optout, opt_out
    // We capture the actual link URL regardless of what it contains
    final patterns = [
      // mailto: links - these are legitimate unsubscribe links even if URL doesn't say "unsubscribe"
      RegExp(r'''mailto:[^\s"\'<>]*(?:unsubscribe|unsub|opt[-_]?out|optout)[^\s"\'<>]*''', caseSensitive: false),
      // Catch links where href is followed by "Unsubscribe" text inside the tag
      // Matches: <a href="tracking-url">Unsubscribe</a> or <a href="url">Unsubscribe</a>
      RegExp(r'''<a[^>]*href=["']([^"']+)["'][^>]*>(?:[^<]*<[^>]*>)*[^<]*(?:unsubscribe|unsub|opt[-_\s]?out|optout)[^<]*</a>''', caseSensitive: false),
      // Catch links where "Unsubscribe" text precedes the href
      // Matches: <a>Unsubscribe</a> with href elsewhere, or text before href
      RegExp(r'''(?:unsubscribe|unsub|opt[-_\s]?out|optout)[^<>]*?<a[^>]*href=["']([^"']+)["']''', caseSensitive: false),
      // Catch links where href and unsubscribe text are in the same tag area
      // More flexible: allows whitespace and other attributes between href and text
      RegExp(r'''<a[^>]*href=["']([^"']+)["'][^>]*>[\s\S]{0,500}?(?:unsubscribe|unsub|opt[-_\s]?out|optout)[\s\S]{0,500}?</a>''', caseSensitive: false),
      // Reverse: href followed by unsubscribe text (within reasonable distance)
      RegExp(r'''href=["']([^"']+)["'][^>]*>[\s\S]{0,500}?(?:unsubscribe|unsub|opt[-_\s]?out|optout)''', caseSensitive: false),
    ];
    
    for (final body in bodies) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(body);
        if (match != null) {
          // Use group(1) if it exists (capturing group), otherwise use group(0) (full match)
          // Some patterns have capturing groups, others don't
          String? link;
          if (match.groupCount >= 1) {
            try {
              link = match.group(1);
            } catch (e) {
              // group(1) doesn't exist, fall back to full match
              link = match.group(0);
            }
          } else {
            link = match.group(0);
          }
          if (link != null && link.isNotEmpty) {
            debugPrint('[Phase2] Found unsubscribe link: $link');
            // Decode HTML entities if needed
            return link
                .replaceAll('&amp;', '&')
                .replaceAll('&lt;', '<')
                .replaceAll('&gt;', '>')
                .replaceAll('&quot;', '"')
                .replaceAll('&#39;', "'");
          }
        }
      }
    }
    debugPrint('[Phase2] No unsubscribe link found in email body');
    return null;
  }

  Future<void> phase1Tagging(String accountId, List<GmailMessage> gmailMessages) async {
    // Lightweight: headers-only to avoid slowing load
    // Phase 1 tagging: checks email header and sets subs local tag if subscription email
    // Also checks for shopping category from labelIds
    // This happens only once when new email arrives
    debugPrint('[Phase1] Testing ${gmailMessages.length} messages for subscription headers and shopping');
    for (final gm in gmailMessages) {
      final headers = gm.payload?.headers ?? [];
      final subject = headers.firstWhere((h) => h.name.toLowerCase() == 'subject', orElse: () => const MessageHeader(name: '', value: '')).value;
      
      final hasListHeader = headers.any((h) {
        final name = h.name.toLowerCase();
        return name == 'list-unsubscribe' || name == 'list-id';
      });
      if (hasListHeader) {
        // Extract a usable unsubscribe link from List-Unsubscribe header if present
        final unsubLink = _extractUnsubFromHeader(headers);
        await _repo.updateLocalClassification(gm.id, subs: true, unsubLink: unsubLink);
        debugPrint('[Phase1] ✓ SUBSCRIPTION: subject="$subject" -> detected (List-* header)');
      } else {
        debugPrint('[Phase1] ✗ NO SUBSCRIPTION: subject="$subject" -> no headers');
      }
      
      // Check for shopping category
      final hasShopping = gm.labelIds.contains('CATEGORY_PURCHASES');
      if (hasShopping) {
        await _repo.updateLocalClassification(gm.id, shopping: true);
        debugPrint('[Phase1] ✓ SHOPPING: subject="$subject" -> CATEGORY_PURCHASES');
      } else {
        debugPrint('[Phase1] ✗ NO SHOPPING: subject="$subject"');
      }
    }
  }
  
  Future<void> phase2TaggingNewMessages(String accountId, List<GmailMessage> gmailMessages, {VoidCallback? onComplete}) async {
    // Phase 2 tagging: performs extra checks on emails that DO NOT have the subs tag already set
    // Also performs action detection with deeper body-based analysis
    debugPrint('[Phase2] Testing ${gmailMessages.length} messages for subscriptions and actions');
    
    // First check existing messages in DB to see which ones already have subs tag from phase 1 or action from previous run
    final messageIds = gmailMessages.map((gm) => gm.id).toList();
    final existingMessages = await _repo.getByIds(accountId, messageIds);
    
    for (final gm in gmailMessages) {
      final existing = existingMessages[gm.id];
      
      final headers = gm.payload?.headers ?? [];
      final subject = headers.firstWhere((h) => h.name.toLowerCase() == 'subject', orElse: () => const MessageHeader(name: '', value: '')).value;
      final subj = subject.toLowerCase();
      final from = headers.firstWhere((h) => h.name.toLowerCase() == 'from', orElse: () => const MessageHeader(name: '', value: '')).value.toLowerCase();
      final snippet = gm.snippet ?? '';
      
      // === SUBSCRIPTION DETECTION ===
      // Skip if email already has subs tag from phase 1
      if (existing == null || !existing.subsLocal) {
        final cats = gm.labelIds.map((e) => e.toLowerCase()).toList();
        
        // Phase 2: Simple heuristic checks to see if email might be a subs email
        final subscriptionKeywords = ['newsletter', 'news', 'digest', 'alert', 'update', 'weekly', 'daily', 'monthly'];
        final hasSubscriptionKeyword = subscriptionKeywords.any((keyword) => subj.contains(keyword));
        
        final isSubsCandidate = cats.any((c) => c.contains('forum') || c.contains('update')) || 
                               subj.contains('unsubscribe') || 
                               hasSubscriptionKeyword ||
                               from.contains('noreply');
        
        // If email looks like a subs email, perform deeper checks
        if (isSubsCandidate) {
          // Download the email body
          final unsubLink = await _tryExtractUnsubLink(accountId, gm.id);
          
          // Tag as subscription ONLY if unsubscribe link is found
          if (unsubLink != null && unsubLink.isNotEmpty) {
            await _repo.updateLocalClassification(gm.id, subs: true, unsubLink: unsubLink);
            debugPrint('[Phase2] ✓ SUBSCRIPTION: subject="$subject" -> detected (heuristic + unsubLink)');
          } else {
            debugPrint('[Phase2] ✗ NO SUBSCRIPTION: subject="$subject" -> candidate but no unsubLink');
          }
        }
      } else {
        debugPrint('[Phase2] - SKIP SUBSCRIPTION: subject="$subject" -> already tagged');
      }
      
      // === ACTION DETECTION ===
      // Skip if email already has an action (don't overwrite user edits)
      if (existing == null || !existing.hasAction) {
        // Quick check: is this an action candidate? (lightweight, no body download)
        final isActionCandidate = ActionExtractor.isActionCandidate(subj, snippet);
        
        if (isActionCandidate) {
          // Quick detection on subject/snippet first (low confidence)
          final quickResult = ActionExtractor.detectQuick(subj, snippet);
          
          if (quickResult != null) {
            // Download email body for deeper detection (higher confidence)
            final bodyContent = await _downloadEmailBody(accountId, gm.id);
            
            if (bodyContent != null && bodyContent.isNotEmpty) {
              // Deep detection with full body content
              final deepResult = ActionExtractor.detectWithBody(subj, snippet, bodyContent);
              
              if (deepResult != null && deepResult.confidence >= 0.6) {
                // Use deep result if confidence is high enough
                await _repo.updateAction(
                  gm.id,
                  null,
                  _formatPossibleActionText(deepResult.insightText, deepResult.actionDate),
                  deepResult.confidence,
                );
                debugPrint('[Phase2] ✓ ACTION: subject="$subject" -> deep (${deepResult.actionDate.toLocal().toString().split(' ')[0]}, conf=${deepResult.confidence})');
              } else if (quickResult.confidence >= 0.5) {
                // Fall back to quick result if deep detection didn't improve confidence
                await _repo.updateAction(
                  gm.id,
                  null,
                  _formatPossibleActionText(quickResult.insightText, quickResult.actionDate),
                  quickResult.confidence,
                );
                debugPrint('[Phase2] ✓ ACTION: subject="$subject" -> quick (${quickResult.actionDate.toLocal().toString().split(' ')[0]}, conf=${quickResult.confidence})');
              } else {
                debugPrint('[Phase2] ✗ NO ACTION: subject="$subject" -> confidence too low (deep=${deepResult?.confidence ?? 0.0}, quick=${quickResult.confidence})');
              }
            } else if (quickResult.confidence >= 0.5) {
              // If body download fails, use quick result
              await _repo.updateAction(
                gm.id,
                null,
                _formatPossibleActionText(quickResult.insightText, quickResult.actionDate),
                quickResult.confidence,
              );
              debugPrint('[Phase2] ✓ ACTION: subject="$subject" -> quick (${quickResult.actionDate.toLocal().toString().split(' ')[0]}, conf=${quickResult.confidence}) body failed');
            } else {
              debugPrint('[Phase2] ✗ NO ACTION: subject="$subject" -> body failed, confidence too low (${quickResult.confidence})');
            }
          } else {
            debugPrint('[Phase2] ✗ NO ACTION: subject="$subject" -> quick detection null');
          }
        } else {
          debugPrint('[Phase2] ✗ NO ACTION: subject="$subject" -> not a candidate');
        }
      } else {
        debugPrint('[Phase2] - SKIP ACTION: subject="$subject" -> already has action');
      }
    }
    
    debugPrint('[Phase2] Testing completed');
    
    // Notify completion callback to reload email list
    if (onComplete != null) {
      onComplete();
    }
  }
  
  /// Download email body content (HTML and plain text combined)
  Future<String?> _downloadEmailBody(String accountId, String messageId) async {
    final account = await GoogleAuthService().ensureValidAccessToken(accountId);
    final accessToken = account?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('[Phase2] Body download failed for $messageId: no access token');
      return null;
    }
    
    final resp = await http.get(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId?format=full'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (resp.statusCode != 200) {
      debugPrint('[Phase2] Body download failed for $messageId: HTTP ${resp.statusCode}');
      return null;
    }
    
    try {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final gm = GmailMessage.fromJson(map);
      
      // Collect HTML/plain bodies from parts tree
      final bodies = <String>[];
      void walkPart(MessagePart? part) {
        if (part == null) return;
        final mime = (part.mimeType ?? '').toLowerCase();
        if ((mime.contains('text/html') || mime.contains('text/plain')) && part.body?.data != null) {
          try {
            final decoded = utf8.decode(
              base64Url.decode((part.body!.data!).replaceAll('-', '+').replaceAll('_', '/')),
            );
            bodies.add(decoded);
          } catch (e) {
            debugPrint('[Phase2] Failed to decode body part for $messageId: $e');
          }
        }
        if (part.parts != null) {
          for (final p in part.parts!) {
            walkPart(p);
          }
        }
      }
      
      // Check if payload itself has body data (MessagePayload.body is a String, not MessageBody)
      if (gm.payload?.body != null && gm.payload!.body!.isNotEmpty) {
        try {
          final decoded = utf8.decode(
            base64Url.decode((gm.payload!.body!).replaceAll('-', '+').replaceAll('_', '/')),
          );
          bodies.add(decoded);
        } catch (e) {
          debugPrint('[Phase2] Failed to decode payload body for $messageId: $e');
        }
      }
      
      if (gm.payload?.parts != null) {
        for (final p in gm.payload!.parts!) {
          walkPart(p);
        }
      }
      
      if (bodies.isEmpty) {
        debugPrint('[Phase2] Body download for $messageId: no body content found in parts');
        return null;
      }
      
      return bodies.join(' ');
    } catch (e) {
      debugPrint('[Phase2] Body download failed for $messageId: parse error $e');
      return null;
    }
  }


  String? _extractUnsubFromHeader(List<MessageHeader> headers) {
    final header = headers.firstWhere(
      (h) => h.name.toLowerCase() == 'list-unsubscribe',
      orElse: () => const MessageHeader(name: '', value: ''),
    );
    if (header.value.isEmpty) return null;
    // Header format often: "<mailto:...>, <https://...>"
    final raw = header.value.replaceAll('\r', '').replaceAll('\n', '');
    // Split on commas, strip angle brackets and whitespace
    final parts = raw
        .split(',')
        .map((s) => s.replaceAll('<', '').replaceAll('>', '').replaceAll(' ', '').replaceAll('\t', ''))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    // Prefer mailto link for true auto-unsubscribe; else https
    final mailto = parts.firstWhere(
      (p) => p.toLowerCase().startsWith('mailto:'),
      orElse: () => '',
    );
    if (mailto.isNotEmpty) {
      // ignore: avoid_print
      print('[subs] header mailto=$mailto');
      return mailto;
    }
    final https = parts.firstWhere(
      (p) => p.toLowerCase().startsWith('http'),
      orElse: () => '',
    );
    final chosen = https.isNotEmpty ? https : parts.first;
    // ignore: avoid_print
    print('[subs] header chosen=$chosen');
    return chosen;
  }

  /// Apply sender preferences to messages (auto-apply local tag)
  /// Preserves existing tags if message already has one locally
  Future<List<MessageIndex>> _applySenderPreferences(
    String accountId,
    List<MessageIndex> messageIndexes,
    Map<String, MessageIndex> idMap, {
    required String context,
  }) async {
    final senderPrefs = await _repo.getAllSenderPrefs();
    debugPrint('[SenderPrefs] $context: applying sender prefs to ${messageIndexes.length} messages');
    
    int preservedCount = 0;
    int appliedCount = 0;
    int noPrefCount = 0;
    
    final result = <MessageIndex>[];
    for (var i = 0; i < messageIndexes.length; i++) {
      final m = messageIndexes[i];
      final existing = idMap[m.id];
      
      // If message exists locally and already has a tag, preserve it
      final existingTag = existing?.localTagPersonal;
      if (existingTag != null && existingTag.isNotEmpty) {
        // Preserve existing tag
        result.add(m.copyWith(localTagPersonal: existingTag));
        preservedCount++;
        debugPrint('[SenderPrefs] $context: messageId=${m.id} subject="${m.subject}" preserved existing tag=$existingTag');
      } else {
        // New message or no existing tag - apply sender preference
        final email = _extractEmail(m.from);
        debugPrint('[SenderPrefs] $context: messageId=${m.id} subject="${m.subject}" from="$email" (extracted from "${m.from}")');
        final pref = senderPrefs[email];
        if (pref != null && pref.isNotEmpty) {
          result.add(m.copyWith(localTagPersonal: pref));
          appliedCount++;
          debugPrint('[SenderPrefs] $context: messageId=${m.id} APPLIED tag=$pref from sender preference');
        } else {
          result.add(m);
          noPrefCount++;
          debugPrint('[SenderPrefs] $context: messageId=${m.id} NO PREF found for email=$email');
        }
      }
    }

    debugPrint('[SenderPrefs] $context: summary - preserved=$preservedCount, applied=$appliedCount, noPref=$noPrefCount');
    return result;
  }

  String _extractEmail(String from) {
    final regex = RegExp(r'<([^>]+)>');
    final match = regex.firstMatch(from);
    if (match != null) return match.group(1)!.trim();
    if (from.contains('@')) return from.trim();
    return '';
  }

  Future<ReplyContext?> fetchReplyContext(String accountId, String messageId) async {
    try {
      final account = await GoogleAuthService().ensureValidAccessToken(accountId);
      final accessToken = account?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('[Gmail] fetchReplyContext: No access token for account $accountId');
        return null;
      }

      final uri = Uri.parse(
        'https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId'
        '?format=metadata&metadataHeaders=Message-ID&metadataHeaders=References',
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (resp.statusCode != 200) {
        debugPrint('[Gmail] fetchReplyContext: HTTP ${resp.statusCode} ${resp.body}');
        return null;
      }

      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final payload = map['payload'] as Map<String, dynamic>?;
      final headersJson = payload?['headers'] as List<dynamic>? ?? const [];
      String? messageIdHeader;
      List<String> references = [];

      for (final header in headersJson) {
        final h = MessageHeader.fromJson(header as Map<String, dynamic>);
        final name = h.name.toLowerCase();
        if (name == 'message-id') {
          messageIdHeader = h.value.trim();
        } else if (name == 'references') {
          references = h.value
              .split(RegExp(r'[\s]+'))
              .map((entry) => entry.trim())
              .where((entry) => entry.isNotEmpty)
              .toList();
        }
      }

      return ReplyContext(
        messageIdHeader: messageIdHeader,
        references: references,
      );
    } catch (e) {
      debugPrint('[Gmail] fetchReplyContext: Error $e');
      return null;
    }
  }

  Future<Uint8List?> _downloadAttachmentBytes(String accessToken, String messageId, String attachmentId) async {
    try {
      final resp = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId/attachments/$attachmentId'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (resp.statusCode != 200) {
        debugPrint('[Gmail] _downloadAttachmentBytes: HTTP ${resp.statusCode}');
        return null;
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = map['data'] as String?;
      if (data == null) return null;
      final normalized = data.replaceAll('-', '+').replaceAll('_', '/');
      return base64Decode(normalized);
    } catch (e) {
      debugPrint('[Gmail] _downloadAttachmentBytes: Error $e');
      return null;
    }
  }

  String _normalizeContentId(String cid) {
    var normalized = cid.trim();
    if (normalized.startsWith('<') && normalized.endsWith('>')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized;
  }

  String _embedInlineImages(String html, Map<String, _InlineImage> inlineImages) {
    var processed = html;
    inlineImages.forEach((cid, image) {
      final pattern = RegExp('cid:${RegExp.escape(cid)}', caseSensitive: false);
      processed = processed.replaceAll(
        pattern,
        'data:${image.mimeType};base64,${image.base64Data}',
      );
    });
    return processed;
  }

  String? _extractFilenameFromHeaders(Map<String, String> headers) {
    final disposition = headers['content-disposition'] ?? '';
    final contentType = headers['content-type'] ?? '';
    final filenameMatch = RegExp(r'''filename\*?=("?)([^";\r\n]+)\1''', caseSensitive: false).firstMatch(disposition);
    if (filenameMatch != null) {
      return filenameMatch.group(2)?.trim();
    }
    final nameMatch = RegExp(r'''name\*?=("?)([^";\r\n]+)\1''', caseSensitive: false).firstMatch(contentType);
    if (nameMatch != null) {
      return nameMatch.group(2)?.trim();
    }
    return null;
  }

  /// Send an email via Gmail API
  /// [to] can be comma-separated for multiple recipients
  /// [cc] and [bcc] are optional and can be comma-separated
  /// [replyTo] is optional message ID for replies
  /// [attachments] is a list of File objects to attach
  Future<bool> sendEmail(
    String accountId, {
    required String to,
    required String subject,
    required String body,
    String? htmlBody,
    String? cc,
    String? bcc,
    String? replyTo,
    String? inReplyTo,
    List<String>? references,
    List<File>? attachments,
    List<GmailAttachmentData>? forwardedAttachments,
    String? threadId,
  }) async {
    try {
      final account = await GoogleAuthService().ensureValidAccessToken(accountId);
      if (account == null) {
        debugPrint('[Gmail] sendEmail: No account found for accountId $accountId');
        return false;
      }
      final accessToken = account.accessToken;
      if (accessToken.isEmpty) {
        debugPrint('[Gmail] sendEmail: No access token for account $accountId');
        return false;
      }

      final senderEmail = account.email;
      final rawMessage = StringBuffer();

      final expandedAttachments = <GmailAttachmentData>[];
      if (attachments != null && attachments.isNotEmpty) {
        for (final file in attachments) {
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          final filename = file.path.split(Platform.pathSeparator).last;
          final mimeType = _determineMimeType(filename);
          expandedAttachments.add(
            GmailAttachmentData(filename: filename, mimeType: mimeType, bytes: bytes),
          );
        }
      }
      if (forwardedAttachments != null && forwardedAttachments.isNotEmpty) {
        expandedAttachments.addAll(forwardedAttachments);
      }
      final hasHtml = htmlBody != null && htmlBody.trim().isNotEmpty;

      rawMessage.writeln('From: $senderEmail');
      rawMessage.writeln('To: $to');
      if (cc != null && cc.trim().isNotEmpty) {
        rawMessage.writeln('Cc: $cc');
      }
      if (bcc != null && bcc.trim().isNotEmpty) {
        rawMessage.writeln('Bcc: $bcc');
      }
      if (replyTo != null && replyTo.trim().isNotEmpty) {
        rawMessage.writeln('Reply-To: $replyTo');
      }
      rawMessage.writeln('Subject: $subject');

      if (inReplyTo != null) {
        rawMessage.writeln('In-Reply-To: $inReplyTo');
      }
      if (references != null && references.isNotEmpty) {
        rawMessage.writeln('References: ${references.join(' ')}');
      }

      final mimeBody = _buildMimeBody(
        plainBody: body,
        htmlBody: htmlBody,
        attachments: expandedAttachments,
        hasHtml: hasHtml,
      );
      rawMessage.write(mimeBody);

      final rawBase64Url = base64UrlEncode(utf8.encode(rawMessage.toString()))
          .replaceAll('=', '');

      final payload = <String, dynamic>{
        'raw': rawBase64Url,
      };
      if (threadId != null && threadId.isNotEmpty) {
        payload['threadId'] = threadId;
      }

      final resp = await http.post(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/send'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        debugPrint('[Gmail] sendEmail: Successfully sent email to=$to subject=$subject');
        return true;
      } else {
        debugPrint('[Gmail] sendEmail: Failed ${resp.statusCode}: ${resp.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[Gmail] sendEmail: Error: $e');
      return false;
    }
  }

  String _determineMimeType(String filename) {
    final extension = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'txt':
        return 'text/plain';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }

  String _buildMimeBody({
    required String plainBody,
    String? htmlBody,
    required List<GmailAttachmentData> attachments,
    required bool hasHtml,
  }) {
    final hasAttachments = attachments.isNotEmpty;
    final trimmedHtml = hasHtml ? (htmlBody ?? '').trim() : null;

    if (!hasAttachments && (!hasHtml || trimmedHtml == null || trimmedHtml.isEmpty)) {
      final buffer = StringBuffer();
      buffer.writeln('Content-Type: text/plain; charset=UTF-8');
      buffer.writeln('Content-Transfer-Encoding: 7bit');
      buffer.writeln('');
      buffer.writeln(plainBody);
      return buffer.toString();
    }

    if (!hasAttachments && trimmedHtml != null && trimmedHtml.isNotEmpty) {
      final boundaryAlt = _generateBoundary();
      final buffer = StringBuffer();
      buffer.writeln('MIME-Version: 1.0');
      buffer.writeln('Content-Type: multipart/alternative; boundary="$boundaryAlt"');
      buffer.writeln('');
      buffer.writeln('--$boundaryAlt');
      buffer.writeln('Content-Type: text/plain; charset=UTF-8');
      buffer.writeln('Content-Transfer-Encoding: 7bit');
      buffer.writeln('');
      buffer.writeln(plainBody);
      buffer.writeln('');
      buffer.writeln('--$boundaryAlt');
      buffer.writeln('Content-Type: text/html; charset=UTF-8');
      buffer.writeln('Content-Transfer-Encoding: 7bit');
      buffer.writeln('');
      buffer.writeln(trimmedHtml);
      buffer.writeln('');
      buffer.writeln('--$boundaryAlt--');
      return buffer.toString();
    }

    final buffer = StringBuffer();
    final boundaryMixed = _generateBoundary();
    buffer.writeln('MIME-Version: 1.0');
    buffer.writeln('Content-Type: multipart/mixed; boundary="$boundaryMixed"');
    buffer.writeln('');
    buffer.writeln('This is a multi-part message in MIME format.');
    buffer.writeln('');

    if (trimmedHtml != null && trimmedHtml.isNotEmpty) {
      final boundaryAlt = _generateBoundary();
      buffer.writeln('--$boundaryMixed');
      buffer.writeln('Content-Type: multipart/alternative; boundary="$boundaryAlt"');
      buffer.writeln('');
      buffer.writeln('--$boundaryAlt');
      buffer.writeln('Content-Type: text/plain; charset=UTF-8');
      buffer.writeln('Content-Transfer-Encoding: 7bit');
      buffer.writeln('');
      buffer.writeln(plainBody);
      buffer.writeln('');
      buffer.writeln('--$boundaryAlt');
      buffer.writeln('Content-Type: text/html; charset=UTF-8');
      buffer.writeln('Content-Transfer-Encoding: 7bit');
      buffer.writeln('');
      buffer.writeln(trimmedHtml);
      buffer.writeln('');
      buffer.writeln('--$boundaryAlt--');
      buffer.writeln('');
    } else {
      buffer.writeln('--$boundaryMixed');
      buffer.writeln('Content-Type: text/plain; charset=UTF-8');
      buffer.writeln('Content-Transfer-Encoding: 7bit');
      buffer.writeln('');
      buffer.writeln(plainBody);
      buffer.writeln('');
    }

    for (final attachment in attachments) {
      final base64Data = base64Encode(attachment.bytes);
      buffer.writeln('--$boundaryMixed');
      buffer.writeln('Content-Type: ${attachment.mimeType}; name="${attachment.filename}"');
      buffer.writeln('Content-Disposition: attachment; filename="${attachment.filename}"');
      buffer.writeln('Content-Transfer-Encoding: base64');
      buffer.writeln('');
      buffer.writeln(_chunkBase64(base64Data));
      buffer.writeln('');
    }

    buffer.writeln('--$boundaryMixed--');
    return buffer.toString();
  }

  String _generateBoundary() {
    final now = DateTime.now();
    return '----=_Part_${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch}';
  }

  String _chunkBase64(String data, {int chunkSize = 76}) {
    final buffer = StringBuffer();
    for (var i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize) < data.length ? i + chunkSize : data.length;
      buffer.writeln(data.substring(i, end));
    }
    return buffer.toString();
  }

  /// Send an auto-unsubscribe mail when List-Unsubscribe provides a mailto: link
  Future<bool> sendUnsubscribeMailto(String accountId, String mailtoUrl) async {
    try {
      final uri = Uri.parse(mailtoUrl);
      if (uri.scheme.toLowerCase() != 'mailto') return false;
      final to = uri.path;
      final subject = uri.queryParameters['subject'] ?? 'Unsubscribe';
      final body = uri.queryParameters['body'] ?? 'Please unsubscribe me from this mailing list.';

      final account = await GoogleAuthService().ensureValidAccessToken(accountId);
      final accessToken = account?.accessToken;
      if (accessToken == null || accessToken.isEmpty) return false;

      final rawMessage = StringBuffer()
        ..writeln('To: $to')
        ..writeln('Subject: $subject')
        ..writeln('Content-Type: text/plain; charset=UTF-8')
        ..writeln('')
        ..writeln(body);

      final rawBase64Url = base64UrlEncode(utf8.encode(rawMessage.toString()))
          .replaceAll('=', '');

      final resp = await http.post(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/send'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'raw': rawBase64Url}),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // ignore: avoid_print
        print('[subs] mailto sent to=$to');
        return true;
      } else {
        // ignore: avoid_print
        print('[subs] mailto send failed ${resp.statusCode}: ${resp.body}');
        return false;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[subs] mailto send error: $e');
      return false;
    }
  }

  /// Fetch full message and extract all attachment filenames
  Future<List<String>> getAttachmentFilenames(String accountId, String messageId) async {
    final account = await GoogleAuthService().ensureValidAccessToken(accountId);
    final accessToken = account?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('[Attachments] No access token for account $accountId');
      return [];
    }
    
    final resp = await http.get(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId?format=full'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (resp.statusCode != 200) {
      debugPrint('[Attachments] Failed to fetch message $messageId: ${resp.statusCode}');
      return [];
    }
    
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final gm = GmailMessage.fromJson(map);
    final filenames = _extractAttachmentFilenames(gm.payload);
    final subject = gm.payload?.headers.firstWhere((h) => h.name.toLowerCase() == 'subject', orElse: () => const MessageHeader(name: '', value: '')).value ?? 'unknown';
    if (filenames.isNotEmpty) {
      debugPrint('[Attachments] ✓ VERIFIED: subject="$subject" -> ${filenames.length} real attachments: $filenames');
    } else {
      debugPrint('[Attachments] ✗ NO ATTACHMENTS: subject="$subject" -> no real attachments (filtered out)');
    }
    return filenames;
  }

  /// Recursively extract all attachment filenames from message payload
  List<String> _extractAttachmentFilenames(MessagePayload? payload) {
    if (payload == null) return [];
    
    final filenames = <String>[];
    
    // Check if payload itself is an attachment (matches _hasAttachments logic)
    // Exclude text/html and text/plain as they're message content
    final payloadMimeType = payload.mimeType?.toLowerCase() ?? '';
    if (payload.filename != null && 
        payload.filename!.isNotEmpty && 
        payloadMimeType != 'text/html' && 
        payloadMimeType != 'text/plain') {
      filenames.add(payload.filename!);
    }
    
    // Recursively check parts (matches _hasAttachments recursive logic)
    if (payload.parts != null) {
      for (final part in payload.parts!) {
        filenames.addAll(_extractPartAttachmentFilenames(part));
      }
    }
    
    return filenames;
  }

  /// Recursively extract attachment filenames from a message part
  List<String> _extractPartAttachmentFilenames(MessagePart part) {
    final filenames = <String>[];
    
    debugPrint('[Attachments] Checking part: filename=${part.filename}, mimeType=${part.mimeType}, hasAttachmentId=${part.body?.attachmentId != null}');
    
    // Skip if this is not a real attachment (exclude inline images, favicons, etc.)
    if (!_isRealAttachment(part)) {
      debugPrint('[Attachments] Part filtered out, checking nested parts');
      // Still check nested parts recursively
      if (part.parts != null) {
        for (final nestedPart in part.parts!) {
          filenames.addAll(_extractPartAttachmentFilenames(nestedPart));
        }
      }
      return filenames;
    }
    
    debugPrint('[Attachments] Part passed filter check');
    
    // Check if this part is an attachment (matches _hasAttachments logic first)
    // Primary check: has filename (same as _hasAttachments uses)
    if (part.filename != null && part.filename!.isNotEmpty) {
      filenames.add(part.filename!);
    }
    
    // Also check for attachmentId in body (Gmail API indicator for attachments)
    final hasAttachmentId = part.body?.attachmentId != null && part.body!.attachmentId!.isNotEmpty;
    if (hasAttachmentId && (part.filename == null || part.filename!.isEmpty)) {
      // Has attachmentId but no filename - try to get filename from headers
      String? filename;
      
      // Check Content-Disposition header for filename
      final contentDisposition = part.headers.firstWhere(
        (h) => h.name.toLowerCase() == 'content-disposition',
        orElse: () => const MessageHeader(name: '', value: ''),
      );
      if (contentDisposition.value.isNotEmpty) {
        // Match filename=value or filename="value" or filename='value'
        final filenameMatch = RegExp(r'''filename[^=]*=\s*["']?([^"'\r\n]+)["']?''', caseSensitive: false)
            .firstMatch(contentDisposition.value);
        if (filenameMatch != null) {
          filename = filenameMatch.group(1)?.trim();
        }
      }
      
      // Check Content-Type header for name parameter
      if (filename == null || filename.isEmpty) {
        final contentType = part.headers.firstWhere(
          (h) => h.name.toLowerCase() == 'content-type',
          orElse: () => const MessageHeader(name: '', value: ''),
        );
        if (contentType.value.isNotEmpty) {
          // Match name=value or name="value" or name='value'
          final nameMatch = RegExp(r'''name[^=]*=\s*["']?([^"'\r\n]+)["']?''', caseSensitive: false)
              .firstMatch(contentType.value);
          if (nameMatch != null) {
            filename = nameMatch.group(1)?.trim();
          }
        }
      }
      
      // Use mimeType-based default if still no filename
      filename ??= part.mimeType?.split('/').last ?? 'attachment';
      if (filename.isNotEmpty) {
        filenames.add(filename);
      }
    }
    
    // Recursively check nested parts (matches _hasAttachments recursive logic)
    if (part.parts != null) {
      for (final nestedPart in part.parts!) {
        filenames.addAll(_extractPartAttachmentFilenames(nestedPart));
      }
    }
    
    return filenames;
  }

  /// Check if a part is a real attachment (not inline image, favicon, etc.)
  /// Based on reference implementation: must have attachmentId, exclude inline/Content-ID, exclude images
  bool _isRealAttachment(MessagePart part) {
    // Must have attachmentId — this marks it as an actual attachment part
    final hasAttachmentId = part.body?.attachmentId != null && part.body!.attachmentId!.isNotEmpty;
    if (!hasAttachmentId) {
      return false;
    }
    
    // Build header map for easier lookup
    final headers = <String, String>{};
    for (final h in part.headers) {
      headers[h.name.toLowerCase()] = h.value;
    }
    
    final disp = headers['content-disposition'] ?? '';
    final cid = headers['content-id'] ?? '';
    final mimeType = part.mimeType?.toLowerCase() ?? '';
    
    debugPrint('[Attachments] Checking: filename=${part.filename}, mimeType=$mimeType, disp=$disp, cid=$cid');
    
    // Skip inline parts (logos, icons, etc.)
    // But allow if explicitly marked as attachment (Content-Disposition: attachment)
    final dispLower = disp.toLowerCase();
    if (dispLower.contains('inline') && !dispLower.contains('attachment')) {
      debugPrint('[Attachments] Excluding inline part: ${part.filename} (disposition: $disp)');
      return false;
    }
    
    // Skip if has Content-ID (inline images)
    if (cid.isNotEmpty) {
      debugPrint('[Attachments] Excluding Content-ID part: ${part.filename}');
      return false;
    }
    
    // Skip image/* types (unless explicitly marked as attachment)
    if (mimeType.startsWith('image/')) {
      // Only include images if explicitly marked as attachment
      if (dispLower.contains('attachment')) {
        debugPrint('[Attachments] Including image marked as attachment: ${part.filename}');
        return true;
      }
      debugPrint('[Attachments] Excluding image type: ${part.filename}');
      return false;
    }
    
    // Determine the filename
    var realFilename = part.filename ?? '';
    if (realFilename.isEmpty) {
      // Try to extract from Content-Disposition header
      final matchFilename = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(disp);
      if (matchFilename != null) {
        realFilename = matchFilename.group(1)!.trim();
      } else {
        // Try Content-Type header
        final contentType = headers['content-type'] ?? '';
        final matchName = RegExp(r'name="?([^";]+)"?', caseSensitive: false).firstMatch(contentType);
        if (matchName != null) {
          realFilename = matchName.group(1)!.trim();
        }
      }
    }
    
    // Must have filename to be considered an attachment
    if (realFilename.isEmpty) {
      return false;
    }
    
    debugPrint('[Attachments] Including attachment: $realFilename ($mimeType)');
    return true;
  }

  /// Get full email body as HTML document (similar to email viewer)
  /// Returns complete HTML with styling for saving to local files
  Future<String?> getEmailBody(String messageId, String accessToken) async {
    try {
      final resp = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId?format=full'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (resp.statusCode != 200) {
        debugPrint('[GmailSyncService] Failed to get email body: ${resp.statusCode}');
        return null;
      }

      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final payload = map['payload'] as Map<String, dynamic>?;
      
      String? htmlBody;
      String? plainBody;
      final headers = (payload?['headers'] as List<dynamic>?) ?? [];
      
      // Extract From, To, Subject from headers
      String from = '';
      String to = '';
      String subject = '';
      for (final h in headers) {
        final header = h as Map<String, dynamic>;
        final name = (header['name'] as String? ?? '').toLowerCase();
        final value = header['value'] as String? ?? '';
        if (name == 'from') from = value;
        if (name == 'to') to = value;
        if (name == 'subject') subject = value;
      }
      
      // Extract date
      final internalDate = map['internalDate'];
      final dateMs = internalDate is String ? int.tryParse(internalDate) ?? 0 : (internalDate is int ? internalDate : 0);
      final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
      
      // Walk through the payload structure to find HTML and plain text parts
      void extractBody(dynamic part) {
        if (part is! Map<String, dynamic>) return;
        
        final mimeType = (part['mimeType'] as String? ?? '').toLowerCase();
        final body = part['body'] as Map<String, dynamic>?;
        final data = body?['data'] as String?;
        
        if (data != null) {
          try {
            final decoded = utf8.decode(
              base64Url.decode(data.replaceAll('-', '+').replaceAll('_', '/')),
            );
            if (mimeType.contains('text/html')) {
              htmlBody = decoded;
            } else if (mimeType.contains('text/plain')) {
              plainBody = decoded;
            }
          } catch (e) {
            // Continue to next part
          }
        }
        
        // Recursively check nested parts
        final parts = part['parts'] as List<dynamic>?;
        if (parts != null) {
          for (final p in parts) {
            extractBody(p);
          }
        }
      }

      extractBody(payload ?? {});

      // Prefer HTML over plain text
      final bodyContent = htmlBody ?? plainBody ?? '';
      final bodyHtml = htmlBody != null 
          ? bodyContent 
          : '<pre style="white-space: pre-wrap; font-family: inherit;">${_escapeHtml(bodyContent)}</pre>';

      // Create a complete HTML document
      final fullHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      margin: 0;
      padding: 16px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      font-size: 14px;
      line-height: 1.5;
      color: #1a1a1a;
      background-color: #ffffff;
    }
    .email-header {
      border-bottom: 1px solid #e0e0e0;
      padding-bottom: 16px;
      margin-bottom: 16px;
    }
    .email-header h2 {
      margin: 0 0 8px 0;
      font-size: 20px;
      font-weight: 600;
    }
    .email-header .meta {
      color: #666;
      font-size: 12px;
    }
    .email-body {
      max-width: 100%;
      overflow-wrap: break-word;
    }
    .email-body img {
      max-width: 100%;
      height: auto;
    }
    @media (prefers-color-scheme: dark) {
      body {
        background-color: #1a1a1a;
        color: #e0e0e0;
      }
      .email-header {
        border-bottom-color: #333;
      }
      .email-header .meta {
        color: #999;
      }
    }
  </style>
</head>
<body>
  <div class="email-header">
    <h2>${_escapeHtml(subject)}</h2>
    <div class="meta">
      <div><strong>From:</strong> ${_escapeHtml(from)}</div>
      <div><strong>To:</strong> ${_escapeHtml(to)}</div>
      <div><strong>Date:</strong> ${_formatDate(date)}</div>
    </div>
  </div>
  <div class="email-body">
    $bodyHtml
  </div>
</body>
</html>
      ''';
      
      return fullHtml;
    } catch (e) {
      debugPrint('[GmailSyncService] Error getting email body: $e');
      return null;
    }
  }
  
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>?> getAttachmentDownloadInfo(String accountId, String messageId, String filename) async {
    final account = await GoogleAuthService().ensureValidAccessToken(accountId);
    if (account == null || account.accessToken.isEmpty) {
      return null;
    }

    // Fetch the full message to find the attachment part
    final resp = await http.get(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId?format=full'),
      headers: {'Authorization': 'Bearer ${account.accessToken}'},
    );
    if (resp.statusCode != 200) return null;

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final gm = GmailMessage.fromJson(map);

    // Find the attachment part matching the filename
    String? attachmentId = _findAttachmentIdByFilename(gm.payload, filename);
    if (attachmentId == null) return null;

    // Return URL, attachmentId, and access token to avoid double token check
    return {
      'url': Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId/attachments/$attachmentId'),
      'attachmentId': attachmentId,
      'accessToken': account.accessToken,
    };
  }

  /// Recursively find attachmentId for a given filename
  String? _findAttachmentIdByFilename(MessagePayload? payload, String targetFilename) {
    if (payload == null) return null;

    // Check payload parts recursively
    if (payload.parts != null) {
      for (final part in payload.parts!) {
        final result = _findAttachmentIdInPart(part, targetFilename);
        if (result != null) return result;
      }
    }

    return null;
  }

  /// Recursively search a message part for matching attachment
  String? _findAttachmentIdInPart(MessagePart part, String targetFilename) {
    // Check if this part matches
    if (part.filename != null && 
        part.filename!.toLowerCase() == targetFilename.toLowerCase() &&
        part.body?.attachmentId != null) {
      return part.body!.attachmentId;
    }

    // Check nested parts
    if (part.parts != null) {
      for (final nestedPart in part.parts!) {
        final result = _findAttachmentIdInPart(nestedPart, targetFilename);
        if (result != null) return result;
      }
    }

    return null;
  }

  Future<void> _runBackgroundTaggingInSyncMessages(String accountId, List<GmailMessage> gmailMessages) async {
    debugPrint('[Gmail] starting background tagging for ${gmailMessages.length} messages in syncMessages');
    try {
      // Phase 1 tagging on message headers (INBOX emails only) - lightweight, header-only
      unawaited(phase1Tagging(accountId, gmailMessages));
      // Phase 2 tagging on payload in background (INBOX emails only) - heavy, body-based
      unawaited(phase2TaggingNewMessages(accountId, gmailMessages));
    } catch (e) {
      debugPrint('[Gmail] background tagging error: $e');
    }
  }
}

