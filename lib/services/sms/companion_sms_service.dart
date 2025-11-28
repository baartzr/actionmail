import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:domail/data/models/message_index.dart';
import 'package:domail/services/sms/mms_attachment_service.dart';
import 'dart:io';
import 'dart:convert';

/// Service for reading SMS messages from the SMS Companion app via ContentProvider
/// This reads from the local companion app's database instead of Pushbullet
class CompanionSmsService {
  static const String _authority = 'com.domail.smscompanion.provider';
  static const String _messagesUri = 'content://$_authority/messages';
  
  // Switch to control whether messages are deleted from companion DB after fetch
  // Set to false to keep messages in companion DB (for debugging/testing)
  static const bool _deleteAfterFetch = true;
  
  /// Check if the SMS Companion app is installed and accessible
  Future<bool> isCompanionAppAvailable() async {
    if (!Platform.isAndroid) return false;
    
    try {
      // Try to query the ContentProvider to see if it's available
      final result = await _queryContentProvider(_messagesUri, limit: 1);
      return result != null;
    } catch (e) {
      debugPrint('[CompanionSms] Companion app not available: $e');
      return false;
    }
  }
  
  /// Fetch all SMS messages from the companion app
  Future<List<MessageIndex>> fetchAllMessages({
    required String accountId,
    required String accountEmail,
  }) async {
    try {
      final messages = await _queryContentProvider(_messagesUri);
      if (messages == null) {
        debugPrint('[CompanionSms] No messages found or ContentProvider unavailable');
        return [];
      }
      
      return _convertToMessageIndex(messages, accountId: accountId, accountEmail: accountEmail);
    } catch (e) {
      debugPrint('[CompanionSms] Error fetching messages: $e');
      return [];
    }
  }
  
  /// Fetch incoming SMS messages only
  Future<List<MessageIndex>> fetchIncomingMessages({
    required String accountId,
    required String accountEmail,
  }) async {
    try {
      final uri = 'content://$_authority/messages/incoming';
      final messages = await _queryContentProvider(uri);
      if (messages == null) return [];
      
      return _convertToMessageIndex(messages, accountId: accountId, accountEmail: accountEmail);
    } catch (e) {
      debugPrint('[CompanionSms] Error fetching incoming messages: $e');
      return [];
    }
  }
  
  /// Fetch outgoing SMS messages only
  Future<List<MessageIndex>> fetchOutgoingMessages({
    required String accountId,
    required String accountEmail,
  }) async {
    try {
      final uri = 'content://$_authority/messages/outgoing';
      final messages = await _queryContentProvider(uri);
      if (messages == null) return [];
      
      return _convertToMessageIndex(messages, accountId: accountId, accountEmail: accountEmail);
    } catch (e) {
      debugPrint('[CompanionSms] Error fetching outgoing messages: $e');
      return [];
    }
  }
  
  /// Query the ContentProvider and return raw message data
  Future<List<Map<String, dynamic>>?> _queryContentProvider(String uriString, {int? limit}) async {
    if (!Platform.isAndroid) return null;
    
    try {
      // Use platform channel to query ContentProvider
      // Flutter doesn't have direct ContentProvider access, so we need a platform channel
      final methodChannel = const MethodChannel('com.domail.domail/companion_sms');
      final result = await methodChannel.invokeMethod<List<dynamic>>('queryContentProvider', {
        'uri': uriString,
        'limit': limit,
      });
      
      if (result == null) return null;
      
      return result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('[CompanionSms] Error querying ContentProvider: $e');
      return null;
    }
  }
  
