import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:actionmail/data/models/gmail_message.dart';
import 'package:actionmail/data/models/message_index.dart';
import 'package:actionmail/data/repositories/message_repository.dart';
import 'package:actionmail/services/actions/action_extractor.dart';
import 'package:actionmail/services/auth/google_auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Service to simulate Gmail API sync
/// In production, this would call the actual Gmail API
class GmailSyncService {
  final MessageRepository _repo = MessageRepository();
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
    final messages = <GmailMessage>[];
    final items = (listMap['messages'] as List<dynamic>?) ?? [];
    for (final item in items) {
      final id = (item as Map<String, dynamic>)['id'] as String;
      final msgResp = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=full'),
        headers: headers,
      );
      if (msgResp.statusCode != 200) continue;
      final msgMap = jsonDecode(msgResp.body) as Map<String, dynamic>;
      messages.add(GmailMessage.fromJson(msgMap));
    }
    return messages;
  }
  
  /// Convert Gmail API messages to MessageIndex and apply heuristics
  /// This simulates the process: Gmail API -> MessageIndex -> Action Detection
  Future<List<MessageIndex>> syncMessages(String accountId, {String folderLabel = 'INBOX'}) async {
    // Download from Gmail API
    final gmailMessages = await downloadMessages(accountId, label: folderLabel);
    
    // Convert Gmail format to MessageIndex
    final messageIndexes = gmailMessages.map((gmailMsg) => gmailMsg.toMessageIndex(accountId)).toList();

    // Apply sender preferences (auto-apply local tag)
    final senderPrefs = await _repo.getAllSenderPrefs();
    for (var i = 0; i < messageIndexes.length; i++) {
      final m = messageIndexes[i];
      final email = _extractEmail(m.from);
      final pref = senderPrefs[email];
      if (pref != null && pref.isNotEmpty) {
        messageIndexes[i] = m.copyWith(localTagPersonal: pref);
      }
    }
    
    // Note: Action detection moved to Phase 2 (deeper body-based detection)
    var enriched = messageIndexes;

    // Preserve local fields when present locally
    final idMap = await _repo.getByIds(accountId, enriched.map((e) => e.id).toList());
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
        if (actDate != m.actionDate || actText != m.actionInsightText) {
          return m.copyWith(actionDate: actDate, actionInsightText: actText);
        }
      }
      return m;
    }).toList();
    
    // Persist to DB
    await _repo.upsertMessages(enriched);
    
    // Identify NEW emails (not in DB before this sync)
    final existingIds = idMap.keys.toSet();
    final newGmailMessages = gmailMessages.where((gm) => !existingIds.contains(gm.id)).toList();
    
    // Phase 1 local tagging using Gmail message headers and categories (NEW emails only)
    if (newGmailMessages.isNotEmpty) {
      await _phase1Tagging(accountId, newGmailMessages);
    }
    
    // Phase 2 tagging on new messages (run in background after emails are loaded)
    if (newGmailMessages.isNotEmpty) {
      unawaited(_phase2TaggingNewMessages(accountId, newGmailMessages));
    }
    
    // Save the latest historyId for future incremental syncs
    String? latestHistoryId;
    for (final gm in gmailMessages) {
      if (gm.historyId != null) {
        latestHistoryId = gm.historyId;
      }
    }
    if (latestHistoryId != null) {
      await _repo.setLastHistoryId(accountId, latestHistoryId);
    }
    
    // Return from DB filtered by folder
    final stored = await _repo.getByFolder(accountId, folderLabel);
    return stored;
    // TODO: Apply action detection heuristics when implemented
  }

  /// Incremental sync using Gmail History API: fetch changes since last historyId
  Future<void> incrementalSync(String accountId) async {
    final account = await GoogleAuthService().ensureValidAccessToken(accountId);
    final accessToken = account?.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;
    final lastHistoryId = await _repo.getLastHistoryId(accountId);
    if (lastHistoryId == null) return; // no baseline yet

    debugPrint('[Gmail] incrementalSync account=$accountId historyId=$lastHistoryId');
    String? pageToken;
    String? latestHistoryId;
    final gmailMessagesToTag = <GmailMessage>[];
    do {
      final uri = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/history').replace(queryParameters: {
        'startHistoryId': lastHistoryId,
        if (pageToken != null) 'pageToken': pageToken!,
        'historyTypes': 'messageAdded,labelAdded,labelRemoved',
        'maxResults': '100',
      });
      final resp = await http.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
      if (resp.statusCode != 200) break;
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      latestHistoryId = (map['historyId']?.toString()) ?? latestHistoryId;
      final history = (map['history'] as List<dynamic>?) ?? [];
      for (final h in history) {
        final hist = h as Map<String, dynamic>;
        final messagesAdded = (hist['messagesAdded'] as List<dynamic>?) ?? [];
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
            await _repo.upsertMessages([gi]);
            gmailMessagesToTag.add(GmailMessage.fromJson(msgMap));
          }
        }
        // For labels added/removed, refresh the message to get current labels and update
        final ids = <String>{};
        for (final la in (hist['labelsAdded'] as List<dynamic>?) ?? []) {
          final msg = (la as Map<String, dynamic>)['message'] as Map<String, dynamic>;
          ids.add(msg['id'] as String);
        }
        for (final lr in (hist['labelsRemoved'] as List<dynamic>?) ?? []) {
          final msg = (lr as Map<String, dynamic>)['message'] as Map<String, dynamic>;
          ids.add(msg['id'] as String);
        }
        for (final id in ids) {
          final fullResp = await http.get(
            Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id?format=full'),
            headers: {'Authorization': 'Bearer $accessToken'},
          );
          if (fullResp.statusCode == 200) {
            final msgMap = jsonDecode(fullResp.body) as Map<String, dynamic>;
            final gi = GmailMessage.fromJson(msgMap).toMessageIndex(accountId);
            await _repo.upsertMessages([gi]);
            // DO NOT add to gmailMessagesToTag - these are existing messages with label changes, not new messages
          }
        }
      }
      pageToken = map['nextPageToken'] as String?;
    } while (pageToken != null);

    if (latestHistoryId != null) {
      await _repo.setLastHistoryId(accountId, latestHistoryId);
    }
    // Phase 1 tagging on new messages from incremental sync
    debugPrint('[Gmail] incrementalSync found ${gmailMessagesToTag.length} new messages');
    if (gmailMessagesToTag.isNotEmpty) {
      await _phase1Tagging(accountId, gmailMessagesToTag);
      // Phase 2 tagging on new messages only
      await _phase2TaggingNewMessages(accountId, gmailMessagesToTag);
    }
  }

  // Apply pending Gmail modifications with retries
  Future<void> processPendingOps() async {
    final pending = await _repo.getPendingOps(limit: 20);
    for (final op in pending) {
      final int id = op['id'] as int;
      final String accountId = op['accountId'] as String;
      final String messageId = op['messageId'] as String;
      final String action = op['action'] as String;
      final int retries = (op['retries'] as int?) ?? 0;
      try {
        await _applyLabelChange(accountId, messageId, action);
        await _repo.markOpDone(id);
      } catch (e) {
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

  Future<void> _applyLabelChange(String accountId, String messageId, String action) async {
    final auth = GoogleAuthService();
    var account = await auth.ensureValidAccessToken(accountId);
    var accessToken = account?.accessToken;
    // ensureValidAccessToken already refreshed if needed
    if (accessToken == null || accessToken.isEmpty) {
      // Attempt interactive re-auth once to obtain fresh tokens
      // ignore: avoid_print
      print('[gmail] attempting reauth for account=$accountId');
      account = await auth.reauthenticateAccount(accountId) ?? account;
      accessToken = account?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token');
      }
    }

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
      throw Exception('Gmail modify failed: ${resp.statusCode}');
    }
  }

  Map<String, dynamic> _buildModifyBody(String action) {
    // Support meta in action like 'restore:INBOX'
    final parts = action.split(':');
    final base = parts.first;
    final meta = parts.length > 1 ? parts[1] : null;
    switch (base) {
      case 'trash':
        // Add TRASH and remove exactly the source primary label
        if (meta == 'SENT') return {'addLabelIds': ['TRASH'], 'removeLabelIds': ['SENT']};
        if (meta == 'SPAM') return {'addLabelIds': ['TRASH'], 'removeLabelIds': ['SPAM']};
        // Default to INBOX
        return {'addLabelIds': ['TRASH'], 'removeLabelIds': ['INBOX']};
      case 'archive':
        // Remove exactly the source primary label (default INBOX)
        if (meta == 'SENT') return {'removeLabelIds': ['SENT']};
        if (meta == 'SPAM') return {'removeLabelIds': ['SPAM']};
        if (meta == 'TRASH') return {'removeLabelIds': ['TRASH']};
        return {'removeLabelIds': ['INBOX']};
      case 'restore':
        if (meta == 'INBOX') {
          return {'removeLabelIds': ['TRASH'], 'addLabelIds': ['INBOX']};
        }
        if (meta == 'SENT') {
          return {'removeLabelIds': ['TRASH'], 'addLabelIds': ['SENT']};
        }
        return {'removeLabelIds': ['TRASH']};
      case 'star':
        return {'addLabelIds': ['STARRED']};
      case 'unstar':
        return {'removeLabelIds': ['STARRED']};
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
    // Collect HTML/plain bodies from parts tree (MessagePayload.body is not used here)
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
    // Regex for unsubscribe-like links (normal string with escapes)
    final regex = RegExp("href=[\\\"']([^\\\"']*(?:unsubscribe|opt-?out|preferences)[^\\\"']*)[\\\"']", caseSensitive: false);
    for (final body in bodies) {
      final match = regex.firstMatch(body);
      if (match != null) return match.group(1);
    }
    return null;
  }

  Future<void> _phase1Tagging(String accountId, List<GmailMessage> gmailMessages) async {
    // Lightweight: headers-only to avoid slowing load
    // Phase 1 tagging: checks email header and sets subs local tag if subscription email
    // This happens only once when new email arrives
    for (final gm in gmailMessages) {
      final headers = gm.payload?.headers ?? [];
      final hasListHeader = headers.any((h) {
        final name = h.name.toLowerCase();
        return name == 'list-unsubscribe' || name == 'list-id';
      });
      if (hasListHeader) {
        // Extract a usable unsubscribe link from List-Unsubscribe header if present
        final unsubLink = _extractUnsubFromHeader(headers);
        await _repo.updateLocalClassification(gm.id, subs: true, unsubLink: unsubLink);
      }
    }
  }
  
  Future<void> _phase2TaggingNewMessages(String accountId, List<GmailMessage> gmailMessages) async {
    // Phase 2 tagging: performs extra checks on emails that DO NOT have the subs tag already set
    // Also performs action detection with deeper body-based analysis
    debugPrint('[Phase2] Starting Phase 2 tagging for ${gmailMessages.length} messages');
    
    // First check existing messages in DB to see which ones already have subs tag from phase 1 or action from previous run
    final messageIds = gmailMessages.map((gm) => gm.id).toList();
    final existingMessages = await _repo.getByIds(accountId, messageIds);
    debugPrint('[Phase2] Loaded ${existingMessages.length} existing messages from DB');
    
    for (final gm in gmailMessages) {
      final existing = existingMessages[gm.id];
      
      final headers = gm.payload?.headers ?? [];
      final subj = (headers.firstWhere((h) => h.name.toLowerCase() == 'subject', orElse: () => const MessageHeader(name: '', value: '')).value ?? '').toLowerCase();
      final from = (headers.firstWhere((h) => h.name.toLowerCase() == 'from', orElse: () => const MessageHeader(name: '', value: '')).value ?? '').toLowerCase();
      final snippet = gm.snippet ?? '';
      
      // === SUBSCRIPTION DETECTION ===
      // Skip if email already has subs tag from phase 1
      if (existing == null || !existing.subsLocal) {
        final cats = [...gm.labelIds ?? []].map((e) => e.toLowerCase()).toList();
        
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
          
          // If unsubscribe link is found, update email in DB to add subs tag plus unsubscribe link
          if (unsubLink != null && unsubLink.isNotEmpty) {
            await _repo.updateLocalClassification(gm.id, subs: true, unsubLink: unsubLink);
          }
          // If unsubscribe link is not found, do nothing
        }
      }
      
      // === ACTION DETECTION ===
      // Skip if email already has an action (don't overwrite user edits)
      if (existing == null || existing.actionDate == null) {
        debugPrint('[Phase2] Checking action for message ${gm.id}: subject="$subj", snippet="${snippet.substring(0, snippet.length > 50 ? 50 : snippet.length)}"');
        
        // Quick check: is this an action candidate? (lightweight, no body download)
        final isActionCandidate = ActionExtractor.isActionCandidate(subj, snippet);
        debugPrint('[Phase2] Action candidate check: $isActionCandidate for message ${gm.id}');
        
        if (isActionCandidate) {
          // Quick detection on subject/snippet first (low confidence)
          final quickResult = ActionExtractor.detectQuick(subj, snippet);
          debugPrint('[Phase2] Quick detection result for ${gm.id}: ${quickResult != null ? "date=${quickResult.actionDate}, confidence=${quickResult.confidence}, text=${quickResult.insightText}" : "null"}');
          
          if (quickResult != null) {
            // Download email body for deeper detection (higher confidence)
            debugPrint('[Phase2] Downloading body for ${gm.id}...');
            final bodyContent = await _downloadEmailBody(accountId, gm.id);
            debugPrint('[Phase2] Body download for ${gm.id}: ${bodyContent != null ? "success (${bodyContent.length} chars)" : "failed"}');
            
            if (bodyContent != null && bodyContent.isNotEmpty) {
              // Deep detection with full body content
              final deepResult = ActionExtractor.detectWithBody(subj, snippet, bodyContent);
              debugPrint('[Phase2] Deep detection result for ${gm.id}: ${deepResult != null ? "date=${deepResult.actionDate}, confidence=${deepResult.confidence}, text=${deepResult.insightText}" : "null"}');
              
              if (deepResult != null && deepResult.confidence >= 0.6) {
                // Use deep result if confidence is high enough
                debugPrint('[Phase2] Saving deep result for ${gm.id} (confidence ${deepResult.confidence} >= 0.6)');
                await _repo.updateAction(gm.id, deepResult.actionDate, deepResult.insightText, deepResult.confidence);
              } else if (quickResult.confidence >= 0.5) {
                // Fall back to quick result if deep detection didn't improve confidence
                debugPrint('[Phase2] Saving quick result for ${gm.id} (confidence ${quickResult.confidence} >= 0.5)');
                await _repo.updateAction(gm.id, quickResult.actionDate, quickResult.insightText, quickResult.confidence);
              } else {
                debugPrint('[Phase2] Skipping ${gm.id}: deep result confidence ${deepResult?.confidence ?? "null"} < 0.6, quick confidence ${quickResult.confidence} < 0.5');
              }
            } else if (quickResult.confidence >= 0.5) {
              // If body download fails, use quick result
              debugPrint('[Phase2] Body download failed, saving quick result for ${gm.id} (confidence ${quickResult.confidence} >= 0.5)');
              await _repo.updateAction(gm.id, quickResult.actionDate, quickResult.insightText, quickResult.confidence);
            } else {
              debugPrint('[Phase2] Body download failed and quick confidence ${quickResult.confidence} < 0.5, skipping ${gm.id}');
            }
          } else {
            debugPrint('[Phase2] Quick detection returned null for ${gm.id}, skipping');
          }
        }
      } else {
        debugPrint('[Phase2] Skipping action detection for ${gm.id}: already has action (date=${existing.actionDate})');
      }
    }
    
    debugPrint('[Phase2] Phase 2 tagging completed');
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

  String _extractEmail(String from) {
    final regex = RegExp(r'<([^>]+)>');
    final match = regex.firstMatch(from);
    if (match != null) return match.group(1)!.trim();
    if (from.contains('@')) return from.trim();
    return '';
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
    String? cc,
    String? bcc,
    String? replyTo,
    String? inReplyTo,
    List<String>? references,
    List<File>? attachments,
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

      // Get the sender's email address (the account's email)
      final senderEmail = account.email;

      // Build the raw email message
      final rawMessage = StringBuffer();
      
      final hasAttachments = attachments != null && attachments.isNotEmpty;
      
      // Generate a boundary for multipart messages if we have attachments
      final boundary = hasAttachments ? '----=_Part_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}' : null;
      
      // Headers
      rawMessage.writeln('From: $senderEmail');
      rawMessage.writeln('To: $to');
      if (cc != null && cc.trim().isNotEmpty) {
        rawMessage.writeln('Cc: $cc');
      }
      if (bcc != null && bcc.trim().isNotEmpty) {
        rawMessage.writeln('Bcc: $bcc');
      }
      rawMessage.writeln('Subject: $subject');
      
      // Reply headers
      if (inReplyTo != null) {
        rawMessage.writeln('In-Reply-To: $inReplyTo');
      }
      if (references != null && references.isNotEmpty) {
        rawMessage.writeln('References: ${references.join(' ')}');
      }
      
      // MIME type headers
      if (hasAttachments) {
        rawMessage.writeln('MIME-Version: 1.0');
        rawMessage.writeln('Content-Type: multipart/mixed; boundary="$boundary"');
        rawMessage.writeln('');
        rawMessage.writeln('This is a multi-part message in MIME format.');
        rawMessage.writeln('');
        rawMessage.writeln('--$boundary');
      }
      
      // Message body
      rawMessage.writeln('Content-Type: text/plain; charset=UTF-8');
      rawMessage.writeln('Content-Transfer-Encoding: 7bit');
      rawMessage.writeln('');
      rawMessage.writeln(body);
      
      // Add attachments if any
      if (hasAttachments) {
        for (final file in attachments!) {
          if (!await file.exists()) continue;
          
          final fileBytes = await file.readAsBytes();
          final fileName = file.path.split(Platform.pathSeparator).last;
          final fileExtension = fileName.split('.').last.toLowerCase();
          
          // Determine MIME type based on extension
          String mimeType = 'application/octet-stream';
          if (fileExtension == 'pdf') {
            mimeType = 'application/pdf';
          } else if (fileExtension == 'jpg' || fileExtension == 'jpeg') {
            mimeType = 'image/jpeg';
          } else if (fileExtension == 'png') {
            mimeType = 'image/png';
          } else if (fileExtension == 'gif') {
            mimeType = 'image/gif';
          } else if (fileExtension == 'txt') {
            mimeType = 'text/plain';
          } else if (fileExtension == 'html' || fileExtension == 'htm') {
            mimeType = 'text/html';
          } else if (fileExtension == 'doc' || fileExtension == 'docx') {
            mimeType = 'application/msword';
          } else if (fileExtension == 'xls' || fileExtension == 'xlsx') {
            mimeType = 'application/vnd.ms-excel';
          }
          
          rawMessage.writeln('');
          rawMessage.writeln('--$boundary');
          rawMessage.writeln('Content-Type: $mimeType; name="$fileName"');
          rawMessage.writeln('Content-Disposition: attachment; filename="$fileName"');
          rawMessage.writeln('Content-Transfer-Encoding: base64');
          rawMessage.writeln('');
          rawMessage.writeln(base64Encode(fileBytes));
        }
        
        rawMessage.writeln('');
        rawMessage.writeln('--$boundary--');
      }

      // Encode to base64url (URL-safe base64, padding removed)
      final rawBase64Url = base64UrlEncode(utf8.encode(rawMessage.toString()))
          .replaceAll('=', '');

      // Send via Gmail API
      final resp = await http.post(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/send'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'raw': rawBase64Url}),
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
    debugPrint('[Attachments] Found ${filenames.length} attachments for message $messageId: $filenames');
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
    
    // Exclude text/html and text/plain as they're message content, not attachments
    if (mimeType == 'text/html' || mimeType == 'text/plain') {
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
}

