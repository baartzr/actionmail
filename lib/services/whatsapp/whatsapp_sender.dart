import 'package:domail/services/whatsapp/whatsapp_sync_service.dart';
import 'package:domail/services/whatsapp/whatsapp_api_service.dart';
import 'package:flutter/foundation.dart';

/// Sends WhatsApp messages via WhatsApp Business API.
class WhatsAppSender {
  WhatsAppSender();

  final WhatsAppSyncService _whatsAppSyncService = WhatsAppSyncService();

  Future<void> sendWhatsApp({
    required String accountId,
    required String phoneNumber,
    required String message,
  }) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw ArgumentError('Message cannot be empty');
    }

    final token = await _whatsAppSyncService.getToken();
    if (token == null || token.isEmpty) {
      throw StateError('WhatsApp access token is missing');
    }

    final phoneNumberId = await _whatsAppSyncService.getPhoneNumberId();
    if (phoneNumberId == null || phoneNumberId.isEmpty) {
      throw StateError('WhatsApp phone number ID is missing. Please configure WhatsApp sync settings.');
    }

    final sanitizedNumber = _sanitizePhoneNumber(phoneNumber);
    if (sanitizedNumber.isEmpty) {
      throw ArgumentError('Invalid phone number: $phoneNumber');
    }

    try {
      final apiService = WhatsAppApiService(
        accessToken: token,
        phoneNumberId: phoneNumberId,
      );

      final messageId = await apiService.sendMessage(
        toPhoneNumber: sanitizedNumber,
        message: trimmedMessage,
      );

      debugPrint('[WhatsAppSender] Message sent successfully: $messageId to $sanitizedNumber (account $accountId)');
    } catch (e) {
      debugPrint('[WhatsAppSender] Error sending WhatsApp message: $e');
      rethrow;
    }
  }

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
}