  /// Convert ContentProvider message data to MessageIndex
  List<MessageIndex> _convertToMessageIndex(
    List<Map<String, dynamic>> messages, {
    required String accountId,
    required String accountEmail,
  }) {
    return messages.map((msg) {
      final phoneNumber = msg['phoneNumber'] as String? ?? '';
      final messageBody = msg['message'] as String? ?? '';
      final timestamp = msg['timestamp'] as int?;
      final direction = msg['direction'] as String? ?? 'INCOMING';
      final id = msg['id'] as String? ?? '';
      final threadId = msg['threadId'] as String?;
      final read = (msg['read'] as int? ?? 0) == 1;
      final attachmentsJson = msg['attachments'] as String?;
      
      // Convert timestamp (milliseconds) to DateTime
      final dateTime = timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : DateTime.now();
      
      // Normalize phone number to avoid duplicates (e.g., 0412390363 vs +61412390363)
      // Do this early so we can use it in messageId generation
      final normalizedPhone = _normalizePhoneNumber(phoneNumber);
      
      // Parse attachments if present
      List<Map<String, dynamic>> attachments = [];
      if (attachmentsJson != null && attachmentsJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(attachmentsJson) as List;
          attachments = decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        } catch (e) {
          debugPrint('[CompanionSms] Error parsing attachments JSON: $e');
        }
      }
      
      final hasAttachments = attachments.isNotEmpty;
      
      // Store attachment info in cache if present
      if (hasAttachments) {
        final attachmentService = MmsAttachmentService();
        final attachmentInfos = attachments.map((att) => MmsAttachmentInfo.fromJson(att)).toList();
        // Store with the message ID we'll use
        final messageId = id.isNotEmpty ? id : 'sms_${normalizedPhone}_${timestamp ?? dateTime.millisecondsSinceEpoch}';
        attachmentService.storeAttachments(messageId, attachmentInfos);
      }
      
      // Determine from/to based on direction
      final isOutgoing = direction.toUpperCase() == 'OUTGOING';
      final String from;
      final String to;
      
      if (isOutgoing) {
        from = 'Me';
        to = normalizedPhone; // Use normalized phone number
      } else {
        from = normalizedPhone; // Use normalized phone number
        to = 'Me';
      }
      
      // Generate message ID if not provided (use normalized phone for consistency)
      final messageId = id.isNotEmpty ? id : 'sms_${normalizedPhone}_${timestamp ?? dateTime.millisecondsSinceEpoch}';
      
      // Use phone number as thread ID if not provided
      final finalThreadId = threadId ?? 'sms_thread_$normalizedPhone';
      
      return MessageIndex(
        id: messageId,
        threadId: finalThreadId,
        accountId: accountId,
        accountEmail: accountEmail,
        internalDate: dateTime,
        from: from,
        to: to,
        subject: messageBody, // SMS/MMS body becomes subject
        snippet: messageBody.length > 100 ? '${messageBody.substring(0, 100)}...' : messageBody,
        hasAttachments: hasAttachments,
        gmailCategories: [],
        gmailSmartLabels: [],
        isRead: read,
        isStarred: false,
        isImportant: false,
        folderLabel: isOutgoing ? 'SENT' : 'INBOX',
      );
    }).toList();
  }
  
  /// Delete a message from the companion app's database by ID
  Future<bool> deleteMessage(String messageId) async {
    if (!Platform.isAndroid) return false;
    if (!_deleteAfterFetch) {
      debugPrint('[CompanionSms] Delete after fetch is disabled, skipping deletion');
      return false;
    }
    
    try {
      final methodChannel = const MethodChannel('com.domail.domail/companion_sms');
      final result = await methodChannel.invokeMethod<bool>('deleteMessage', {
        'id': messageId,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[CompanionSms] Error deleting message: $e');
      return false;
    }
  }
  
  /// Delete multiple messages from the companion app's database
  Future<int> deleteMessages(List<String> messageIds) async {
    if (!Platform.isAndroid) return 0;
    if (!_deleteAfterFetch) {
      debugPrint('[CompanionSms] Delete after fetch is disabled, skipping deletion');
      return 0;
    }
    
    if (messageIds.isEmpty) return 0;
    
    int deletedCount = 0;
    for (final id in messageIds) {
      final success = await deleteMessage(id);
      if (success) deletedCount++;
    }
    return deletedCount;
  }

  /// Send an SMS message via the companion app
  Future<bool> sendSms(String phoneNumber, String message, {String? threadId}) async {
    if (!Platform.isAndroid) return false;
    
    try {
      final methodChannel = const MethodChannel('com.domail.domail/companion_sms');
      final result = await methodChannel.invokeMethod<bool>('sendSms', {
        'phoneNumber': phoneNumber,
        'message': message,
        if (threadId != null) 'threadId': threadId,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[CompanionSms] Error sending SMS: $e');
      return false;
    }
  }
  
  /// Send an MMS message with attachments via the companion app
  Future<bool> sendMms(
    String phoneNumber,
    String? message, {
    String? threadId,
    required List<String> attachmentUris,
  }) async {
    if (!Platform.isAndroid) return false;
    if (attachmentUris.isEmpty) {
      // Fall back to SMS if no attachments
      return sendSms(phoneNumber, message ?? '', threadId: threadId);
    }
    
    try {
      final methodChannel = const MethodChannel('com.domail.domail/companion_sms');
      final result = await methodChannel.invokeMethod<bool>('sendSms', {
        'phoneNumber': phoneNumber,
        if (message != null) 'message': message,
        if (threadId != null) 'threadId': threadId,
        'attachmentUris': attachmentUris,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('[CompanionSms] Error sending MMS: $e');
      return false;
    }
  }
  
  /// Read MMS attachment data from a content URI
  Future<Uint8List?> readMmsAttachment(String uri) async {
    if (!Platform.isAndroid) return null;
    
    try {
      final methodChannel = const MethodChannel('com.domail.domail/companion_sms');
      final result = await methodChannel.invokeMethod<List<int>>('readMmsAttachment', {
        'uri': uri,
      });
      if (result != null) {
        return Uint8List.fromList(result);
      }
      return null;
    } catch (e) {
      debugPrint('[CompanionSms] Error reading MMS attachment: $e');
      return null;
    }
  }

  /// Normalize phone number for consistent thread grouping
  /// Handles formats like: 0412390363, +61412390363, 61412390363
  static String _normalizePhoneNumber(String phoneNumber) {
    // Remove spaces, dashes, parentheses, dots
    var normalized = phoneNumber
        .replaceAll(RegExp(r'[\s\-\(\)\.]'), '')
        .replaceAll(RegExp(r'^\+'), ''); // Remove leading +
    
    // Convert Australian mobile format: 04... to 614...
    // This handles the common case where one message has 0412... and another has +61412...
    if (normalized.startsWith('04') && normalized.length == 10) {
      normalized = '61${normalized.substring(1)}';
    }
    
    return normalized.toLowerCase();
  }
}

