import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:domail/services/whatsapp/whatsapp_message_converter.dart';

/// Service for interacting with WhatsApp Business API
/// Handles sending messages and receiving webhook events
class WhatsAppApiService {
  final String accessToken;
  final String phoneNumberId;
  
  static const String _baseUrl = 'https://graph.facebook.com/v18.0';

  WhatsAppApiService({
    required this.accessToken,
    required this.phoneNumberId,
  });

  /// Send a text message via WhatsApp Business API
  Future<String> sendMessage({
    required String toPhoneNumber, // Recipient's phone number with country code
    required String message,
  }) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw ArgumentError('Message cannot be empty');
    }

    final sanitizedNumber = _sanitizePhoneNumber(toPhoneNumber);
    if (sanitizedNumber.isEmpty) {
      throw ArgumentError('Invalid phone number: $toPhoneNumber');
    }

    final url = '$_baseUrl/$phoneNumberId/messages';
    
    final payload = jsonEncode({
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': sanitizedNumber,
      'type': 'text',
      'text': {
        'preview_url': false,
        'body': trimmedMessage,
      },
    });

    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: payload,
      );

      if (resp.statusCode != 200) {
        final errorBody = resp.body;
        debugPrint('[WhatsAppAPI] Failed response: ${resp.statusCode} $errorBody');
        throw StateError('WhatsApp API failed (status ${resp.statusCode}): $errorBody');
      }

      final responseJson = jsonDecode(resp.body) as Map<String, dynamic>;
      final messageId = responseJson['messages']?[0]?['id'] as String?;
      
      if (messageId == null) {
        throw StateError('No message ID returned from WhatsApp API');
      }

      debugPrint('[WhatsAppAPI] Message sent successfully: $messageId to $sanitizedNumber');
      return messageId;
    } catch (e) {
      debugPrint('[WhatsAppAPI] Error sending message: $e');
      rethrow;
    }
  }

  /// Parse a WhatsApp Business API webhook event
  /// Returns a list of WhatsAppMessageEvent objects
  static List<WhatsAppMessageEvent> parseWebhookEvent(Map<String, dynamic> event) {
    final events = <WhatsAppMessageEvent>[];

    try {
      // WhatsApp webhook structure: { "entry": [{ "changes": [...] }] }
      final entries = event['entry'] as List<dynamic>?;
      if (entries == null || entries.isEmpty) {
        return events;
      }

      for (final entry in entries) {
        if (entry is! Map<String, dynamic>) continue;
        
        final changes = entry['changes'] as List<dynamic>?;
        if (changes == null || changes.isEmpty) continue;

        for (final change in changes) {
          if (change is! Map<String, dynamic>) continue;
          
          final value = change['value'] as Map<String, dynamic>?;
          if (value == null) continue;

          // Check if this is a messages event
          final messages = value['messages'] as List<dynamic>?;
          if (messages == null || messages.isEmpty) continue;

          for (final msg in messages) {
            if (msg is! Map<String, dynamic>) continue;

            // Extract message details
            final from = msg['from'] as String?;
            final messageId = msg['id'] as String?;
            final timestamp = msg['timestamp'] as String?;
            final messageType = msg['type'] as String?;

            // Only process text messages for now
            if (messageType != 'text') {
              debugPrint('[WhatsAppAPI] Skipping non-text message type: $messageType');
              continue;
            }

            final text = msg['text'] as Map<String, dynamic>?;
            final messageText = text?['body'] as String?;

            if (from == null || messageId == null || messageText == null) {
              debugPrint('[WhatsAppAPI] Missing required fields in message');
              continue;
            }

            // Check if message is from the user (sent by us)
            // In WhatsApp Business API, we need to check the context or contacts
            final contacts = value['contacts'] as List<dynamic>?;
            String? contactName;
            if (contacts != null && contacts.isNotEmpty) {
              final contact = contacts.first as Map<String, dynamic>?;
              contactName = contact?['profile']?['name'] as String?;
            }

            // Parse timestamp
            DateTime? messageTimestamp;
            if (timestamp != null) {
              try {
                final seconds = int.parse(timestamp);
                messageTimestamp = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
              } catch (e) {
                debugPrint('[WhatsAppAPI] Error parsing timestamp: $e');
                messageTimestamp = DateTime.now();
              }
            } else {
              messageTimestamp = DateTime.now();
            }

            events.add(WhatsAppMessageEvent(
              phoneNumber: from,
              messageId: messageId,
              messageText: messageText,
              timestamp: messageTimestamp,
              contactName: contactName,
              isFromMe: false, // Incoming messages from webhook are not from us
            ));
          }

          // Also check for status updates (sent message confirmations)
          final statuses = value['statuses'] as List<dynamic>?;
          if (statuses != null && statuses.isNotEmpty) {
            // Status updates indicate messages we sent
            // We can use these to mark sent messages as read or track delivery
            for (final status in statuses) {
              if (status is! Map<String, dynamic>) continue;
              final messageId = status['id'] as String?;
              final statusValue = status['status'] as String?; // sent, delivered, read
              debugPrint('[WhatsAppAPI] Message status update: $messageId -> $statusValue');
            }
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[WhatsAppAPI] Error parsing webhook event: $e');
      debugPrint('[WhatsAppAPI] Stack trace: $stackTrace');
      debugPrint('[WhatsAppAPI] Event data: ${jsonEncode(event)}');
    }

    return events;
  }

  /// Sanitize phone number for WhatsApp API
  /// WhatsApp requires phone numbers in E.164 format (e.g., +1234567890)
  String _sanitizePhoneNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    
    // Remove common formatting characters but keep + sign
    var digits = trimmed.replaceAll(RegExp(r'[^\d+]'), '');
    
    // Ensure it starts with + for international format
    if (!digits.startsWith('+')) {
      // If starts with 00, replace with +
      if (digits.startsWith('00')) {
        digits = '+${digits.substring(2)}';
      } else {
        // Assume it's a local number, might need country code prefix
        // For now, just add + if missing
        digits = '+$digits';
      }
    }
    
    return digits;
  }

  /// Verify webhook challenge (for webhook setup)
  static bool verifyWebhookChallenge({
    required String mode,
    required String token,
    required String challenge,
    required String verifyToken,
  }) {
    // WhatsApp webhook verification
    // GET request with query params: hub.mode, hub.verify_token, hub.challenge
    if (mode == 'subscribe' && token == verifyToken) {
      return true;
    }
    return false;
  }
}

